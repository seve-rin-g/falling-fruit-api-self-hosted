-- =============================================================================
-- Falling Fruit API — Database Schema Initialization
-- =============================================================================
-- This script initializes the PostgreSQL database with PostGIS and creates
-- the tables needed by the Falling Fruit API.
--
-- Usage:
--   # As postgres superuser:
--   sudo -u postgres psql -d falling_fruit -f scripts/init-db.sql
--
--   # Via Docker:
--   docker compose exec -T db psql -U ffuser falling_fruit < scripts/init-db.sql
--
-- Note: This is a simplified schema for self-hosted use. The production
-- Falling Fruit database may have additional columns, constraints, and
-- data not included here. Run this once on a fresh database.
-- =============================================================================

-- =============================================================================
-- Extensions
-- =============================================================================

-- PostGIS enables geographic/spatial data types and functions
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;

-- Full-text search support
CREATE EXTENSION IF NOT EXISTS unaccent;

-- UUID generation (for tokens, etc.)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =============================================================================
-- Types (Plant/Tree taxonomy)
-- =============================================================================

CREATE TABLE IF NOT EXISTS types (
    -- Unique identifier (matches the public Falling Fruit API).
    -- SERIAL PRIMARY KEY so new types inserted without an explicit id receive unique ids.
    -- Migration note: if upgrading an existing DB, run:
    --   CREATE SEQUENCE IF NOT EXISTS types_id_seq;
    --   ALTER TABLE types ALTER COLUMN id SET DEFAULT nextval('types_id_seq');
    --   SELECT setval('types_id_seq', COALESCE(MAX(id), 0)) FROM types;
    id                  SERIAL PRIMARY KEY,

    -- English common name (e.g., "Apple", "Fig")
    en_name             TEXT,

    -- Scientific/Latin name (e.g., "Malus domestica")
    scientific_name     TEXT,

    -- Common name in other languages
    name                TEXT,

    -- Synonyms (pipe-separated)
    synonyms            TEXT,

    -- Whether this is an invasive species
    invasive            BOOLEAN DEFAULT FALSE,

    -- Whether this is a foraging type (vs informational)
    foraging            BOOLEAN DEFAULT TRUE,

    -- URL-friendly slug
    slug                TEXT,

    -- Creation and update timestamps
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for name searches
CREATE INDEX IF NOT EXISTS idx_types_en_name ON types USING btree (en_name);
CREATE INDEX IF NOT EXISTS idx_types_scientific_name ON types USING btree (scientific_name);

-- =============================================================================
-- Users
-- =============================================================================

CREATE TABLE IF NOT EXISTS users (
    id                  SERIAL PRIMARY KEY,
    email               TEXT UNIQUE NOT NULL,
    name                TEXT,

    -- BCrypt hashed password
    password_hash       TEXT,

    -- JWT refresh token (null when logged out)
    refresh_token       TEXT,

    -- Email verification
    email_verified      BOOLEAN DEFAULT FALSE,
    verification_token  TEXT,

    -- Admin flag
    admin               BOOLEAN DEFAULT FALSE,

    -- User's preferred language
    locale              TEXT DEFAULT 'en',

    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users USING btree (email);

-- =============================================================================
-- Locations
-- =============================================================================

CREATE TABLE IF NOT EXISTS locations (
    id                  SERIAL PRIMARY KEY,

    -- Geographic coordinates
    lat                 DOUBLE PRECISION NOT NULL,
    lng                 DOUBLE PRECISION NOT NULL,

    -- PostGIS geometry column (SRID 4326 = WGS84, standard GPS coordinates)
    -- This is what enables fast geographic queries (bounding box, distance, etc.)
    latlon              GEOMETRY(Point, 4326),

    -- Location details
    description         TEXT,
    access              INTEGER DEFAULT 1,  -- 1=public, 2=private, 3=restricted

    -- Creator (null for imported/anonymous locations)
    user_id             INTEGER REFERENCES users(id) ON DELETE SET NULL,

    -- Import batch (for bulk-imported locations)
    import_id           INTEGER,

    -- Whether this is a "muni" (municipal/government) location
    muni                BOOLEAN DEFAULT FALSE,

    -- Whether this species is invasive at this location
    invasive            BOOLEAN DEFAULT FALSE,

    -- Season/availability information
    season_start        INTEGER,  -- Month number (1-12)
    season_stop         INTEGER,  -- Month number (1-12)
    no_season           BOOLEAN DEFAULT FALSE,

    -- Photo thumbnail URL
    photo_url           TEXT,

    -- Moderation
    unverified          BOOLEAN DEFAULT FALSE,

    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =============================================================================
-- CRITICAL: Spatial index on the geometry column
-- This is what makes bounding box queries fast (required for good performance)
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_locations_latlon ON locations USING GIST (latlon);

-- Additional indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_locations_lat_lng ON locations (lat, lng);
CREATE INDEX IF NOT EXISTS idx_locations_user_id ON locations (user_id);
CREATE INDEX IF NOT EXISTS idx_locations_created_at ON locations (created_at DESC);

-- =============================================================================
-- Trigger: Keep latlon geometry in sync with lat/lng columns
-- =============================================================================

CREATE OR REPLACE FUNCTION update_location_geometry()
RETURNS TRIGGER AS $$
BEGIN
    -- Update the PostGIS geometry whenever lat or lng changes
    IF NEW.lat IS NOT NULL AND NEW.lng IS NOT NULL THEN
        NEW.latlon := ST_SetSRID(ST_MakePoint(NEW.lng, NEW.lat), 4326);
    END IF;
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_location_geometry ON locations;
CREATE TRIGGER trigger_update_location_geometry
    BEFORE INSERT OR UPDATE OF lat, lng ON locations
    FOR EACH ROW
    EXECUTE FUNCTION update_location_geometry();

-- =============================================================================
-- Location Types (Many-to-Many: locations ↔ types)
-- =============================================================================

CREATE TABLE IF NOT EXISTS location_types (
    location_id         INTEGER NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
    type_id             INTEGER NOT NULL REFERENCES types(id) ON DELETE CASCADE,

    PRIMARY KEY (location_id, type_id)
);

CREATE INDEX IF NOT EXISTS idx_location_types_type_id ON location_types (type_id);
CREATE INDEX IF NOT EXISTS idx_location_types_location_id ON location_types (location_id);

-- =============================================================================
-- Reviews (User reviews/observations of locations)
-- =============================================================================

CREATE TABLE IF NOT EXISTS reviews (
    id                  SERIAL PRIMARY KEY,
    location_id         INTEGER NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
    user_id             INTEGER REFERENCES users(id) ON DELETE SET NULL,

    -- Rating (1-5, or null if not rated)
    rating              INTEGER CHECK (rating BETWEEN 1 AND 5),

    -- Review text
    body                TEXT,

    -- Photo
    photo_url           TEXT,
    photo_caption       TEXT,

    -- Observation date
    observed_on         DATE,

    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reviews_location_id ON reviews (location_id);
CREATE INDEX IF NOT EXISTS idx_reviews_user_id ON reviews (user_id);

-- =============================================================================
-- Imports (Bulk data import history)
-- =============================================================================

CREATE TABLE IF NOT EXISTS imports (
    id                  SERIAL PRIMARY KEY,

    -- Source/organization name
    name                TEXT NOT NULL,

    -- URL or description of the data source
    url                 TEXT,

    -- Number of locations imported
    location_count      INTEGER DEFAULT 0,

    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =============================================================================
-- Schema Version (for tracking migrations)
-- =============================================================================

CREATE TABLE IF NOT EXISTS schema_version (
    version             INTEGER PRIMARY KEY,
    applied_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    description         TEXT
);

INSERT INTO schema_version (version, description)
VALUES (1, 'Initial schema for self-hosted Falling Fruit API')
ON CONFLICT (version) DO NOTHING;

-- =============================================================================
-- Summary
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE '=================================================';
    RAISE NOTICE 'Database schema initialized successfully!';
    RAISE NOTICE '';
    RAISE NOTICE 'Tables created:';
    RAISE NOTICE '  - types           (plant/tree taxonomy)';
    RAISE NOTICE '  - users           (user accounts)';
    RAISE NOTICE '  - locations       (foraging spots with PostGIS)';
    RAISE NOTICE '  - location_types  (many-to-many: locations-types)';
    RAISE NOTICE '  - reviews         (user reviews and photos)';
    RAISE NOTICE '  - imports         (bulk import history)';
    RAISE NOTICE '  - schema_version  (migration tracking)';
    RAISE NOTICE '';
    RAISE NOTICE 'PostGIS extensions enabled:';
    RAISE NOTICE '  - postgis (spatial data)';
    RAISE NOTICE '  - postgis_topology';
    RAISE NOTICE '';
    RAISE NOTICE 'Next step: Import data using scripts/import-from-api.sh';
    RAISE NOTICE '         or scripts/import-from-csv.sh data/locations.csv.bz2';
    RAISE NOTICE '=================================================';
END $$;
