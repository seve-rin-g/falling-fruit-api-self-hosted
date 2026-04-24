# =============================================================================
# Falling Fruit API — Dockerfile
# =============================================================================
# Multi-stage build using Alpine Linux for minimal image size.
#
# Build stages:
#   1. deps    - Install all dependencies (including devDependencies)
#   2. prod    - Install only production dependencies
#   3. runner  - Final minimal image
#
# Usage:
#   docker build -t falling-fruit-api .
#   docker run -p 3300:3300 --env-file .env falling-fruit-api
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Install dependencies
# -----------------------------------------------------------------------------
FROM node:16-alpine AS deps

# Install build tools needed for native Node.js modules
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git

WORKDIR /app

# Copy package files first (Docker layer caching optimization)
COPY falling-fruit-api/package.json falling-fruit-api/yarn.lock* ./

# Install all dependencies (including devDependencies for building)
RUN yarn install --frozen-lockfile

# -----------------------------------------------------------------------------
# Stage 2: Production dependencies only
# -----------------------------------------------------------------------------
FROM node:16-alpine AS prod-deps

WORKDIR /app
COPY falling-fruit-api/package.json falling-fruit-api/yarn.lock* ./

# Install only production dependencies
RUN yarn install --frozen-lockfile --production

# -----------------------------------------------------------------------------
# Stage 3: Final runner image
# -----------------------------------------------------------------------------
FROM node:16-alpine AS runner

# Install runtime dependencies
RUN apk add --no-cache \
    # For healthcheck curl command
    curl \
    # For timezone support
    tzdata

# Create non-root user for security
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 --ingroup nodejs nodeuser

WORKDIR /app

# Copy production dependencies from prod-deps stage
COPY --from=prod-deps --chown=nodeuser:nodejs /app/node_modules ./node_modules

# Copy application source code
COPY --chown=nodeuser:nodejs falling-fruit-api/ .

# Switch to non-root user
USER nodeuser

# Expose the API port
EXPOSE 3300

# Health check — verifies API is responding
# Starts checking after 30s, checks every 30s, fails after 3 misses
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:${PORT:-3300}${API_BASE:-/api/0.3}/types || exit 1

# Start the API
CMD ["yarn", "start"]
