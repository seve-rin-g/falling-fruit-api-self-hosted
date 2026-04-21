#!/usr/bin/env bash
# =============================================================================
# scripts/docker-init.d/02-import.sh
# =============================================================================
# DB-init helper — runs inside the PostgreSQL container via
# /docker-entrypoint-initdb.d/ on first database initialization.
#
# The Postgres official image executes *.sh files in /docker-entrypoint-initdb.d/
# in alphabetical order.  This script runs after 01-init.sql has created the
# schema, and attempts to load a locations CSV if one is available.
#
# Supported locations for the data file (checked in order):
#   /docker-entrypoint-initdb.d/locations.csv.bz2
#   /docker-entrypoint-initdb.d/locations.csv.gz
#   /docker-entrypoint-initdb.d/locations.csv
#
# If none of the above files exist the script exits silently (no error).
# =============================================================================
set -e

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[02-import] $*"; }

# Resolve data file
DATA_FILE=""
for candidate in \
    /docker-entrypoint-initdb.d/locations.csv.bz2 \
    /docker-entrypoint-initdb.d/locations.csv.gz \
    /docker-entrypoint-initdb.d/locations.csv
do
    if [ -f "$candidate" ]; then
        DATA_FILE="$candidate"
        break
    fi
done

if [ -z "$DATA_FILE" ]; then
    log "No locations CSV found in /docker-entrypoint-initdb.d — skipping auto-import."
    log "To import later, run:  scripts/import-from-csv.sh data/locations.csv.bz2"
    exit 0
fi

log "Found data file: $DATA_FILE"

# ---------------------------------------------------------------------------
# Decompress to a temporary CSV
# ---------------------------------------------------------------------------
TMPCSV="$(mktemp /tmp/ff-init-locations-XXXXXX.csv)"
cleanup() { rm -f "$TMPCSV"; }
trap cleanup EXIT

case "$DATA_FILE" in
    *.bz2)
        log "Decompressing bzip2 …"
        bzip2 -dc "$DATA_FILE" > "$TMPCSV"
        ;;
    *.gz)
        log "Decompressing gzip …"
        gunzip -c "$DATA_FILE" > "$TMPCSV"
        ;;
    *)
        cp "$DATA_FILE" "$TMPCSV"
        ;;
esac

HEADER_LINE="$(head -n1 "$TMPCSV")"
log "CSV header: $HEADER_LINE"

# ---------------------------------------------------------------------------
# Load into a raw staging table then transform into the live schema
# ---------------------------------------------------------------------------
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<SQL
-- Raw staging (all-text, tolerant of varying headers)
DROP TABLE IF EXISTS _ff_staging_raw;
CREATE UNLOGGED TABLE _ff_staging_raw (
    id           TEXT,
    types        TEXT,
    description  TEXT,
    lat          TEXT,
    lng          TEXT,
    season_start TEXT,
    season_stop  TEXT,
    no_season    TEXT,
    unverified   TEXT,
    photo_url    TEXT,
    import_id    TEXT,
    created_at   TEXT,
    updated_at   TEXT,
    address      TEXT,
    city         TEXT,
    state        TEXT,
    country      TEXT,
    access       TEXT,
    geometry     TEXT
);
SQL

# Build column list from actual CSV header so COPY does not fail on unknown cols
COPY_COLS="$(python3 - <<'PY'
import csv
known = {
    'id','types','description','lat','lng','season_start','season_stop',
    'no_season','unverified','photo_url','import_id','created_at','updated_at',
    'address','city','state','country','access','geometry',
}
alias = {
    'latitude':'lat','longitude':'lng',
    'type_ids':'types','type_names':'types',
    'photos':'photo_url','photo':'photo_url',
}
with open("'"$TMPCSV"'", newline='', encoding='utf-8-sig') as f:
    cols = [c.strip().lstrip('\ufeff').lower() for c in next(csv.reader(f))]
cols = [alias.get(c, c) for c in cols]
print(','.join(c for c in cols if c in known))
PY
)"

log "Mapped columns: $COPY_COLS"

if [ -z "$COPY_COLS" ]; then
    log "ERROR: could not map CSV headers — skipping import."
    exit 1
fi

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    -c "\COPY _ff_staging_raw($COPY_COLS) FROM '$TMPCSV' WITH (FORMAT csv, HEADER true, NULL '')"

log "CSV loaded into staging table."

# Transform staging → live schema
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
-- Parse and cast staging rows
DROP TABLE IF EXISTS _ff_staging;
CREATE UNLOGGED TABLE _ff_staging AS
SELECT
    NULLIF(trim(id),'')::bigint   AS location_id,
    CASE
        WHEN NULLIF(trim(lat),'') IS NOT NULL THEN trim(lat)::double precision
        WHEN NULLIF(trim(geometry),'') IS NOT NULL
            THEN (regexp_matches(geometry,'POINT\s*\(\s*([0-9.\-]+)\s+([0-9.\-]+)\s*\)'))[2]::double precision
    END AS lat,
    CASE
        WHEN NULLIF(trim(lng),'') IS NOT NULL THEN trim(lng)::double precision
        WHEN NULLIF(trim(geometry),'') IS NOT NULL
            THEN (regexp_matches(geometry,'POINT\s*\(\s*([0-9.\-]+)\s+([0-9.\-]+)\s*\)'))[1]::double precision
    END AS lng,
    NULLIF(trim(types),'')           AS types_text,
    NULLIF(trim(description),'')     AS description,
    NULLIF(trim(season_start),'')::int AS season_start,
    NULLIF(trim(season_stop),'')::int  AS season_stop,
    COALESCE(NULLIF(trim(no_season),'')::boolean, false)   AS no_season,
    COALESCE(NULLIF(trim(unverified),'')::boolean, false)  AS unverified,
    NULLIF(trim(photo_url),'')       AS photo_url,
    COALESCE(NULLIF(trim(access),'')::int, 1) AS access,
    NULLIF(trim(import_id),'')::int  AS import_id,
    CASE WHEN NULLIF(trim(created_at),'') IS NOT NULL THEN trim(created_at)::timestamptz ELSE NOW() END AS created_at
FROM _ff_staging_raw;

DELETE FROM _ff_staging WHERE lat IS NULL OR lng IS NULL;

-- Import record
INSERT INTO imports (name, url, location_count, created_at)
VALUES (
    'locations.csv auto-import (docker-entrypoint-initdb.d)',
    'https://fallingfruit.org/locations.csv.bz2',
    (SELECT COUNT(*) FROM _ff_staging),
    NOW()
);

-- Upsert types (numeric ids honoured; name-based types get auto ids)
-- NOTE: numeric-id types use 'Type <id>' as en_name placeholder.
CREATE TEMP TABLE _ff_type_tokens AS
SELECT DISTINCT trim(token) AS token
FROM _ff_staging, regexp_split_to_table(COALESCE(types_text,''), '[,|]') AS token
WHERE trim(token) <> '';

INSERT INTO types (id, en_name, created_at)
SELECT token::int, 'Type ' || token, NOW() FROM _ff_type_tokens
WHERE token ~ '^[0-9]+$'
  AND NOT EXISTS (SELECT 1 FROM types t WHERE t.id = token::int)
ON CONFLICT (id) DO NOTHING;

INSERT INTO types (en_name, created_at)
SELECT token, NOW() FROM _ff_type_tokens
WHERE token !~ '^[0-9]+$'
  AND NOT EXISTS (SELECT 1 FROM types t WHERE lower(t.en_name) = lower(token))
ON CONFLICT DO NOTHING;

-- Upsert locations
-- access: 1=public (default), 2=private, 3=restricted
INSERT INTO locations (
    id, lat, lng, description, season_start, season_stop,
    no_season, photo_url, unverified, access, import_id, created_at
)
SELECT location_id, lat, lng, description, season_start, season_stop,
       no_season, photo_url, unverified, access, import_id, created_at
FROM _ff_staging
ON CONFLICT (id) DO UPDATE
    SET lat=EXCLUDED.lat, lng=EXCLUDED.lng, description=EXCLUDED.description,
        season_start=EXCLUDED.season_start, season_stop=EXCLUDED.season_stop,
        no_season=EXCLUDED.no_season, photo_url=EXCLUDED.photo_url,
        unverified=EXCLUDED.unverified, access=EXCLUDED.access, updated_at=NOW();

-- Upsert location_types
INSERT INTO location_types (location_id, type_id)
SELECT DISTINCT s.location_id,
    CASE WHEN trim(token) ~ '^[0-9]+$' THEN trim(token)::int
         ELSE (SELECT id FROM types t WHERE lower(t.en_name)=lower(trim(token)) LIMIT 1)
    END
FROM _ff_staging s, regexp_split_to_table(COALESCE(s.types_text,''), '[,|]') AS token
WHERE trim(token) <> '' AND s.location_id IS NOT NULL
ON CONFLICT DO NOTHING;

-- Cleanup
DROP TABLE IF EXISTS _ff_staging;
DROP TABLE IF EXISTS _ff_staging_raw;
DROP TABLE IF EXISTS _ff_type_tokens;
SQL

LOCATION_COUNT="$(psql -tAqc "SELECT COUNT(*) FROM locations" -U "$POSTGRES_USER" -d "$POSTGRES_DB")"
log "Auto-import complete. locations table now has ${LOCATION_COUNT} rows."
