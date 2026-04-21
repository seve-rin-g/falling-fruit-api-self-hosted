# 🐳 Docker Setup Guide

Run the Falling Fruit API locally using Docker and Docker Compose. This is the fastest way to get a development environment running on your machine.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Mac/Windows) or Docker Engine + Docker Compose (Linux)
- Git

## Project Structure

```
falling-fruit-api-self-hosted/
├── docker-compose.yml          # Development environment
├── docker-compose.prod.yml     # Production-like testing
├── Dockerfile                  # API container image
├── .env.example                # Environment template
└── falling-fruit-api/          # Cloned API (created by setup)
```

---

## Quick Start

### 1. Clone Repositories

```bash
# Clone this setup guide
git clone https://github.com/seve-rin-g/falling-fruit-api-self-hosted.git
cd falling-fruit-api-self-hosted

# Clone the actual Falling Fruit API source code
git clone https://github.com/falling-fruit/falling-fruit-api.git
```

### 2. Configure Environment

```bash
# Copy the example environment file into the API directory
cp .env.example falling-fruit-api/.env

# Optional: review and edit settings
nano falling-fruit-api/.env
```

### 3. Start the Stack

```bash
# Start all services (API + PostgreSQL/PostGIS)
docker compose up -d

# Watch the logs during startup
docker compose logs -f
```

The first run may take 2-5 minutes to:
- Pull Docker images
- Build the API container
- Initialize the PostgreSQL + PostGIS database

### 4. Verify Everything Works

```bash
# Check all containers are running
docker compose ps

# Test the API
curl http://localhost:3300/api/0.3/types

# Test with API key (if configured)
curl -H "x-api-key: dev-api-key-change-me" http://localhost:3300/api/0.3/types
```

---

## Services

The `docker-compose.yml` defines these services:

| Service | Port | Description |
|---------|------|-------------|
| `api` | 3300 | Falling Fruit Node.js API |
| `db` | 5432 | PostgreSQL 14 with PostGIS |

### Service Details

**API Container** (`api`)
- Based on `node:20-alpine`
- Mounts the `falling-fruit-api/` directory as a volume
- Restarts automatically on crash
- Health check polls `/api/0.3/types` every 30s

**Database Container** (`db`)
- PostgreSQL 14 with PostGIS 3
- Data persisted in a named volume (`postgres_data`)
- Initialized with the `init-db.sql` script on first run

---

## Common Docker Commands

### Start and Stop

```bash
# Start all services in background
docker compose up -d

# Start and watch logs
docker compose up

# Stop all services (keeps data)
docker compose down

# Stop and remove all data (fresh start)
docker compose down -v
```

### Logs

```bash
# Follow all logs
docker compose logs -f

# Follow only API logs
docker compose logs -f api

# Follow only database logs
docker compose logs -f db

# Last 50 lines
docker compose logs --tail=50 api
```

### Shell Access

```bash
# Open a shell in the API container
docker compose exec api sh

# Connect to PostgreSQL
docker compose exec db psql -U ffuser -d falling_fruit

# Or connect from your host machine
psql -h localhost -p 5432 -U ffuser -d falling_fruit
# Password: ffpassword (from .env.example)
```

### Rebuild

```bash
# Rebuild the API image after Dockerfile changes
docker compose build api

# Rebuild and restart
docker compose up -d --build
```

---

## Volumes and Data

### Named Volumes

The Docker Compose setup uses named volumes for persistence:

```yaml
volumes:
  postgres_data:    # PostgreSQL database files
  api_node_modules: # Cached Node.js dependencies
```

### Inspecting Volumes

```bash
# List all volumes
docker volume ls

# Inspect a volume
docker volume inspect falling-fruit-api-self-hosted_postgres_data

# Back up the database
docker compose exec db pg_dump -U ffuser falling_fruit > backup.sql

# Restore from backup
cat backup.sql | docker compose exec -T db psql -U ffuser falling_fruit
```

---

## Database Initialization

On first startup, Docker automatically runs `scripts/init-db.sql` which:
1. Enables PostGIS extensions
2. Creates the basic schema
3. Creates indexes for geographic queries

### Manually Run SQL

```bash
# Run a SQL file in the container
docker compose exec -T db psql -U ffuser falling_fruit < my-script.sql

# Run a SQL command directly
docker compose exec db psql -U ffuser falling_fruit -c "SELECT COUNT(*) FROM locations;"
```

### Import Location Data

```bash
# Import Bay Area locations from the public Falling Fruit API
bash scripts/import-from-api.sh \
  --bounds "37.124,-122.519|37.884,-121.208" \
  --db-host localhost \
  --db-user ffuser \
  --db-name falling_fruit
```

---

## Development Workflow

### Hot Reload

The `docker-compose.yml` mounts `./falling-fruit-api` as a volume, so code changes in the API directory take effect after a container restart:

```bash
# After editing API source code
docker compose restart api
```

For true hot-reload during development, you can override the start command:

```bash
# Start with nodemon for hot reload
docker compose exec api yarn dev
# (requires nodemon to be installed in the API package.json)
```

### Running Tests

```bash
# Run tests inside the container
docker compose exec api yarn test

# Run a specific test file
docker compose exec api yarn test -- --grep "locations"
```

### Database Migrations

```bash
# Check current schema version
docker compose exec db psql -U ffuser falling_fruit -c "SELECT version FROM schema_version;"

# Run a migration file
docker compose exec -T db psql -U ffuser falling_fruit < db/migrations/001_add_column.sql
```

---

## Production-Like Testing

Use `docker-compose.prod.yml` to test with production settings before deploying:

```bash
# Start production-like environment
docker compose -f docker-compose.prod.yml up -d

# This uses:
# - NODE_ENV=production
# - No volume mounts (uses built image)
# - Stricter resource limits
```

---

## Networking

### Container Network

All services share the `falling-fruit-network` bridge network:

```
[Your Browser/App]
       |
       | :3300
       ▼
[api container]  ──────────────  [db container]
  :3300                              :5432
  (mapped to host)               (internal only)
```

The database port 5432 is mapped to your host for direct psql access during development.

### Accessing from Other Containers

If you're running your frontend in a separate Docker container, connect it to the same network:

```yaml
# In your app's docker-compose.yml
services:
  frontend:
    networks:
      - falling-fruit-network

networks:
  falling-fruit-network:
    external: true
    name: falling-fruit-api-self-hosted_falling-fruit-network
```

Then use `http://api:3300` as the API URL from your frontend container.

---

## Troubleshooting Docker

### Port Already in Use

```bash
# Find what's using port 3300
lsof -i :3300
# or
ss -tulpn | grep 3300

# Kill the process or change the port in docker-compose.yml
```

### Container Won't Start

```bash
# Check detailed error
docker compose logs api

# Check container exit code
docker compose ps
```

### Database Connection Error

```bash
# Verify database is running
docker compose ps db

# Test connection manually
docker compose exec db psql -U ffuser -d falling_fruit -c "SELECT 1;"

# Check environment variables in API container
docker compose exec api env | grep DB
```

### Out of Disk Space

```bash
# Check Docker disk usage
docker system df

# Clean up unused images/containers/volumes
docker system prune -a

# Remove only unused volumes (careful: this deletes data!)
docker volume prune
```

### Reset Everything

```bash
# Nuclear option: remove all containers, networks, volumes
docker compose down -v --remove-orphans
docker rmi $(docker images -q "falling-fruit*") 2>/dev/null || true

# Start fresh
docker compose up -d
```

---

## Environment Variables Reference

All environment variables for local Docker development are in `.env.example`. Key variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `NODE_ENV` | `development` | Environment mode |
| `PORT` | `3300` | API port |
| `DB` | `postgres://ffuser:ffpassword@db:5432/falling_fruit` | Database connection |
| `JWT_SECRET` | `dev-jwt-secret-change-me` | JWT signing secret |
| `API_KEY` | `dev-api-key-change-me` | Required request header |

See [.env.example](.env.example) for the full list.
