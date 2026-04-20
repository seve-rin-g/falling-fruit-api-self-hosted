#!/usr/bin/env bash
# =============================================================================
# Falling Fruit API — Automated AWS EC2 Setup Script
# =============================================================================
# This script sets up everything needed to run the Falling Fruit API on
# a fresh Ubuntu 22.04 LTS AWS EC2 instance.
#
# What this script installs:
#   - Node.js 20 LTS and Yarn
#   - PostgreSQL 14 with PostGIS 3
#   - The Falling Fruit API (cloned from GitHub)
#   - Systemd service for auto-start on boot
#
# Usage (run as root or with sudo):
#   sudo bash scripts/setup.sh
#
# Requirements:
#   - Ubuntu 22.04 LTS
#   - Internet access
#   - Run as root or with sudo
# =============================================================================

set -euo pipefail  # Exit on error, unbound variables, pipe failures

# =============================================================================
# Configuration — Modify these if needed
# =============================================================================

# Falling Fruit API repository URL
FF_API_REPO="https://github.com/falling-fruit/falling-fruit-api.git"

# Installation directory for the API
INSTALL_DIR="/opt/falling-fruit-api"

# Directory for environment configuration
ENV_DIR="/etc/falling-fruit-api"

# PostgreSQL settings
DB_NAME="falling_fruit"
DB_USER="ffuser"
# Generate a random password for the database user
DB_PASS=$(openssl rand -hex 16)

# Service name for systemd
SERVICE_NAME="falling-fruit-api"

# User to run the service as (change if different)
SERVICE_USER="${SUDO_USER:-ubuntu}"

# Node.js version to install
NODE_VERSION="20"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root. Use: sudo bash scripts/setup.sh"
    fi
}

check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
        log_warn "This script is designed for Ubuntu. Other distributions may not work correctly."
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# =============================================================================
# Main Setup Steps
# =============================================================================

echo ""
echo "============================================="
echo " Falling Fruit API — EC2 Setup Script"
echo "============================================="
echo ""

# Step 0: Pre-flight checks
check_root
check_ubuntu

log_info "Service user: ${SERVICE_USER}"
log_info "Install directory: ${INSTALL_DIR}"
log_info "Environment directory: ${ENV_DIR}"
echo ""

# =============================================================================
# Step 1: System Updates
# =============================================================================
log_info "Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
    curl \
    wget \
    git \
    jq \
    openssl \
    ca-certificates \
    gnupg \
    lsb-release \
    build-essential
log_success "System packages updated"

# =============================================================================
# Step 2: Install Node.js
# =============================================================================
log_info "Installing Node.js ${NODE_VERSION} LTS..."

if command -v node &> /dev/null; then
    CURRENT_NODE=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [[ "$CURRENT_NODE" -ge "$NODE_VERSION" ]]; then
        log_success "Node.js $(node --version) already installed"
    else
        log_warn "Upgrading Node.js from v${CURRENT_NODE} to v${NODE_VERSION}..."
    fi
fi

# Install Node.js via NodeSource (official repository)
curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash -
apt-get install -y nodejs
log_success "Node.js $(node --version) installed"

# Install Yarn package manager
npm install -g yarn --quiet
log_success "Yarn $(yarn --version) installed"

# =============================================================================
# Step 3: Install PostgreSQL + PostGIS
# =============================================================================
log_info "Installing PostgreSQL 14 + PostGIS 3..."

# Add PostgreSQL apt repository
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
    gpg --dearmor -o /usr/share/keyrings/postgresql.gpg

echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] \
    https://apt.postgresql.org/pub/repos/apt \
    $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

apt-get update -qq
apt-get install -y -qq postgresql-14 postgresql-14-postgis-3
log_success "PostgreSQL $(psql --version | awk '{print $3}') + PostGIS 3 installed"

# Start and enable PostgreSQL
systemctl start postgresql
systemctl enable postgresql
log_success "PostgreSQL service started and enabled"

# =============================================================================
# Step 4: Set Up PostgreSQL Database
# =============================================================================
log_info "Setting up PostgreSQL database..."

# Create database user and database
sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';" 2>/dev/null || \
    sudo -u postgres psql -c "ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"

sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};" 2>/dev/null || \
    log_warn "Database ${DB_NAME} already exists — skipping creation"

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"

# Enable PostGIS extensions
sudo -u postgres psql -d "${DB_NAME}" -c "CREATE EXTENSION IF NOT EXISTS postgis;"
sudo -u postgres psql -d "${DB_NAME}" -c "CREATE EXTENSION IF NOT EXISTS postgis_topology;"

log_success "Database '${DB_NAME}' created with user '${DB_USER}'"
log_success "PostGIS extensions enabled"

# =============================================================================
# Step 5: Clone and Install the Falling Fruit API
# =============================================================================
log_info "Cloning Falling Fruit API to ${INSTALL_DIR}..."

if [[ -d "${INSTALL_DIR}" ]]; then
    log_warn "Directory ${INSTALL_DIR} already exists — pulling latest changes"
    cd "${INSTALL_DIR}" && git pull
else
    git clone "${FF_API_REPO}" "${INSTALL_DIR}"
fi

# Set ownership to the service user
chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}"

# Install Node.js dependencies as the service user
log_info "Installing Node.js dependencies (this may take a minute)..."
cd "${INSTALL_DIR}"
sudo -u "${SERVICE_USER}" yarn install --production
log_success "Dependencies installed"

# =============================================================================
# Step 6: Configure Environment
# =============================================================================
log_info "Setting up environment configuration..."

# Create env directory
mkdir -p "${ENV_DIR}"
chown -R "${SERVICE_USER}:${SERVICE_USER}" "${ENV_DIR}"
chmod 750 "${ENV_DIR}"

# Generate security keys
JWT_SECRET=$(openssl rand -hex 64)
API_KEY=$(openssl rand -hex 32)

# Create the environment file
cat > "${ENV_DIR}/.env" << EOF
# Falling Fruit API — Production Environment
# Generated by setup.sh on $(date)
# Edit this file and restart the service: sudo systemctl restart ${SERVICE_NAME}

NODE_ENV=production
PORT=3300
API_BASE=/api/0.3

# Database connection
DB=postgres://${DB_USER}:${DB_PASS}@localhost:5432/${DB_NAME}

# Security keys (auto-generated — keep these secret!)
JWT_SECRET=${JWT_SECRET}
API_KEY=${API_KEY}

# Optional services (uncomment and configure as needed)
# RECAPTCHA_SITE_KEY=
# RECAPTCHA_SECRET_KEY=
# S3_BUCKET=
# S3_REGION=us-east-1
# AWS_ACCESS_KEY_ID=
# AWS_SECRET_ACCESS_KEY=
# POSTMARK_API_TOKEN=
# EMAIL_FROM=noreply@yourdomain.com

# Performance
MAX_LIMIT=1000
LOG_QUERIES=false
CORS_ORIGIN=*
NODE_OPTIONS=--max-old-space-size=512
EOF

# Restrict permissions on env file (contains secrets)
chmod 640 "${ENV_DIR}/.env"
chown "${SERVICE_USER}:${SERVICE_USER}" "${ENV_DIR}/.env"

log_success "Environment configuration created at ${ENV_DIR}/.env"

# =============================================================================
# Step 7: Initialize Database Schema
# =============================================================================
log_info "Initializing database schema..."

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

if [[ -f "${SCRIPT_DIR}/init-db.sql" ]]; then
    sudo -u postgres psql -d "${DB_NAME}" -f "${SCRIPT_DIR}/init-db.sql"
    log_success "Database schema initialized"
elif [[ -f "${INSTALL_DIR}/db/schema.sql" ]]; then
    sudo -u postgres psql -d "${DB_NAME}" -f "${INSTALL_DIR}/db/schema.sql"
    log_success "Database schema initialized from API repo"
else
    log_warn "No schema SQL file found — you'll need to initialize the schema manually"
    log_warn "Try: sudo -u postgres psql -d ${DB_NAME} -f /path/to/schema.sql"
fi

# =============================================================================
# Step 8: Install Systemd Service
# =============================================================================
log_info "Installing systemd service..."

SETUP_DIR="$(dirname "$(dirname "$(readlink -f "$0")")")"
SERVICE_TEMPLATE="${SETUP_DIR}/templates/falling-fruit-api.service"

if [[ -f "${SERVICE_TEMPLATE}" ]]; then
    cp "${SERVICE_TEMPLATE}" "/etc/systemd/system/${SERVICE_NAME}.service"
else
    # Create service file inline if template not found
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << SVCEOF
[Unit]
Description=Falling Fruit API (Node.js)
After=network.target postgresql.service
Requires=network.target

[Service]
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${ENV_DIR}/.env
ExecStart=/usr/bin/yarn start
Restart=always
RestartSec=5
TimeoutStartSec=30
TimeoutStopSec=30
NoNewPrivileges=true
PrivateTmp=true
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
SVCEOF
fi

# Reload systemd and enable service
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
log_success "Systemd service installed and enabled"

# =============================================================================
# Step 9: Configure UFW Firewall (Optional)
# =============================================================================
if command -v ufw &> /dev/null; then
    log_info "Configuring UFW firewall..."
    ufw allow ssh    # Port 22 — SSH (important: always allow this first!)
    ufw allow 3300   # API port
    log_success "UFW rules added (SSH and port 3300)"
    log_warn "UFW not enabled automatically. Run 'sudo ufw enable' when ready."
fi

# =============================================================================
# Setup Complete!
# =============================================================================

echo ""
echo "============================================="
echo " Setup Complete!"
echo "============================================="
echo ""
echo "Database credentials:"
echo "  Name:     ${DB_NAME}"
echo "  User:     ${DB_USER}"
echo "  Password: ${DB_PASS}"
echo ""
echo "API key (add this to your application):"
echo "  API_KEY: ${API_KEY}"
echo ""
echo "Next steps:"
echo "  1. Review config:   sudo nano ${ENV_DIR}/.env"
echo "  2. Start service:   sudo systemctl start ${SERVICE_NAME}"
echo "  3. Check status:    sudo systemctl status ${SERVICE_NAME}"
echo "  4. View logs:       sudo journalctl -u ${SERVICE_NAME} -f"
echo "  5. Import data:     bash scripts/import-from-api.sh --bounds '37,-122|38,-121'"
echo "  6. Test API:        curl -H 'x-api-key: ${API_KEY}' http://localhost:3300/api/0.3/types"
echo ""
echo "⚠️  IMPORTANT: Save your database password and API key above!"
echo "   They are also saved in ${ENV_DIR}/.env"
echo "============================================="
