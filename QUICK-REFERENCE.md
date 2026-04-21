# ⚡ Quick Reference

Essential commands, API examples, and code snippets for the self-hosted Falling Fruit API.

## Table of Contents

- [curl Examples](#curl-examples)
- [JavaScript Snippets](#javascript-snippets)
- [Python Snippets](#python-snippets)
- [Docker Commands](#docker-commands)
- [Service Management](#service-management)
- [Database Queries](#database-queries)

---

## curl Examples

### Basic Requests

```bash
# Set your base URL and API key
BASE_URL="http://YOUR-EC2-IP:3300/api/0.3"
API_KEY="your-api-key"

# Get all types (plant categories)
curl -H "x-api-key: $API_KEY" "$BASE_URL/types"

# Get type counts
curl -H "x-api-key: $API_KEY" "$BASE_URL/types/counts"

# Get a single location
curl -H "x-api-key: $API_KEY" "$BASE_URL/locations/1"
```

### Location Queries

```bash
# Get locations in San Francisco Bay Area
curl -H "x-api-key: $API_KEY" \
  "$BASE_URL/locations?bounds=37.124,-122.519|37.884,-121.208"

# Get locations with limit and offset (pagination)
curl -H "x-api-key: $API_KEY" \
  "$BASE_URL/locations?bounds=37.124,-122.519|37.884,-121.208&limit=50&offset=0"

# Filter by type IDs (comma-separated)
curl -H "x-api-key: $API_KEY" \
  "$BASE_URL/locations?bounds=37.124,-122.519|37.884,-121.208&types=1,2,3"

# Include photo thumbnails
curl -H "x-api-key: $API_KEY" \
  "$BASE_URL/locations?bounds=37.124,-122.519|37.884,-121.208&photo=true"

# Get total count (via response header)
curl -I -H "x-api-key: $API_KEY" \
  "$BASE_URL/locations?bounds=37.124,-122.519|37.884,-121.208&count=true"
```

### Cluster Queries (Map Rendering)

```bash
# Get clusters at zoom level 10
curl -H "x-api-key: $API_KEY" \
  "$BASE_URL/clusters?zoom=10&bounds=37.124,-122.519|37.884,-121.208"

# Clusters with type filter
curl -H "x-api-key: $API_KEY" \
  "$BASE_URL/clusters?zoom=12&bounds=37.124,-122.519|37.884,-121.208&types=1,2"
```

### User Authentication

```bash
# Get an access token (login)
curl -X POST "$BASE_URL/user/token" \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "your-password"}'

# Use the token for authenticated requests
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -H "x-api-key: $API_KEY" \
  -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/user/profile"
```

### Create a Location (Authenticated)

```bash
curl -X POST "$BASE_URL/locations" \
  -H "x-api-key: $API_KEY" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "lat": 37.7749,
    "lng": -122.4194,
    "type_ids": [1, 5],
    "description": "Apple tree near the park",
    "access": 1
  }'
```

### Pretty-Print JSON

```bash
# Install jq for pretty JSON output
sudo apt install -y jq   # Linux
brew install jq           # macOS

# Use with curl
curl -H "x-api-key: $API_KEY" "$BASE_URL/types" | jq '.'

# Extract specific fields
curl -H "x-api-key: $API_KEY" \
  "$BASE_URL/locations?bounds=37.124,-122.519|37.884,-121.208" | \
  jq '[.[] | {id: .id, lat: .lat, lng: .lng}]'
```

---

## JavaScript Snippets

### Setup (Node.js / Browser)

```javascript
// Configuration
const BASE_URL = 'http://YOUR-EC2-IP:3300/api/0.3';
const API_KEY = 'your-api-key';

// Helper function for all requests
async function apiRequest(path, options = {}) {
  const url = `${BASE_URL}${path}`;
  const response = await fetch(url, {
    ...options,
    headers: {
      'x-api-key': API_KEY,
      'Content-Type': 'application/json',
      ...options.headers,
    },
  });

  if (!response.ok) {
    throw new Error(`API error: ${response.status} ${response.statusText}`);
  }

  return response.json();
}
```

### Get Types

```javascript
// Get all plant/tree types
const types = await apiRequest('/types');
console.log(`Found ${types.length} types`);

// Find types by name
const appleTypes = types.filter(t =>
  t.en_name?.toLowerCase().includes('apple')
);
```

### Query Locations by Bounding Box

```javascript
// San Francisco Bay Area bounds
const bounds = {
  sw: { lat: 37.124, lng: -122.519 },
  ne: { lat: 37.884, lng: -121.208 },
};

// Format bounds string
const boundsStr = `${bounds.sw.lat},${bounds.sw.lng}|${bounds.ne.lat},${bounds.ne.lng}`;

const params = new URLSearchParams({
  bounds: boundsStr,
  limit: '100',
  offset: '0',
  // types: '1,2,3',  // Optional: filter by type IDs
});

const locations = await apiRequest(`/locations?${params}`);
console.log(`Found ${locations.length} locations`);
```

### Fetch Clusters for Map

```javascript
// Get clusters for a map view (efficient for large datasets)
async function getClusters(map) {
  const bounds = map.getBounds(); // Leaflet/Mapbox bounds
  const zoom = map.getZoom();

  const params = new URLSearchParams({
    zoom: zoom.toString(),
    bounds: [
      bounds.getSouth(), bounds.getWest(),
      bounds.getNorth(), bounds.getEast(),
    ].join(',').replace(',', ',').replace(/(.+,.+),(.+,.+)/, '$1|$2'),
  });

  return apiRequest(`/clusters?${params}`);
}
```

### Authentication Flow

```javascript
// Login and get token
async function login(email, password) {
  const response = await fetch(`${BASE_URL}/user/token`, {
    method: 'POST',
    headers: {
      'x-api-key': API_KEY,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ email, password }),
  });

  if (!response.ok) throw new Error('Login failed');

  const { access_token } = await response.json();
  // Store token (localStorage for web, secure storage for mobile)
  localStorage.setItem('ff_token', access_token);
  return access_token;
}

// Authenticated request helper
async function authRequest(path, options = {}) {
  const token = localStorage.getItem('ff_token');
  return apiRequest(path, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      ...options.headers,
    },
  });
}
```

### Add a New Location

```javascript
async function addLocation({ lat, lng, typeIds, description }) {
  return authRequest('/locations', {
    method: 'POST',
    body: JSON.stringify({
      lat,
      lng,
      type_ids: typeIds,
      description,
      access: 1, // 1=public, 2=private
    }),
  });
}

// Usage
const newLocation = await addLocation({
  lat: 37.7749,
  lng: -122.4194,
  typeIds: [1, 5],
  description: 'Wild blackberry bushes',
});
```

---

## Python Snippets

### Setup

```python
import requests
from typing import Optional

BASE_URL = "http://YOUR-EC2-IP:3300/api/0.3"
API_KEY = "your-api-key"

# Session with default headers
session = requests.Session()
session.headers.update({
    "x-api-key": API_KEY,
    "Content-Type": "application/json",
})
```

### Get Types

```python
def get_types():
    response = session.get(f"{BASE_URL}/types")
    response.raise_for_status()
    return response.json()

types = get_types()
print(f"Found {len(types)} types")

# Find apple-related types
apple_types = [t for t in types if "apple" in (t.get("en_name") or "").lower()]
print("Apple types:", [t["en_name"] for t in apple_types])
```

### Query Locations by Bounding Box

```python
def get_locations(bounds: str, types: Optional[str] = None,
                  limit: int = 100, offset: int = 0):
    """
    Get locations within a bounding box.

    Args:
        bounds: "swlat,swlng|nelat,nelng" format
        types: Comma-separated type IDs (e.g., "1,2,3")
        limit: Max results to return
        offset: Pagination offset
    """
    params = {
        "bounds": bounds,
        "limit": limit,
        "offset": offset,
    }
    if types:
        params["types"] = types

    response = session.get(f"{BASE_URL}/locations", params=params)
    response.raise_for_status()
    return response.json()

# San Francisco Bay Area
locations = get_locations(
    bounds="37.124,-122.519|37.884,-121.208",
    limit=500,
)
print(f"Found {len(locations)} locations in Bay Area")
```

### Paginate Through All Locations

```python
def get_all_locations(bounds: str, page_size: int = 500):
    """Fetch all locations by paginating through results."""
    all_locations = []
    offset = 0

    while True:
        batch = get_locations(bounds, limit=page_size, offset=offset)
        if not batch:
            break
        all_locations.extend(batch)
        offset += len(batch)
        print(f"Fetched {len(all_locations)} locations so far...")
        if len(batch) < page_size:
            break

    return all_locations

all_bay_area = get_all_locations("37.124,-122.519|37.884,-121.208")
print(f"Total: {len(all_bay_area)} locations")
```

### Login and Authenticated Requests

```python
def login(email: str, password: str) -> str:
    """Login and return access token."""
    response = session.post(f"{BASE_URL}/user/token", json={
        "email": email,
        "password": password,
    })
    response.raise_for_status()
    return response.json()["access_token"]

def add_location(token: str, lat: float, lng: float,
                 type_ids: list, description: str = ""):
    """Add a new location (requires authentication)."""
    headers = {"Authorization": f"Bearer {token}"}
    response = session.post(
        f"{BASE_URL}/locations",
        headers=headers,
        json={
            "lat": lat,
            "lng": lng,
            "type_ids": type_ids,
            "description": description,
            "access": 1,
        },
    )
    response.raise_for_status()
    return response.json()

# Usage
token = login("user@example.com", "password123")
new_loc = add_location(token, 37.7749, -122.4194, [1, 5], "Wild figs")
```

### Export to GeoJSON

```python
import json

def locations_to_geojson(locations: list) -> dict:
    """Convert API locations to GeoJSON FeatureCollection."""
    features = []
    for loc in locations:
        feature = {
            "type": "Feature",
            "geometry": {
                "type": "Point",
                "coordinates": [loc["lng"], loc["lat"]],
            },
            "properties": {
                "id": loc.get("id"),
                "type_ids": loc.get("type_ids", []),
                "description": loc.get("description", ""),
            },
        }
        features.append(feature)

    return {
        "type": "FeatureCollection",
        "features": features,
    }

locations = get_locations("37.124,-122.519|37.884,-121.208", limit=1000)
geojson = locations_to_geojson(locations)

with open("bay-area-foraging.geojson", "w") as f:
    json.dump(geojson, f, indent=2)

print(f"Saved {len(locations)} locations to GeoJSON")
```

---

## Docker Commands

```bash
# Start all services
docker compose up -d

# Stop all services
docker compose down

# View logs
docker compose logs -f api

# Open API shell
docker compose exec api sh

# Connect to database
docker compose exec db psql -U ffuser -d falling_fruit

# Rebuild after changes
docker compose up -d --build

# Full reset (deletes all data)
docker compose down -v
```

---

## Service Management (EC2)

```bash
# Start API
sudo systemctl start falling-fruit-api

# Stop API
sudo systemctl stop falling-fruit-api

# Restart API (after config changes)
sudo systemctl restart falling-fruit-api

# Enable auto-start on boot
sudo systemctl enable falling-fruit-api

# Check status
sudo systemctl status falling-fruit-api

# Follow logs
sudo journalctl -u falling-fruit-api -f

# Last 100 log lines
sudo journalctl -u falling-fruit-api -n 100

# Logs since yesterday
sudo journalctl -u falling-fruit-api --since yesterday
```

---

## Database Queries

```bash
# Connect to database
sudo -u postgres psql -d falling_fruit

# Or with credentials
psql -h localhost -U ffuser -d falling_fruit
```

```sql
-- Count all locations
SELECT COUNT(*) FROM locations;

-- Count locations by type
SELECT t.en_name, COUNT(lt.location_id) as count
FROM types t
JOIN location_types lt ON t.id = lt.type_id
GROUP BY t.en_name
ORDER BY count DESC
LIMIT 20;

-- Locations in Bay Area bounding box
SELECT id, ST_Y(latlon) as lat, ST_X(latlon) as lng
FROM locations
WHERE ST_Within(
  latlon,
  ST_MakeEnvelope(-122.519, 37.124, -121.208, 37.884, 4326)
)
LIMIT 10;

-- Database size
SELECT pg_size_pretty(pg_database_size('falling_fruit'));

-- Active connections
SELECT COUNT(*) FROM pg_stat_activity WHERE datname = 'falling_fruit';

-- Check PostGIS version
SELECT PostGIS_Version();
```

---

## Bay Area Bounding Box Reference

```
San Francisco Bay Area:
  SW: 37.124°N, 122.519°W  →  37.124,-122.519
  NE: 37.884°N, 121.208°W  →  37.884,-121.208

API format: "37.124,-122.519|37.884,-121.208"

Sub-regions:
  San Francisco city:  37.708,-122.513|37.832,-122.357
  East Bay (Oakland):  37.699,-122.355|37.905,-122.115
  South Bay (San Jose): 37.121,-122.058|37.470,-121.747
  Marin County:        37.820,-122.758|38.065,-122.435
```

---

## Common Bounds Format

```
Format: "swlat,swlng|nelat,nelng"

Examples:
  World:       "-85,-180|85,180"
  USA:         "24.396,-124.849|49.384,-66.934"
  California:  "32.534,-124.409|42.009,-114.131"
  Bay Area:    "37.124,-122.519|37.884,-121.208"
  NYC:         "40.477,-74.260|40.917,-73.700"
  London:      "51.284,-0.489|51.686,0.236"
  Tokyo:       "35.523,139.268|35.818,139.910"
```
