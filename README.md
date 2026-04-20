# 🍎 Falling Fruit API — Self-Hosted Setup Guide

A complete guide to deploying the [Falling Fruit API](https://github.com/falling-fruit/falling-fruit-api) on your own AWS EC2 instance. Self-host the API with your own data so you can use it freely in your own applications without requiring an API key from the Falling Fruit project.

## Table of Contents

1. [What Is This?](#what-is-this)
2. [Quick Start (Docker)](#quick-start-docker)
3. [AWS EC2 Setup Guide](#aws-ec2-setup-guide)
4. [Database Setup](#database-setup)
5. [Security Configuration](#security-configuration)
6. [Monitoring & Logs](#monitoring--logs)
7. [Troubleshooting](#troubleshooting)

---

## What Is This?

The [Falling Fruit API](https://fallingfruit.org) is an open-source REST API for community foraging maps. It provides:

- 🗺️ **Location data** — foraging spots with GPS coordinates and plant types
- 🌿 **Type taxonomy** — hundreds of plant/tree categories
- 📍 **Geographic clustering** — efficient map rendering at any zoom level
- 👤 **User management** — accounts, contributions, reviews
- 📸 **Photo uploads** — location photos via AWS S3

This repository contains everything you need to:
1. Deploy the API on an **AWS EC2** instance
2. Run it locally with **Docker**
3. **Populate** the database from the public Falling Fruit API
4. **Integrate** the API into your own web/mobile application

---

## Quick Start (Docker)

The fastest way to get a local instance running:

```bash
# Clone this setup guide
git clone https://github.com/seve-rin-g/falling-fruit-api-self-hosted.git
cd falling-fruit-api-self-hosted

# Clone the actual API
git clone https://github.com/falling-fruit/falling-fruit-api.git

# Copy environment file
cp .env.example falling-fruit-api/.env

# Start everything with Docker Compose
docker compose up -d

# Check it's running
curl http://localhost:3300/api/0.3/types | head -c 200
```

See [DOCKER-SETUP.md](DOCKER-SETUP.md) for the full Docker guide.

---

## AWS EC2 Setup Guide

### Step 1: Launch Your EC2 Instance

1. Go to the **AWS Console → EC2 → Launch Instance**
2. Choose settings:
   - **AMI**: Ubuntu Server 22.04 LTS (Free Tier eligible)
   - **Instance type**: `t3.micro` (free tier) or `t3.small` for better performance
   - **Storage**: 30 GB gp3 (free tier eligible)
   - **Key pair**: Create or select an existing key pair (download the `.pem` file!)
3. **Security Group** — Add these inbound rules:
   | Port | Protocol | Source | Description |
   |------|----------|--------|-------------|
   | 22   | TCP      | Your IP | SSH access |
   | 3300 | TCP      | 0.0.0.0/0 | API access |
   | 80   | TCP      | 0.0.0.0/0 | HTTP (optional NGINX) |
   | 443  | TCP      | 0.0.0.0/0 | HTTPS (optional NGINX) |
4. Launch the instance and note your **Public IP address**

### Step 2: Connect to Your Instance

```bash
# Set correct permissions on your key
chmod 400 your-key.pem

# Connect via SSH
ssh -i your-key.pem ubuntu@YOUR-EC2-PUBLIC-IP
```

### Step 3: Run the Automated Setup Script

```bash
# On your EC2 instance:

# Download this setup repository
git clone https://github.com/seve-rin-g/falling-fruit-api-self-hosted.git
cd falling-fruit-api-self-hosted

# Make scripts executable
chmod +x scripts/*.sh

# Run the automated setup (installs Node.js, Yarn, PostgreSQL, PostGIS)
sudo bash scripts/setup.sh
```

The setup script installs and configures:
- **Node.js 20 LTS** + Yarn
- **PostgreSQL 14** + PostGIS extension
- **Falling Fruit API** cloned to `/opt/falling-fruit-api`
- **Systemd service** for auto-start on boot

### Step 4: Configure Your Environment

```bash
# Edit the environment configuration
sudo nano /etc/falling-fruit-api/.env
```

Minimum required settings:

```env
NODE_ENV=production
PORT=3300
API_BASE=/api/0.3

# Database (auto-configured by setup.sh)
DB=postgres://ffuser:CHANGE_THIS_PASSWORD@localhost:5432/falling_fruit

# Security keys (CHANGE THESE!)
JWT_SECRET=your-very-long-random-secret-key-here
API_KEY=your-custom-api-key-for-your-application

# Disable optional services (uncomment to enable)
# RECAPTCHA_SITE_KEY=your-recaptcha-key
# RECAPTCHA_SECRET_KEY=your-recaptcha-secret
# S3_BUCKET=your-s3-bucket
# POSTMARK_API_TOKEN=your-postmark-token
```

Generate secure random keys:
```bash
# Generate JWT_SECRET
openssl rand -hex 64

# Generate API_KEY
openssl rand -hex 32
```

### Step 5: Initialize the Database

```bash
# Initialize PostgreSQL schema with PostGIS
sudo -u postgres psql -d falling_fruit -f /opt/falling-fruit-api/db/schema.sql

# Or use the included init script
sudo -u postgres psql -d falling_fruit -f /home/ubuntu/falling-fruit-api-self-hosted/scripts/init-db.sql
```

### Step 6: Populate with Data

**Option A — Import from Public API (Recommended)**

```bash
# Import Bay Area data (customize bounds as needed)
bash scripts/import-from-api.sh \
  --bounds "37.124,-122.519|37.884,-121.208" \
  --output /tmp/bay-area-locations.json

# The script auto-loads data into your database
```

**Option B — Use a Database Dump** (if you have one)

```bash
# Restore from dump
pg_restore -U ffuser -d falling_fruit -F c falling-fruit-dump.dump
```

**Option C — Start Empty**

The database will be empty but the API will still function. You can add locations via the API.

### Step 7: Start the API Service

```bash
# Start the API
sudo systemctl start falling-fruit-api

# Enable auto-start on reboot
sudo systemctl enable falling-fruit-api

# Check status
sudo systemctl status falling-fruit-api

# Test it works
curl -H "x-api-key: your-custom-api-key" \
  "http://YOUR-EC2-IP:3300/api/0.3/types" | head -c 200
```

---

## Database Setup

### PostgreSQL with PostGIS

PostGIS is required for geographic queries (bounding box filtering, clustering, etc.). The `setup.sh` script installs it automatically, or you can install manually:

```bash
# Install PostGIS
sudo apt install -y postgresql-14-postgis-3

# Enable in your database
sudo -u postgres psql -d falling_fruit -c "CREATE EXTENSION IF NOT EXISTS postgis;"
sudo -u postgres psql -d falling_fruit -c "CREATE EXTENSION IF NOT EXISTS postgis_topology;"
```

### Schema Overview

The key tables in the Falling Fruit database are:

| Table | Description |
|-------|-------------|
| `locations` | Foraging spots with PostGIS geometry |
| `types` | Plant/tree taxonomy |
| `location_types` | Many-to-many: locations ↔ types |
| `users` | User accounts |
| `reviews` | Location reviews and photos |
| `imports` | Bulk data import history |

---

## Security Configuration

### API Key Authentication

By default, all API endpoints require an `x-api-key` header:

```bash
curl -H "x-api-key: YOUR_API_KEY" http://your-ec2-ip:3300/api/0.3/types
```

Your `API_KEY` environment variable controls what key is accepted.

### Disabling API Key Requirement (Development Only)

For local development, you may want to remove the API key check. Find the middleware in the cloned API:

```bash
# In /opt/falling-fruit-api — look for API key middleware
grep -r "x-api-key" /opt/falling-fruit-api/src/
```

### Firewall with UFW

```bash
# Enable UFW firewall
sudo ufw enable

# Allow only necessary ports
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 3300/tcp  # API
# sudo ufw allow 80/tcp  # HTTP (if using NGINX)
# sudo ufw allow 443/tcp # HTTPS (if using NGINX)

# Check status
sudo ufw status
```

### Optional: NGINX Reverse Proxy with HTTPS

```bash
# Install NGINX and Certbot
sudo apt install -y nginx certbot python3-certbot-nginx

# Configure NGINX (see templates directory)
sudo nano /etc/nginx/sites-available/falling-fruit-api

# Get free SSL certificate (requires a domain name)
sudo certbot --nginx -d api.yourdomain.com
```

---

## Monitoring & Logs

### View API Logs

```bash
# Follow live logs
sudo journalctl -u falling-fruit-api -f

# View last 100 lines
sudo journalctl -u falling-fruit-api -n 100

# View logs since a specific time
sudo journalctl -u falling-fruit-api --since "2024-01-01 00:00:00"
```

### Service Management

```bash
# Check status
sudo systemctl status falling-fruit-api

# Restart after config changes
sudo systemctl restart falling-fruit-api

# Stop the service
sudo systemctl stop falling-fruit-api

# View resource usage
top -p $(pgrep -f "node.*app.js")
```

### Database Monitoring

```bash
# Connect to database
sudo -u postgres psql -d falling_fruit

# Count locations
SELECT COUNT(*) FROM locations;

# Check database size
SELECT pg_size_pretty(pg_database_size('falling_fruit'));

# Active connections
SELECT COUNT(*) FROM pg_stat_activity WHERE datname = 'falling_fruit';
```

---

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed solutions to common issues.

### Quick Fixes

| Issue | Solution |
|-------|----------|
| `Connection refused` | Check `sudo systemctl status falling-fruit-api` |
| `401 Unauthorized` | Ensure `x-api-key` header matches your `API_KEY` env var |
| `502 Bad Gateway` | API is down; check logs with `journalctl -u falling-fruit-api` |
| `No locations returned` | Database may be empty; run the import script |
| `PostGIS error` | Run `CREATE EXTENSION postgis;` in your database |

---

## Related Documentation

- 📦 [DOCKER-SETUP.md](DOCKER-SETUP.md) — Local Docker development guide
- ⚡ [QUICK-REFERENCE.md](QUICK-REFERENCE.md) — Common commands and API examples
- 🔗 [INTEGRATION-GUIDE.md](INTEGRATION-GUIDE.md) — React, Python, Swift integration
- 🔧 [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — Detailed issue resolutions
- 💰 [COST-OPTIMIZATION.md](COST-OPTIMIZATION.md) — AWS cost breakdown
- 🗺️ [GETTING-STARTED.md](GETTING-STARTED.md) — Docker vs AWS decision guide

---

## Contributing

This setup guide is open source. If you find issues or improvements:
1. Fork this repository
2. Create a branch: `git checkout -b fix/your-fix`
3. Submit a pull request

## License

This setup guide is released under the [GPL-3.0 License](LICENSE).  
The Falling Fruit API itself is copyright Falling Fruit contributors — see [their repository](https://github.com/falling-fruit/falling-fruit-api).
