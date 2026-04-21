#!/usr/bin/env bash
# =============================================================================
# Falling Fruit API — Import Location Data from Public API
# =============================================================================
# This script fetches location data from the public Falling Fruit API
# and loads it into your local PostgreSQL database.
#
# Usage:
#   bash scripts/import-from-api.sh [OPTIONS]
#
# Examples:
#   # Import Bay Area locations
#   bash scripts/import-from-api.sh --bounds "37.124,-122.519|37.884,-121.208"
#
#   # Import with custom database settings
#   bash scripts/import-from-api.sh \
#     --bounds "37.124,-122.519|37.884,-121.208" \
#     --db-host localhost \
#     --db-user ffuser \
#     --db-name falling_fruit \
#     --output /tmp/locations.json
#
#   # Import entire USA (may take a while)
#   bash scripts/import-from-api.sh --bounds "24,-124|49,-67"
#
# Notes:
#   - Requires: curl, jq, psql
#   - The public API may rate-limit large requests
#   - Use smaller bounding boxes to avoid timeouts
# =============================================================================

set -euo pipefail

# =============================================================================
# Defaults (can be overridden by command line arguments)
# =============================================================================

PUBLIC_API_URL="https://fallingfruit.org/api/0.3"
BOUNDS="37.124,-122.519|37.884,-121.208"  # San Francisco Bay Area
LIMIT=1000          # Locations per batch request
OUTPUT_FILE=""      # Will auto-generate if not set
LOAD_TO_DB=true     # Import into database after fetching

# Database settings (load from environment if available)
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-ffuser}"
DB_NAME="${DB_NAME:-falling_fruit}"
DB_PASS="${DB_PASS:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# Helper Functions
# =============================================================================

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

usage() {
    cat << 'EOF'
Usage: bash scripts/import-from-api.sh [OPTIONS]

Options:
  --bounds BOUNDS       Bounding box in "swlat,swlng|nelat,nelng" format
                        Default: "37.124,-122.519|37.884,-121.208" (Bay Area)
  --output FILE         Save raw JSON to this file (default: /tmp/ff-locations-TIMESTAMP.json)
  --no-db               Fetch data but don't load into database
  --db-host HOST        Database host (default: localhost)
  --db-port PORT        Database port (default: 5432)
  --db-user USER        Database user (default: ffuser)
  --db-name NAME        Database name (default: falling_fruit)
  --api-url URL         Public API URL (default: https://fallingfruit.org/api/0.3)
  --limit N             Locations per batch request (default: 1000)
  --help                Show this help

Examples:
  # Import Bay Area locations
  bash scripts/import-from-api.sh --bounds "37.124,-122.519|37.884,-121.208"

  # Import NYC locations without loading to database
  bash scripts/import-from-api.sh --bounds "40.477,-74.260|40.917,-73.700" --no-db

  # Import to remote database
  bash scripts/import-from-api.sh --db-host my-rds-endpoint.rds.amazonaws.com --db-user admin
EOF
    exit 0
}

# =============================================================================
# Parse Arguments
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --bounds)     BOUNDS="$2";    shift 2 ;;
        --output)     OUTPUT_FILE="$2"; shift 2 ;;
        --no-db)      LOAD_TO_DB=false; shift ;;
        --db-host)    DB_HOST="$2";   shift 2 ;;
        --db-port)    DB_PORT="$2";   shift 2 ;;
        --db-user)    DB_USER="$2";   shift 2 ;;
        --db-name)    DB_NAME="$2";   shift 2 ;;
        --api-url)    PUBLIC_API_URL="$2"; shift 2 ;;
        --limit)      LIMIT="$2";     shift 2 ;;
        --help|-h)    usage ;;
        *)            log_error "Unknown option: $1. Use --help for usage." ;;
    esac
done

# Auto-generate output filename if not specified
if [[ -z "$OUTPUT_FILE" ]]; then
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    OUTPUT_FILE="/tmp/ff-locations-${TIMESTAMP}.json"
fi

# =============================================================================
# Pre-flight Checks
# =============================================================================

log_info "Checking required tools..."

# Check for required commands
for cmd in curl jq; do
    if ! command -v "$cmd" &> /dev/null; then
        log_error "'$cmd' is required but not installed. Install with: sudo apt install -y $cmd"
    fi
done

if [[ "$LOAD_TO_DB" == "true" ]]; then
    if ! command -v psql &> /dev/null; then
        log_error "'psql' is required for database loading. Install with: sudo apt install -y postgresql-client"
    fi
fi

log_success "All required tools are available"

# Test public API connectivity
log_info "Testing connection to public Falling Fruit API..."
if ! curl -sf --max-time 10 "${PUBLIC_API_URL}/types" > /dev/null; then
    log_error "Cannot reach ${PUBLIC_API_URL}. Check your internet connection."
fi
log_success "Public API is reachable"

# =============================================================================
# Fetch Location Data
# =============================================================================

log_info "Fetching locations from public API..."
log_info "Bounds: ${BOUNDS}"
log_info "Batch size: ${LIMIT}"
echo ""

ALL_LOCATIONS="[]"
OFFSET=0
TOTAL_FETCHED=0
BATCH_NUM=1

while true; do
    log_info "Fetching batch ${BATCH_NUM} (offset: ${OFFSET})..."

    # Build the URL with parameters
    API_URL="${PUBLIC_API_URL}/locations?bounds=${BOUNDS}&limit=${LIMIT}&offset=${OFFSET}"

    # Fetch data with retry logic
    RESPONSE=""
    for ATTEMPT in 1 2 3; do
        RESPONSE=$(curl -sf \
            --max-time 60 \
            --retry 3 \
            --retry-delay 5 \
            "${API_URL}" 2>/dev/null) && break

        if [[ $ATTEMPT -lt 3 ]]; then
            log_warn "Request failed (attempt ${ATTEMPT}/3), retrying in 5s..."
            sleep 5
        else
            log_error "Failed to fetch batch ${BATCH_NUM} after 3 attempts"
        fi
    done

    # Count locations in this batch
    BATCH_COUNT=$(echo "$RESPONSE" | jq 'length')
    TOTAL_FETCHED=$((TOTAL_FETCHED + BATCH_COUNT))

    log_info "  Received ${BATCH_COUNT} locations (total: ${TOTAL_FETCHED})"

    # Merge with all locations
    ALL_LOCATIONS=$(echo "$ALL_LOCATIONS $RESPONSE" | jq -s '.[0] + .[1]')

    # If we got fewer than the limit, we've fetched all available data
    if [[ "$BATCH_COUNT" -lt "$LIMIT" ]]; then
        log_success "All locations fetched (${TOTAL_FETCHED} total)"
        break
    fi

    # Move to next batch
    OFFSET=$((OFFSET + LIMIT))
    BATCH_NUM=$((BATCH_NUM + 1))

    # Be polite to the public API — add a short delay between requests
    sleep 1
done

if [[ "$TOTAL_FETCHED" -eq 0 ]]; then
    log_warn "No locations found in the specified bounds: ${BOUNDS}"
    log_warn "Try a different bounding box or check the public API directly:"
    log_warn "  curl '${PUBLIC_API_URL}/locations?bounds=${BOUNDS}&limit=10'"
    exit 0
fi

# Save to JSON file
echo "$ALL_LOCATIONS" > "$OUTPUT_FILE"
log_success "Saved ${TOTAL_FETCHED} locations to ${OUTPUT_FILE}"

# =============================================================================
# Fetch Types Data
# =============================================================================

log_info "Fetching types data..."
TYPES_FILE="${OUTPUT_FILE%.json}-types.json"
curl -sf "${PUBLIC_API_URL}/types" > "$TYPES_FILE"
TYPES_COUNT=$(jq 'length' "$TYPES_FILE")
log_success "Saved ${TYPES_COUNT} types to ${TYPES_FILE}"

# =============================================================================
# Load Into Database
# =============================================================================

if [[ "$LOAD_TO_DB" != "true" ]]; then
    log_info "Skipping database load (--no-db flag set)"
    echo ""
    log_success "Import complete! Files saved:"
    log_success "  Locations: ${OUTPUT_FILE}"
    log_success "  Types:     ${TYPES_FILE}"
    exit 0
fi

log_info "Loading data into database..."
log_info "Database: ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

# Build psql connection string
PSQL_CMD="psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME}"
if [[ -n "$DB_PASS" ]]; then
    export PGPASSWORD="$DB_PASS"
fi

# Test database connection
if ! $PSQL_CMD -c "SELECT 1;" > /dev/null 2>&1; then
    log_error "Cannot connect to database. Check your credentials and try again."
fi

log_success "Database connection successful"

# Generate SQL for types
log_info "Generating SQL for types..."
TYPES_SQL_FILE="${OUTPUT_FILE%.json}-types.sql"

jq -r '.[] | "INSERT INTO types (id, en_name, name, scientific_name) VALUES (" +
    (.id | tostring) + ", " +
    (if .en_name then ("'"'"'" + (.en_name | gsub("'"'"'"; "'"'"''"'"'")) + "'"'"'") else "NULL" end) + ", " +
    (if .name then ("'"'"'" + (.name | gsub("'"'"'"; "'"'"''"'"'")) + "'"'"'") else "NULL" end) + ", " +
    (if .scientific_name then ("'"'"'" + (.scientific_name | gsub("'"'"'"; "'"'"''"'"'")) + "'"'"'") else "NULL" end) +
    ") ON CONFLICT (id) DO UPDATE SET en_name = EXCLUDED.en_name, name = EXCLUDED.name;
"' "$TYPES_FILE" > "$TYPES_SQL_FILE"

log_info "Loading types into database..."
$PSQL_CMD -f "$TYPES_SQL_FILE" > /dev/null 2>&1 || log_warn "Some types may have failed to insert (check schema compatibility)"
log_success "Types loaded"

# Generate SQL for locations
log_info "Generating SQL for locations (${TOTAL_FETCHED} records)..."
LOCATIONS_SQL_FILE="${OUTPUT_FILE%.json}.sql"

jq -r '.[] | "INSERT INTO locations (id, lat, lng, description, latlon) VALUES (" +
    (.id | tostring) + ", " +
    (.lat | tostring) + ", " +
    (.lng | tostring) + ", " +
    (if .description then ("'"'"'" + (.description | gsub("'"'"'"; "'"'"''"'"'")) + "'"'"'") else "NULL" end) + ", " +
    "ST_SetSRID(ST_MakePoint(" + (.lng | tostring) + ", " + (.lat | tostring) + "), 4326)" +
    ") ON CONFLICT (id) DO UPDATE SET lat = EXCLUDED.lat, lng = EXCLUDED.lng, description = EXCLUDED.description, latlon = EXCLUDED.latlon;
"' "$OUTPUT_FILE" > "$LOCATIONS_SQL_FILE"

log_info "Loading locations into database..."
$PSQL_CMD -f "$LOCATIONS_SQL_FILE" > /dev/null 2>&1 || \
    log_warn "Some locations may have failed to insert (check schema compatibility)"
log_success "Locations loaded"

# Verify the import
LOADED_COUNT=$($PSQL_CMD -t -c "SELECT COUNT(*) FROM locations;" 2>/dev/null | tr -d ' ' || echo "unknown")
log_success "Database now contains ${LOADED_COUNT} locations"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "============================================="
echo " Import Complete!"
echo "============================================="
echo ""
echo "Fetched from public API: ${TOTAL_FETCHED} locations"
echo "Database location count: ${LOADED_COUNT}"
echo ""
echo "Files saved:"
echo "  Locations JSON: ${OUTPUT_FILE}"
echo "  Locations SQL:  ${LOCATIONS_SQL_FILE}"
echo "  Types JSON:     ${TYPES_FILE}"
echo "  Types SQL:      ${TYPES_SQL_FILE}"
echo ""
echo "Test your API:"
echo "  curl -H 'x-api-key: your-key' \\"
echo "    'http://localhost:3300/api/0.3/locations?bounds=${BOUNDS}&limit=10'"
echo "============================================="
