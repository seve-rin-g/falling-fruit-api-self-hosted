# data/

This directory holds the compressed Falling Fruit locations export used by
`scripts/import-from-csv.sh` and the Docker Compose `importer` service.

## Obtaining the dataset

```bash
# Download the latest full export from fallingfruit.org
curl -fL https://fallingfruit.org/locations.csv.bz2 -o data/locations.csv.bz2
```

The file is typically 10–50 MB compressed and contains all public Falling Fruit
locations worldwide.

Once downloaded, run the importer:

```bash
# Via Docker Compose (recommended)
docker compose run --rm importer

# Or directly against a running database
DB_HOST=localhost DB_USER=ffuser DB_NAME=falling_fruit PGPASSWORD=ffpassword \
  bash scripts/import-from-csv.sh data/locations.csv.bz2
```

See [docs/IMPORT.md](../docs/IMPORT.md) for full documentation.
