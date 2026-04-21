# Importing the Falling Fruit Dataset

This document explains how to populate your self-hosted Falling Fruit database
with real location data from the official Falling Fruit export
(`data/locations.csv.bz2`).

---

## Overview

The repository ships with `data/locations.csv.bz2` — the full compressed
Falling Fruit locations export (~`fallingfruit.org/locations.csv.bz2`).

Two import paths are provided:

| Path | When it runs |
|------|-------------|
| **Docker Compose `importer` service** | On-demand (or automatically after `docker compose up`) |
| **`scripts/import-from-csv.sh`** | Manually, against any reachable PostgreSQL |

---

## Quick Start with Docker Compose

```bash
# 1. Start the database (and API)
docker compose up -d

# 2. Wait for the database to be healthy, then run the importer
docker compose run --rm importer
```

The `importer` service:
- Uses a slim Debian image with `psql`, `bzip2`, and `python3`
- Mounts `./data` (read-only) for the compressed CSV
- Mounts `./scripts` (read-only) for the import script
- Exits with code `0` on success; check logs with `docker compose logs importer`

After import you can verify:

```bash
# Count of imported locations
docker compose exec db psql -U ffuser -d falling_fruit \
  -c "SELECT COUNT(*) FROM locations;"

# Sample geometry check
docker compose exec db psql -U ffuser -d falling_fruit \
  -c "SELECT ST_AsText(latlon) FROM locations LIMIT 5;"
```

---

## Manual Import (no Docker)

### Prerequisites

- `psql` (PostgreSQL client)
- `python3`
- `bzip2` (for `.bz2` files) or `gzip` (for `.gz` files)

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DB_HOST` | `localhost` | PostgreSQL host |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_USER` | `ffuser` | PostgreSQL user |
| `DB_NAME` | `falling_fruit` | PostgreSQL database |
| `PGPASSWORD` | _(unset)_ | Password (or use `~/.pgpass`) |

### Run

```bash
export DB_HOST=localhost
export DB_USER=ffuser
export DB_NAME=falling_fruit
export PGPASSWORD=ffpassword

bash scripts/import-from-csv.sh data/locations.csv.bz2
```

The script accepts `.bz2`, `.gz`, or plain `.csv` files:

```bash
# Compressed bzip2 (default)
bash scripts/import-from-csv.sh data/locations.csv.bz2

# Compressed gzip
bash scripts/import-from-csv.sh data/locations.csv.gz

# Plain CSV
bash scripts/import-from-csv.sh data/locations.csv
```

---

## Automatic Import at DB Initialization

`scripts/docker-init.d/02-import.sh` is a helper that runs inside the
PostgreSQL container during **first initialization** (via
`/docker-entrypoint-initdb.d/`).

If you want automatic import on DB creation, mount both the script **and** the
CSV into the `db` container's init directory:

```yaml
# In docker-compose.yml, under services.db.volumes:
- ./scripts/docker-init.d/02-import.sh:/docker-entrypoint-initdb.d/02-import.sh:ro
- ./data/locations.csv.bz2:/docker-entrypoint-initdb.d/locations.csv.bz2:ro
```

> **Note:** This only runs once, on the very first container start (when the
> data volume is empty). To re-run, remove the volume:
> `docker compose down -v && docker compose up -d`

---

## How the Import Works

1. **Decompress** — `.bz2` or `.gz` files are decompressed to a temp file.
2. **Detect headers** — Column names are read from the CSV header line and
   mapped to the database schema (handles common aliases like `latitude`/`longitude`).
3. **Stage** — CSV is loaded into an unlogged `_ff_staging_raw` table via
   `COPY` (fast bulk load).
4. **Transform** — SQL casts text columns to their target types, derives PostGIS
   geometry from `lat`/`lng` (or parses `POINT(lon lat)` WKT from a `geometry`
   column).
5. **Upsert types** — Numeric type ids are honoured; name-based types are
   inserted with auto-generated ids.
6. **Upsert locations** — `ON CONFLICT (id) DO UPDATE` so re-running is safe.
7. **Upsert location_types** — Many-to-many links created from the `types` field.
8. **Cleanup** — Staging tables are dropped; an `imports` row is recorded.

---

## Removing the Dataset from the Repository

If the large binary file is not desired in version control, remove it and
add it to `.gitignore`:

```bash
git rm --cached data/locations.csv.bz2
echo "data/locations.csv.bz2" >> .gitignore
git commit -m "chore: remove large binary from repo"
```

You can then provide the file at runtime by mounting it externally, or have
the importer download it automatically:

```bash
# Download at runtime inside the importer container
curl -fL https://fallingfruit.org/locations.csv.bz2 -o /data/locations.csv.bz2
bash /scripts/import-from-csv.sh /data/locations.csv.bz2
```
