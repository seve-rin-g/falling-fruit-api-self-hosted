# 🔧 Troubleshooting Guide

Solutions to the most common issues encountered when self-hosting the Falling Fruit API.

---

## Issue 1: API Returns 401 Unauthorized

**Symptom:**
```json
{"error": "Unauthorized", "message": "Invalid or missing API key"}
```

**Causes and Solutions:**

**A) Missing `x-api-key` header**
```bash
# Wrong:
curl http://localhost:3300/api/0.3/types

# Correct:
curl -H "x-api-key: your-api-key" http://localhost:3300/api/0.3/types
```

**B) API key doesn't match environment variable**
```bash
# Check what key the API expects (EC2)
sudo grep API_KEY /etc/falling-fruit-api/.env

# Check what key the API expects (Docker)
docker compose exec api env | grep API_KEY
```

**C) Environment variable not loaded**
```bash
# Restart the service to reload env vars
sudo systemctl restart falling-fruit-api

# Or restart Docker container
docker compose restart api
```

---

## Issue 2: Connection Refused / Cannot Connect

**Symptom:**
```
curl: (7) Failed to connect to localhost port 3300 after 0 ms: Connection refused
```

**Causes and Solutions:**

**A) Service not running**
```bash
# Check status (EC2)
sudo systemctl status falling-fruit-api

# Start if not running
sudo systemctl start falling-fruit-api

# Check Docker
docker compose ps
docker compose up -d
```

**B) Wrong port**
```bash
# Check what port the API is actually listening on
sudo ss -tlnp | grep node
# or
sudo netstat -tlnp | grep node

# Check configured port
grep PORT /etc/falling-fruit-api/.env
```

**C) Firewall blocking port (EC2)**
```bash
# Check UFW rules
sudo ufw status

# Allow port 3300 if blocked
sudo ufw allow 3300/tcp

# Also check AWS Security Group in the AWS Console
# EC2 → Security Groups → Inbound Rules
# Must allow TCP port 3300 from 0.0.0.0/0
```

**D) API crashed on startup**
```bash
# Check logs for crash reason
sudo journalctl -u falling-fruit-api -n 50 --no-pager

# Common startup errors:
# - Database connection failed → see Issue 3
# - Port already in use → change PORT in .env
# - Missing environment variables → check .env file
```

---

## Issue 3: Database Connection Failed

**Symptom:**
```
Error: connect ECONNREFUSED 127.0.0.1:5432
Error: password authentication failed for user "ffuser"
Error: database "falling_fruit" does not exist
```

**Causes and Solutions:**

**A) PostgreSQL not running**
```bash
# Check PostgreSQL status
sudo systemctl status postgresql

# Start if needed
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

**B) Wrong database credentials**
```bash
# Test the connection directly
psql -h localhost -U ffuser -d falling_fruit
# Enter password when prompted

# If it fails, reset the password:
sudo -u postgres psql -c "ALTER USER ffuser PASSWORD 'new-password';"

# Update .env with new password
sudo nano /etc/falling-fruit-api/.env
# Change: DB=postgres://ffuser:new-password@localhost:5432/falling_fruit
```

**C) Database doesn't exist**
```bash
# Check existing databases
sudo -u postgres psql -l

# Create the database if missing
sudo -u postgres createdb falling_fruit
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE falling_fruit TO ffuser;"

# Initialize schema
sudo -u postgres psql -d falling_fruit -f scripts/init-db.sql
```

**D) Docker database not ready**
```bash
# Wait for database health check to pass
docker compose logs db

# Check if PostGIS initialized successfully
docker compose exec db psql -U ffuser falling_fruit -c "SELECT PostGIS_Version();"
```

---

## Issue 4: No Locations Returned / Empty Results

**Symptom:**
```bash
curl -H "x-api-key: key" "http://localhost:3300/api/0.3/locations?bounds=37,-122|38,-121"
# Returns: []
```

**Causes and Solutions:**

**A) Database is empty — needs data import**
```bash
# Check if locations table has any data
sudo -u postgres psql -d falling_fruit -c "SELECT COUNT(*) FROM locations;"
# If count = 0, you need to import data

# Import from public Falling Fruit API
bash scripts/import-from-api.sh \
  --bounds "37.124,-122.519|37.884,-121.208"
```

**B) Bounds format is wrong**
```bash
# Correct format: "swlat,swlng|nelat,nelng"
# Make sure you use pipe (|) to separate SW and NE corners

# Wrong:
bounds=37.124,-122.519,37.884,-121.208

# Correct:
bounds=37.124,-122.519|37.884,-121.208
```

**C) Bounding box is outside your data area**
```bash
# Check what geographic area your data covers
sudo -u postgres psql -d falling_fruit -c "
  SELECT
    ST_YMin(ST_Extent(latlon)) as south,
    ST_XMin(ST_Extent(latlon)) as west,
    ST_YMax(ST_Extent(latlon)) as north,
    ST_XMax(ST_Extent(latlon)) as east
  FROM locations;
"
```

**D) PostGIS extension not installed**
```bash
# Check if PostGIS is available
sudo -u postgres psql -d falling_fruit -c "SELECT PostGIS_Version();"

# If error, install PostGIS:
sudo apt install -y postgresql-14-postgis-3

# Then enable it:
sudo -u postgres psql -d falling_fruit -c "CREATE EXTENSION IF NOT EXISTS postgis;"
sudo -u postgres psql -d falling_fruit -c "CREATE EXTENSION IF NOT EXISTS postgis_topology;"

# Restart API
sudo systemctl restart falling-fruit-api
```

---

## Issue 5: PostGIS / Geographic Query Errors

**Symptom:**
```
Error: function st_within(geometry, geometry) does not exist
Error: type "geography" does not exist
```

**Solution:**

```bash
# Install PostGIS
sudo apt install -y postgresql-14-postgis-3

# Enable extensions in your database
sudo -u postgres psql -d falling_fruit << 'EOF'
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
CREATE EXTENSION IF NOT EXISTS postgis_tiger_geocoder;
EOF

# Verify installation
sudo -u postgres psql -d falling_fruit -c "\dx"
```

For Docker:
```bash
# The docker-compose.yml uses postgis/postgis image which includes PostGIS
# If extensions are missing, recreate the container:
docker compose down -v
docker compose up -d
```

---

## Issue 6: API Slow Response / Timeouts

**Symptom:**
- Queries take 10+ seconds
- Browser shows timeout errors

**Causes and Solutions:**

**A) Missing database indexes**
```sql
-- Connect to database
sudo -u postgres psql -d falling_fruit

-- Check existing indexes
\di locations*

-- Add spatial index if missing
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_locations_latlon
ON locations USING GIST (latlon);

-- Add type index if missing
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_location_types_type_id
ON location_types (type_id);
```

**B) Instance is too small**

The `t3.micro` (1 vCPU, 1 GB RAM) can struggle with large datasets. Consider:
```bash
# Check current memory usage
free -h

# Check if swapping (bad for performance)
vmstat 1 5

# Upgrade instance type in AWS Console:
# EC2 → Stop instance → Change instance type → t3.small (2 vCPU, 2 GB)
```

**C) Large dataset in bounding box**
```bash
# Reduce the bounds or add limit parameter
curl -H "x-api-key: key" \
  "http://localhost:3300/api/0.3/locations?bounds=37.5,-122.1|37.6,-122.0&limit=100"

# Or use the clusters endpoint for zoomed-out views
curl -H "x-api-key: key" \
  "http://localhost:3300/api/0.3/clusters?zoom=10&bounds=37,-123|38,-121"
```

---

## Issue 7: API Crashes / Restarts Repeatedly

**Symptom:**
- Service shows as `active (running)` but restarts frequently
- Logs show repeated startup → crash → restart cycle

**Solution:**

```bash
# View recent restart history
sudo journalctl -u falling-fruit-api --since "1 hour ago" | grep -E "Start|Exit|Crash"

# View full error output
sudo journalctl -u falling-fruit-api -n 100 --no-pager

# Common causes:
# 1. Out of memory
free -h
dmesg | grep -i "killed process"

# 2. Missing .env variables
# Check which env var is missing in the logs
grep "Cannot read" /var/log/syslog

# 3. Wrong Node.js version
node --version  # Should be 16+
```

**Fixing OOM (Out of Memory) crashes:**
```bash
# Add swap space if not present
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

---

## Issue 8: Import Script Fails

**Symptom:**
```
Error: API request failed: 429 Too Many Requests
Error: jq: command not found
Error: psql: error: could not connect to server
```

**Solution:**

**A) Install missing dependencies**
```bash
# Install jq (JSON processor)
sudo apt install -y jq

# Verify psql is available
which psql
# If not: sudo apt install -y postgresql-client
```

**B) Rate limited by public API**
```bash
# The public Falling Fruit API has rate limits
# Add delays between requests in the import script
# Or reduce the batch size (edit import-from-api.sh BATCH_SIZE variable)
```

**C) Network issue reaching public API**
```bash
# Test connectivity to public API
curl -I "https://fallingfruit.org/api/0.3/types"

# If blocked, check security group outbound rules
# Or use a VPN/NAT gateway
```

---

## Issue 9: Cannot SSH to EC2 Instance

**Symptom:**
```
ssh: connect to host XX.XX.XX.XX port 22: Operation timed out
Permission denied (publickey)
```

**Solutions:**

**A) Operation timed out**
- Check your EC2 Security Group allows TCP port 22 from your current IP
- Your IP may have changed — update the security group rule

**B) Permission denied (publickey)**
```bash
# Make sure you're using the correct key file
ssh -i /path/to/your-key.pem ubuntu@YOUR-EC2-IP

# Check key permissions
chmod 400 your-key.pem

# Make sure you're using the ubuntu user (not root or ec2-user)
ssh -i your-key.pem ubuntu@YOUR-EC2-IP
```

**C) Recover via AWS Console**
- EC2 → Connect → EC2 Instance Connect (browser-based SSH)
- This works even if your key is lost

---

## General Debugging Commands

```bash
# Check all running processes
ps aux | grep node

# Check port bindings
sudo ss -tlnp

# Check system resources
top
htop  # if installed: sudo apt install htop

# Check disk space
df -h

# Check memory
free -h

# Recent system events
sudo dmesg | tail -50

# API service logs (last 24 hours)
sudo journalctl -u falling-fruit-api --since "24 hours ago" --no-pager

# All system errors
sudo journalctl -p err --since "1 hour ago"
```

---

## Getting More Help

1. **Check the logs first** — most issues have clear error messages in the logs
2. **Search GitHub Issues** — [Falling Fruit API issues](https://github.com/falling-fruit/falling-fruit-api/issues)
3. **Check this repository's issues** — [Self-hosted issues](https://github.com/seve-rin-g/falling-fruit-api-self-hosted/issues)
4. **Database documentation** — [PostgreSQL docs](https://www.postgresql.org/docs/) and [PostGIS docs](https://postgis.net/documentation/)
