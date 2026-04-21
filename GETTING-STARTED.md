# 🚀 Getting Started

Use this guide to choose the right setup method and get your Falling Fruit API running as quickly as possible.

---

## Step 1: Choose Your Setup Method

```
Do you have Docker installed?
├─ YES → Go to Option A: Docker (easiest, 5 minutes)
└─ NO  →
    Do you want to deploy to the cloud?
    ├─ YES → Go to Option B: AWS EC2 (30-60 minutes)
    └─ NO  →
        Do you want to install Docker?
        ├─ YES → Install Docker first, then Option A
        └─ NO  → Go to Option C: Manual Setup
```

---

## Option A: Docker (Recommended for Development)

**Best for**: Local development, testing, learning the API

**Requirements**:
- Docker Desktop (Mac/Windows) or Docker Engine (Linux)
- 4 GB RAM available
- 10 GB disk space

### Steps

```bash
# 1. Clone this setup guide
git clone https://github.com/seve-rin-g/falling-fruit-api-self-hosted.git
cd falling-fruit-api-self-hosted

# 2. Clone the actual API source code
git clone https://github.com/falling-fruit/falling-fruit-api.git

# 3. Set up environment variables
cp .env.example falling-fruit-api/.env

# 4. Start everything
docker compose up -d

# 5. Wait 1-2 minutes for initialization, then test:
curl http://localhost:3300/api/0.3/types
```

**Expected output**: A JSON array of plant/tree types

✅ **Done!** Your API is running at `http://localhost:3300/api/0.3`

> **Next**: See [DOCKER-SETUP.md](DOCKER-SETUP.md) for loading data, advanced configuration, and development workflow.

---

## Option B: AWS EC2 (Recommended for Production)

**Best for**: Production deployment, sharing with others, always-on availability

**Requirements**:
- AWS account (free tier eligible)
- SSH client (built into Mac/Linux; use PuTTY or Windows Terminal on Windows)
- ~30-60 minutes

### Pre-flight Checklist

Before starting, make sure you have:

- [ ] AWS account created at [aws.amazon.com](https://aws.amazon.com)
- [ ] Credit card added to AWS account (required even for free tier)
- [ ] SSH key pair created (or will create during EC2 setup)
- [ ] `.pem` key file downloaded and saved somewhere safe

### Steps Overview

1. **Launch EC2 Instance** (5 min) — Ubuntu 22.04 LTS, t3.micro, 30 GB storage
2. **Configure Security Group** (2 min) — Allow SSH (22), API (3300)
3. **SSH into Instance** (2 min) — `ssh -i key.pem ubuntu@YOUR-IP`
4. **Run Setup Script** (10 min) — Installs Node.js, PostgreSQL, PostGIS
5. **Configure Environment** (3 min) — Set database URL, API key, JWT secret
6. **Initialize Database** (2 min) — Run schema creation SQL
7. **Start & Enable Service** (1 min) — systemctl start/enable
8. **Import Data** (5-30 min) — Pull locations from public API

> **Full guide**: See [README.md](README.md) for detailed step-by-step instructions.

---

## Option C: Manual Setup (Advanced)

**Best for**: When you can't use Docker or cloud platforms

**Requirements**:
- Node.js 18+ and Yarn
- PostgreSQL 14+ with PostGIS 3
- Git

```bash
# 1. Clone and install dependencies
git clone https://github.com/falling-fruit/falling-fruit-api.git
cd falling-fruit-api
yarn install

# 2. Set up PostgreSQL
createdb falling_fruit
psql falling_fruit -c "CREATE EXTENSION postgis;"

# 3. Configure environment
cp .env.example .env
nano .env  # Edit with your database URL and settings

# 4. Start the API
yarn start
# API runs on http://localhost:3300/api/0.3
```

---

## Verification Checklist

After setup, verify everything is working:

### Basic Health Checks

```bash
# 1. API is responding
curl http://localhost:3300/api/0.3/types
# Expected: JSON array of types (or empty array if no data yet)

# 2. API key authentication works
curl -H "x-api-key: YOUR_API_KEY" http://localhost:3300/api/0.3/types
# Expected: Same JSON array

# 3. Database connection is working
# (No "database connection" error in logs)
```

### Advanced Checks

```bash
# 4. PostgreSQL/PostGIS is working (enables geographic queries)
# Run this in your database:
sudo -u postgres psql -d falling_fruit -c "SELECT PostGIS_Version();"
# Expected: PostGIS version string

# 5. Location query works
curl -H "x-api-key: KEY" \
  "http://localhost:3300/api/0.3/locations?bounds=37,-122|38,-121"
# Expected: [] (empty if no data imported) or array of locations

# 6. Clusters endpoint works
curl -H "x-api-key: KEY" \
  "http://localhost:3300/api/0.3/clusters?zoom=10&bounds=37,-122|38,-121"
# Expected: Array of cluster objects
```

### ✅ All Checks Passing?

You're ready! Next steps:

1. **Import data** — Run `bash scripts/import-from-api.sh` to pull Bay Area locations
2. **Build your app** — See [INTEGRATION-GUIDE.md](INTEGRATION-GUIDE.md) for code examples
3. **Explore the API** — See [QUICK-REFERENCE.md](QUICK-REFERENCE.md) for all endpoints

---

## Common "Which option?" Questions

**Q: I'm building a React app for a class project**  
→ Use **Docker** locally, then AWS EC2 if you need to share it publicly

**Q: I want the API to always be available (24/7)**  
→ Use **AWS EC2** — your laptop can't run Docker while closed

**Q: I just want to explore the API**  
→ Use **Docker** — fastest to get running

**Q: I have a Raspberry Pi**  
→ Use **Manual Setup** or Docker (make sure to use ARM images)

**Q: I want it to be free**  
→ **Docker** locally is always free; **AWS EC2** is free for 12 months

**Q: I'm worried about security**  
→ Read [README.md](README.md#security-configuration) for security best practices

---

## What Next?

| You want to... | Read this |
|----------------|-----------|
| Deep-dive Docker setup | [DOCKER-SETUP.md](DOCKER-SETUP.md) |
| See curl / JS / Python examples | [QUICK-REFERENCE.md](QUICK-REFERENCE.md) |
| Build a React/Python/Swift app | [INTEGRATION-GUIDE.md](INTEGRATION-GUIDE.md) |
| Fix a problem | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| Understand AWS costs | [COST-OPTIMIZATION.md](COST-OPTIMIZATION.md) |
