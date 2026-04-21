#!/usr/bin/env bash
# =============================================================================
# scripts/import-from-csv.sh
# =============================================================================
# Import the Falling Fruit locations CSV (plain, .gz, or .bz2) into the local
# PostgreSQL/PostGIS database.
#
# Usage:
#   scripts/import-from-csv.sh [PATH_TO_CSV]
#
# Environment variables (all optional, with defaults):
#   DB_HOST   — PostgreSQL host         (default: localhost)
#   DB_PORT   — PostgreSQL port         (default: 5432)
#   DB_USER   — PostgreSQL user         (default: ffuser)
#   DB_NAME   — PostgreSQL database     (default: falling_fruit)
#   PGPASSWORD — password (or use ~/.pgpass)
#
# The script is idempotent: it uses ON CONFLICT upserts and drops staging
# tables at the end so it is safe to run more than once.
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CSV_SOURCE="${1:-data/locations.csv.bz2}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-ffuser}"
DB_NAME="${DB_NAME:-falling_fruit}"

PSQL_BASE="psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME} -v ON_ERROR_STOP=1"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[import-from-csv] $*"; }
err()  { echo "[import-from-csv] ERROR: $*" >&2; exit 1; }

command -v psql  >/dev/null 2>&1 || err "psql is not installed or not on PATH"
command -v python3 >/dev/null 2>&1 || err "python3 is not installed or not on PATH"

# ---------------------------------------------------------------------------
# Decompress input file if necessary
# ---------------------------------------------------------------------------
if [[ ! -f "$CSV_SOURCE" ]]; then
    err "File not found: $CSV_SOURCE"
fi

TMPCSV="$(mktemp /tmp/ff-locations-XXXXXX.csv)"
cleanup() { rm -f "$TMPCSV"; }
trap cleanup EXIT

log "Input file: $CSV_SOURCE"
case "$CSV_SOURCE" in
    *.bz2)
        log "Decompressing bzip2 …"
        command -v bzip2 >/dev/null 2>&1 || err "bzip2 is not installed"
        bzip2 -dc "$CSV_SOURCE" > "$TMPCSV"
        ;;
    *.gz)
        log "Decompressing gzip …"
        gunzip -c "$CSV_SOURCE" > "$TMPCSV"
        ;;
    *.csv)
        cp "$CSV_SOURCE" "$TMPCSV"
        ;;
    *)
        err "Unsupported file type: $CSV_SOURCE (expected .csv, .gz, or .bz2)"
        ;;
esac

HEADER_LINE="$(head -n1 "$TMPCSV")"
log "CSV header: $HEADER_LINE"

# ---------------------------------------------------------------------------
# Load CSV into a raw staging table (all text) via COPY
# ---------------------------------------------------------------------------
# The CSV must have a header row. We derive column names from it so the COPY
# command is robust to different header orderings.

log "Creating raw staging table …"
$PSQL_BASE -c "
DROP TABLE IF EXISTS _ff_staging_raw;
CREATE UNLOGGED TABLE _ff_staging_raw (
    id              TEXT,
    types           TEXT,
    description     TEXT,
    lat             TEXT,
    lng             TEXT,
    season_start    TEXT,
    season_stop     TEXT,
    no_season       TEXT,
    unverified      TEXT,
    photo_url       TEXT,
    import_id       TEXT,
    created_at      TEXT,
    updated_at      TEXT,
    address         TEXT,
    city            TEXT,
    state           TEXT,
    country         TEXT,
    access          TEXT,
    geometry        TEXT
);
"

# Build a dynamic COPY statement that matches only the columns present in the CSV
COPY_COLS="$(python3 - <<'PY'
import sys, csv
with open("'"$TMPCSV"'", newline='', encoding='utf-8-sig') as f:
    headers = next(csv.reader(f))
known = {
    'id','types','description','lat','lng','season_start','season_stop',
    'no_season','unverified','photo_url','import_id','created_at','updated_at',
    'address','city','state','country','access','geometry',
}
# Normalise: lower-case, strip BOM/whitespace
cols = [h.strip().lstrip('\ufeff').lower() for h in headers]
# Map common aliases
alias = {
    'latitude': 'lat', 'longitude': 'lng',
    'type_ids': 'types', 'type_names': 'types',
    'photos': 'photo_url', 'photo': 'photo_url',
}
cols = [alias.get(c, c) for c in cols]
filtered = [c for c in cols if c in known]
print(','.join(filtered))
PY
)"

if [[ -z "$COPY_COLS" ]]; then
    err "Could not determine CSV columns from header: $HEADER_LINE"
fi

log "Mapped CSV columns: $COPY_COLS"

log "Loading CSV into staging table (this may take a while for large files) …"
$PSQL_BASE -c "\COPY _ff_staging_raw($COPY_COLS) FROM '$TMPCSV' WITH (FORMAT csv, HEADER true, NULL '')"

ROW_COUNT="$($PSQL_BASE -tAc "SELECT COUNT(*) FROM _ff_staging_raw")"
log "Staged ${ROW_COUNT} rows"

# ---------------------------------------------------------------------------
# SQL transform: types → locations → location_types
# ---------------------------------------------------------------------------
log "Running SQL transforms …"
$PSQL_BASE <<'SQL'
-- -----------------------------------------------------------------------
-- 1. Parse typed staging table from raw strings
-- -----------------------------------------------------------------------
DROP TABLE IF EXISTS _ff_staging;
CREATE UNLOGGED TABLE _ff_staging AS
SELECT
    -- id: prefer explicit id column, fall back to null (auto-assign)
    NULLIF(trim(id), '')::bigint                              AS location_id,

    -- lat/lng: try lat/lng columns first, then parse POINT(lon lat) from geometry
    CASE
        WHEN NULLIF(trim(lat), '') IS NOT NULL
            THEN trim(lat)::double precision
        WHEN NULLIF(trim(geometry), '') IS NOT NULL
            THEN (regexp_matches(
                    geometry,
                    'POINT\s*\(\s*([0-9.\-]+)\s+([0-9.\-]+)\s*\)'))[2]::double precision
    END                                                        AS lat,

    CASE
        WHEN NULLIF(trim(lng), '') IS NOT NULL
            THEN trim(lng)::double precision
        WHEN NULLIF(trim(geometry), '') IS NOT NULL
            THEN (regexp_matches(
                    geometry,
                    'POINT\s*\(\s*([0-9.\-]+)\s+([0-9.\-]+)\s*\)'))[1]::double precision
    END                                                        AS lng,

    NULLIF(trim(types), '')                                   AS types_text,
    NULLIF(trim(description), '')                             AS description,
    NULLIF(trim(season_start), '')::int                       AS season_start,
    NULLIF(trim(season_stop), '')::int                        AS season_stop,
    COALESCE(NULLIF(trim(no_season), '')::boolean,  false)    AS no_season,
    COALESCE(NULLIF(trim(unverified), '')::boolean, false)    AS unverified,
    NULLIF(trim(photo_url), '')                               AS photo_url,
    NULLIF(trim(access), '')::int                             AS access,
    NULLIF(trim(import_id), '')::int                          AS import_id,
    CASE
        WHEN NULLIF(trim(created_at), '') IS NOT NULL
            THEN trim(created_at)::timestamptz
        ELSE NOW()
    END                                                        AS created_at
FROM _ff_staging_raw;

-- Drop rows where we couldn't determine coordinates
DELETE FROM _ff_staging WHERE lat IS NULL OR lng IS NULL;

-- -----------------------------------------------------------------------
-- 2. Record the import batch
-- -----------------------------------------------------------------------
INSERT INTO imports (name, url, location_count, created_at)
VALUES (
    'locations.csv bulk import',
    'https://fallingfruit.org/locations.csv.bz2',
    (SELECT COUNT(*) FROM _ff_staging),
    NOW()
);

-- -----------------------------------------------------------------------
-- 3. Upsert types
--    types_text may be a comma- or pipe-separated list of names or numeric ids
-- -----------------------------------------------------------------------
CREATE TEMP TABLE _ff_type_tokens AS
SELECT DISTINCT trim(token) AS token
FROM _ff_staging,
     regexp_split_to_table(COALESCE(types_text, ''), '[,|]') AS token
WHERE trim(token) <> '';

-- Insert numeric-id types that don't yet exist.
-- NOTE: en_name is temporarily set to a placeholder "Type <id>"; update
-- en_name values later from a reference source if needed.
INSERT INTO types (id, en_name, created_at)
SELECT token::int, 'Type ' || token, NOW()
FROM _ff_type_tokens
WHERE token ~ '^[0-9]+$'
  AND NOT EXISTS (SELECT 1 FROM types t WHERE t.id = token::int)
ON CONFLICT (id) DO NOTHING;

-- Insert name-based types that don't yet exist
INSERT INTO types (en_name, created_at)
SELECT token, NOW()
FROM _ff_type_tokens
WHERE token !~ '^[0-9]+$'
  AND NOT EXISTS (SELECT 1 FROM types t WHERE lower(t.en_name) = lower(token))
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------------------
-- 4. Upsert locations
-- -----------------------------------------------------------------------
INSERT INTO locations (
    id, lat, lng, description, season_start, season_stop,
    no_season, photo_url, unverified, access, import_id, created_at
)
SELECT
    location_id,
    lat, lng, description, season_start, season_stop,
    no_season, photo_url, unverified,
    COALESCE(access, 1),  -- access: 1=public (default), 2=private, 3=restricted
    import_id,
    created_at
FROM _ff_staging
ON CONFLICT (id) DO UPDATE
    SET lat          = EXCLUDED.lat,
        lng          = EXCLUDED.lng,
        description  = EXCLUDED.description,
        season_start = EXCLUDED.season_start,
        season_stop  = EXCLUDED.season_stop,
        no_season    = EXCLUDED.no_season,
        photo_url    = EXCLUDED.photo_url,
        unverified   = EXCLUDED.unverified,
        access       = EXCLUDED.access,
        updated_at   = NOW();

-- -----------------------------------------------------------------------
-- 5. Upsert location_types (many-to-many)
-- -----------------------------------------------------------------------
INSERT INTO location_types (location_id, type_id)
SELECT DISTINCT
    s.location_id,
    CASE
        WHEN trim(token) ~ '^[0-9]+$'
            THEN trim(token)::int
        ELSE (SELECT id FROM types t WHERE lower(t.en_name) = lower(trim(token)) LIMIT 1)
    END AS type_id
FROM _ff_staging s,
     regexp_split_to_table(COALESCE(s.types_text, ''), '[,|]') AS token
WHERE trim(token) <> ''
  AND s.location_id IS NOT NULL
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------------------
-- 6. Cleanup staging tables
-- -----------------------------------------------------------------------
DROP TABLE IF EXISTS _ff_staging;
DROP TABLE IF EXISTS _ff_staging_raw;
DROP TABLE IF EXISTS _ff_type_tokens;
SQL

LOCATION_COUNT="$($PSQL_BASE -tAc "SELECT COUNT(*) FROM locations")"
log "Import complete. locations table now has ${LOCATION_COUNT} rows."
