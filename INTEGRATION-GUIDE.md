# 🔗 Integration Guide

Complete examples for integrating the self-hosted Falling Fruit API into your applications. Covers React, Python backends, Swift (iOS), and Node.js.

---

## React Integration

### Installation

```bash
# No additional packages required — uses native fetch API
# Optional: install axios for convenience
npm install axios
```

### API Client Hook (React)

```jsx
// src/hooks/useFallingFruitApi.js
import { useState, useCallback } from 'react';

const BASE_URL = process.env.REACT_APP_API_URL || 'http://localhost:3300/api/0.3';
const API_KEY = process.env.REACT_APP_API_KEY || 'dev-api-key-change-me';

export function useFallingFruitApi() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const request = useCallback(async (path, options = {}) => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch(`${BASE_URL}${path}`, {
        ...options,
        headers: {
          'x-api-key': API_KEY,
          'Content-Type': 'application/json',
          ...options.headers,
        },
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      return await response.json();
    } catch (err) {
      setError(err.message);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { request, loading, error };
}
```

### Location Map Component (React + Leaflet)

```jsx
// src/components/ForagingMap.jsx
import { useEffect, useState, useRef } from 'react';
import { MapContainer, TileLayer, Marker, Popup } from 'react-leaflet';
import { useFallingFruitApi } from '../hooks/useFallingFruitApi';

// Bay Area default center
const DEFAULT_CENTER = [37.5, -122.0];
const DEFAULT_ZOOM = 10;

export function ForagingMap() {
  const [locations, setLocations] = useState([]);
  const [types, setTypes] = useState({});
  const { request, loading, error } = useFallingFruitApi();
  const mapRef = useRef(null);

  // Load type names on mount
  useEffect(() => {
    request('/types').then(data => {
      const typesMap = {};
      data.forEach(t => { typesMap[t.id] = t.en_name || t.name; });
      setTypes(typesMap);
    });
  }, []);

  // Load locations when map moves
  const handleMapMove = useCallback(async (map) => {
    const bounds = map.getBounds();
    const sw = bounds.getSouthWest();
    const ne = bounds.getNorthEast();
    const boundsStr = `${sw.lat},${sw.lng}|${ne.lat},${ne.lng}`;

    const data = await request(`/locations?bounds=${boundsStr}&limit=200`);
    setLocations(data);
  }, [request]);

  return (
    <div style={{ height: '600px', width: '100%' }}>
      {loading && <div className="loading-overlay">Loading...</div>}
      {error && <div className="error-banner">Error: {error}</div>}

      <MapContainer
        center={DEFAULT_CENTER}
        zoom={DEFAULT_ZOOM}
        style={{ height: '100%', width: '100%' }}
        ref={mapRef}
      >
        <TileLayer
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          attribution='© OpenStreetMap contributors'
        />

        {locations.map(location => (
          <Marker
            key={location.id}
            position={[location.lat, location.lng]}
          >
            <Popup>
              <strong>
                {location.type_ids?.map(id => types[id]).filter(Boolean).join(', ')}
              </strong>
              {location.description && <p>{location.description}</p>}
            </Popup>
          </Marker>
        ))}
      </MapContainer>
    </div>
  );
}
```

### Location Search Component

```jsx
// src/components/LocationSearch.jsx
import { useState } from 'react';
import { useFallingFruitApi } from '../hooks/useFallingFruitApi';

export function LocationSearch({ onResults }) {
  const [bounds, setBounds] = useState('37.124,-122.519|37.884,-121.208');
  const [typeFilter, setTypeFilter] = useState('');
  const { request, loading } = useFallingFruitApi();

  const handleSearch = async (e) => {
    e.preventDefault();
    const params = new URLSearchParams({ bounds, limit: '100' });
    if (typeFilter) params.set('types', typeFilter);

    const results = await request(`/locations?${params}`);
    onResults(results);
  };

  return (
    <form onSubmit={handleSearch}>
      <input
        value={bounds}
        onChange={e => setBounds(e.target.value)}
        placeholder="swlat,swlng|nelat,nelng"
      />
      <input
        value={typeFilter}
        onChange={e => setTypeFilter(e.target.value)}
        placeholder="Type IDs (e.g., 1,2,3)"
      />
      <button type="submit" disabled={loading}>
        {loading ? 'Searching...' : 'Search'}
      </button>
    </form>
  );
}
```

### Environment Setup (React)

```bash
# .env (React app)
REACT_APP_API_URL=http://YOUR-EC2-IP:3300/api/0.3
REACT_APP_API_KEY=your-api-key
```

---

## Python Backend Integration

### Flask API Proxy

```python
# app.py — Flask backend that proxies to Falling Fruit API
from flask import Flask, request, jsonify
import requests
import os

app = Flask(__name__)

FF_API_URL = os.environ.get('FF_API_URL', 'http://localhost:3300/api/0.3')
FF_API_KEY = os.environ.get('FF_API_KEY', 'your-api-key')

ff_session = requests.Session()
ff_session.headers.update({'x-api-key': FF_API_KEY})


@app.route('/foraging/locations')
def get_locations():
    """Proxy location queries to the Falling Fruit API."""
    bounds = request.args.get('bounds')
    if not bounds:
        return jsonify({'error': 'bounds parameter required'}), 400

    params = {
        'bounds': bounds,
        'limit': request.args.get('limit', 100),
        'offset': request.args.get('offset', 0),
    }

    if request.args.get('types'):
        params['types'] = request.args['types']

    try:
        response = ff_session.get(f'{FF_API_URL}/locations', params=params)
        response.raise_for_status()
        return jsonify(response.json())
    except requests.RequestException as e:
        return jsonify({'error': str(e)}), 502


@app.route('/foraging/types')
def get_types():
    """Get all plant/tree types."""
    try:
        response = ff_session.get(f'{FF_API_URL}/types')
        response.raise_for_status()
        return jsonify(response.json())
    except requests.RequestException as e:
        return jsonify({'error': str(e)}), 502


if __name__ == '__main__':
    app.run(debug=True, port=5000)
```

### Django Integration

```python
# foraging/client.py — Falling Fruit API client
import requests
from django.conf import settings
from django.core.cache import cache


class FallingFruitClient:
    def __init__(self):
        self.base_url = settings.FF_API_URL
        self.session = requests.Session()
        self.session.headers.update({
            'x-api-key': settings.FF_API_KEY,
        })

    def get_types(self, cache_timeout=3600):
        """Get types with caching (they rarely change)."""
        cache_key = 'ff_types'
        cached = cache.get(cache_key)
        if cached:
            return cached

        response = self.session.get(f'{self.base_url}/types')
        response.raise_for_status()
        types = response.json()
        cache.set(cache_key, types, cache_timeout)
        return types

    def get_locations(self, bounds, **kwargs):
        """Query locations by bounding box."""
        params = {'bounds': bounds, **kwargs}
        response = self.session.get(f'{self.base_url}/locations', params=params)
        response.raise_for_status()
        return response.json()

    def get_clusters(self, zoom, bounds, **kwargs):
        """Get map clusters for a zoom level."""
        params = {'zoom': zoom, 'bounds': bounds, **kwargs}
        response = self.session.get(f'{self.base_url}/clusters', params=params)
        response.raise_for_status()
        return response.json()


# foraging/views.py
from django.http import JsonResponse
from .client import FallingFruitClient

ff_client = FallingFruitClient()


def locations_view(request):
    bounds = request.GET.get('bounds')
    if not bounds:
        return JsonResponse({'error': 'bounds required'}, status=400)

    locations = ff_client.get_locations(
        bounds=bounds,
        limit=request.GET.get('limit', 100),
    )
    return JsonResponse({'locations': locations})
```

### Async Python (aiohttp)

```python
import aiohttp
import asyncio
import os

FF_API_URL = os.environ.get('FF_API_URL', 'http://localhost:3300/api/0.3')
FF_API_KEY = os.environ.get('FF_API_KEY', 'your-api-key')


async def get_locations_async(bounds: str, limit: int = 100):
    headers = {'x-api-key': FF_API_KEY}
    params = {'bounds': bounds, 'limit': limit}

    async with aiohttp.ClientSession(headers=headers) as session:
        async with session.get(f'{FF_API_URL}/locations', params=params) as resp:
            resp.raise_for_status()
            return await resp.json()


async def main():
    locations = await get_locations_async(
        '37.124,-122.519|37.884,-121.208',
        limit=200
    )
    print(f'Found {len(locations)} locations')


asyncio.run(main())
```

---

## Swift (iOS) Integration

### API Client (Swift)

```swift
// FallingFruitAPI.swift
import Foundation

struct Location: Codable, Identifiable {
    let id: Int
    let lat: Double
    let lng: Double
    let typeIds: [Int]?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id, lat, lng, description
        case typeIds = "type_ids"
    }
}

struct PlantType: Codable, Identifiable {
    let id: Int
    let enName: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case enName = "en_name"
    }

    var displayName: String {
        enName ?? name ?? "Unknown"
    }
}

class FallingFruitAPIClient {
    static let shared = FallingFruitAPIClient()

    private let baseURL: String
    private let apiKey: String

    // Use your EC2 IP or localhost for development
    private init(
        baseURL: String = "http://YOUR-EC2-IP:3300/api/0.3",
        apiKey: String = "your-api-key"
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem] = []) -> URLRequest? {
        var components = URLComponents(string: "\(baseURL)\(path)")
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    func getTypes() async throws -> [PlantType] {
        guard let request = makeRequest(path: "/types") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([PlantType].self, from: data)
    }

    func getLocations(
        southWest: CLLocationCoordinate2D,
        northEast: CLLocationCoordinate2D,
        limit: Int = 100
    ) async throws -> [Location] {
        let bounds = "\(southWest.latitude),\(southWest.longitude)|\(northEast.latitude),\(northEast.longitude)"

        guard let request = makeRequest(path: "/locations", queryItems: [
            URLQueryItem(name: "bounds", value: bounds),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([Location].self, from: data)
    }
}
```

### SwiftUI Map View

```swift
// ForagingMapView.swift
import SwiftUI
import MapKit

struct ForagingMapView: View {
    @State private var locations: [Location] = []
    @State private var types: [Int: String] = [:]
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5, longitude: -122.0),
        span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
    )

    let api = FallingFruitAPIClient.shared

    var body: some View {
        Map(coordinateRegion: $region, annotationItems: locations) { location in
            MapPin(
                coordinate: CLLocationCoordinate2D(
                    latitude: location.lat,
                    longitude: location.lng
                ),
                tint: .green
            )
        }
        .onAppear { Task { await loadData() } }
        .onChange(of: region) { _ in Task { await loadLocations() } }
    }

    func loadData() async {
        do {
            let allTypes = try await api.getTypes()
            types = Dictionary(uniqueKeysWithValues:
                allTypes.map { ($0.id, $0.displayName) }
            )
            await loadLocations()
        } catch {
            print("Failed to load types: \(error)")
        }
    }

    func loadLocations() async {
        let sw = CLLocationCoordinate2D(
            latitude: region.center.latitude - region.span.latitudeDelta / 2,
            longitude: region.center.longitude - region.span.longitudeDelta / 2
        )
        let ne = CLLocationCoordinate2D(
            latitude: region.center.latitude + region.span.latitudeDelta / 2,
            longitude: region.center.longitude + region.span.longitudeDelta / 2
        )

        do {
            locations = try await api.getLocations(southWest: sw, northEast: ne)
        } catch {
            print("Failed to load locations: \(error)")
        }
    }
}
```

---

## Node.js Backend

### Express API Proxy

```javascript
// server.js
const express = require('express');
const axios = require('axios');

const app = express();
const PORT = process.env.PORT || 4000;

const ff = axios.create({
  baseURL: process.env.FF_API_URL || 'http://localhost:3300/api/0.3',
  headers: {
    'x-api-key': process.env.FF_API_KEY || 'your-api-key',
  },
});

// Proxy locations endpoint
app.get('/api/locations', async (req, res) => {
  const { bounds, types, limit = 100 } = req.query;

  if (!bounds) {
    return res.status(400).json({ error: 'bounds parameter required' });
  }

  try {
    const response = await ff.get('/locations', {
      params: { bounds, types, limit },
    });
    res.json(response.data);
  } catch (error) {
    const status = error.response?.status || 502;
    res.status(status).json({ error: error.message });
  }
});

// Proxy types endpoint with caching
let typesCache = null;
let typesCacheTime = 0;

app.get('/api/types', async (req, res) => {
  // Cache for 1 hour
  if (typesCache && Date.now() - typesCacheTime < 3600000) {
    return res.json(typesCache);
  }

  try {
    const response = await ff.get('/types');
    typesCache = response.data;
    typesCacheTime = Date.now();
    res.json(typesCache);
  } catch (error) {
    res.status(502).json({ error: error.message });
  }
});

app.listen(PORT, () => {
  console.log(`Proxy server running on port ${PORT}`);
});
```

### GraphQL Wrapper

```javascript
// schema.js
const { gql } = require('apollo-server-express');
const axios = require('axios');

const ff = axios.create({
  baseURL: process.env.FF_API_URL,
  headers: { 'x-api-key': process.env.FF_API_KEY },
});

const typeDefs = gql`
  type Location {
    id: Int!
    lat: Float!
    lng: Float!
    typeIds: [Int]
    description: String
  }

  type PlantType {
    id: Int!
    name: String
    enName: String
  }

  type Query {
    locations(bounds: String!, limit: Int, types: String): [Location]
    types: [PlantType]
    location(id: Int!): Location
  }
`;

const resolvers = {
  Query: {
    locations: async (_, { bounds, limit = 100, types }) => {
      const params = { bounds, limit };
      if (types) params.types = types;
      const { data } = await ff.get('/locations', { params });
      return data.map(l => ({ ...l, typeIds: l.type_ids }));
    },
    types: async () => {
      const { data } = await ff.get('/types');
      return data.map(t => ({ ...t, enName: t.en_name }));
    },
    location: async (_, { id }) => {
      const { data } = await ff.get(`/locations/${id}`);
      return { ...data, typeIds: data.type_ids };
    },
  },
};

module.exports = { typeDefs, resolvers };
```

---

## CORS Configuration

If your frontend is on a different origin than the API, you'll need to configure CORS on the API. Find the Express app in the cloned API and add:

```javascript
// In falling-fruit-api/src/app.js or similar
const cors = require('cors');

app.use(cors({
  origin: [
    'http://localhost:3000',    // React dev server
    'https://your-app.com',     // Your production domain
  ],
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowedHeaders: ['Content-Type', 'x-api-key', 'Authorization'],
}));
```

---

## Environment Variables

Create `.env` files for each environment:

```bash
# .env.local (development)
REACT_APP_API_URL=http://localhost:3300/api/0.3
REACT_APP_API_KEY=dev-api-key-change-me

# .env.production (production build)
REACT_APP_API_URL=http://YOUR-EC2-IP:3300/api/0.3
REACT_APP_API_KEY=your-production-api-key
```

---

## Rate Limiting Considerations

When self-hosting, there are no external rate limits. However, for production:

1. **Cache type data** — types rarely change; cache for 1+ hours
2. **Implement request debouncing** — avoid firing on every map pan pixel
3. **Use cluster endpoint** for zoomed-out views instead of loading all locations
4. **Add pagination** — use `limit` and `offset` params for large datasets
