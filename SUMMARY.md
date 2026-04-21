# 📋 Project Summary

A complete self-hosting kit for the [Falling Fruit API](https://github.com/falling-fruit/falling-fruit-api) — deploy your own instance with full access to the foraging location database.

---

## What Problem This Solves

The public [Falling Fruit API](https://fallingfruit.org) is amazing, but:
- Requires an API key (which may take time to obtain)
- Has rate limits for production use
- Doesn't allow you to control the data

This repository gives you everything needed to **run your own copy** of the API with your own data, accessible from your own applications without any restrictions.

---

## Quick Start Options

### Option A: Docker (Local Development) — 5 Minutes

```bash
git clone https://github.com/seve-rin-g/falling-fruit-api-self-hosted.git
cd falling-fruit-api-self-hosted
git clone https://github.com/falling-fruit/falling-fruit-api.git
cp .env.example falling-fruit-api/.env
docker compose up -d
curl http://localhost:3300/api/0.3/types
```

### Option B: AWS EC2 (Production) — 30-60 Minutes

```bash
# SSH into your EC2 instance, then:
git clone https://github.com/seve-rin-g/falling-fruit-api-self-hosted.git
cd falling-fruit-api-self-hosted
sudo bash scripts/setup.sh
# Edit /etc/falling-fruit-api/.env
sudo systemctl start falling-fruit-api
```

---

## Technology Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **API** | Node.js 20, Express | REST API server |
| **Database** | PostgreSQL 14 | Data storage |
| **Geographic** | PostGIS 3 | Spatial queries (bounding box, clustering) |
| **ORM/Query** | pg-promise | Database queries |
| **Auth** | JWT (JSON Web Tokens) | User authentication |
| **Container** | Docker, Docker Compose | Containerization |
| **Process Manager** | Systemd | EC2 process management |
| **CI/CD** | GitHub Actions | Automated testing |
| **Deployment** | AWS EC2 (Ubuntu 22.04) | Cloud hosting |

---

## What's Included

### 📚 Documentation (9 files)

| File | Contents |
|------|----------|
| `README.md` | 7-step AWS EC2 setup guide |
| `DOCKER-SETUP.md` | Docker development guide |
| `QUICK-REFERENCE.md` | curl examples, JS/Python snippets |
| `INTEGRATION-GUIDE.md` | React, Python, Swift, Node.js examples |
| `TROUBLESHOOTING.md` | 9+ common issues with solutions |
| `COST-OPTIMIZATION.md` | AWS cost breakdown and savings |
| `INDEX.md` | Documentation navigation |
| `SUMMARY.md` | This file |
| `GETTING-STARTED.md` | Decision tree, verification checklist |

### ⚙️ Configuration (5 files)

| File | Purpose |
|------|---------|
| `.env.example` | Environment variables template |
| `templates/.env.production` | Production settings template |
| `templates/falling-fruit-api.service` | Systemd service definition |
| `.gitignore` | Standard Node.js/Docker ignores |
| `LICENSE` | GPL-3.0 license |

### 🐳 Docker (4 files)

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage Alpine Node.js image |
| `docker-compose.yml` | Development environment |
| `docker-compose.prod.yml` | Production-like testing |
| `.dockerignore` | Build optimization |

### 🔨 Scripts (3 files)

| File | Purpose |
|------|---------|
| `scripts/setup.sh` | Automated EC2 setup script |
| `scripts/import-from-api.sh` | Import data from public API |
| `scripts/init-db.sql` | Database schema initialization |

### 🔄 CI/CD (1 file)

| File | Purpose |
|------|---------|
| `.github/workflows/test.yml` | Automated GitHub Actions tests |

---

## API Overview

### Base URL
- Local Docker: `http://localhost:3300/api/0.3`
- AWS EC2: `http://YOUR-EC2-IP:3300/api/0.3`

### Authentication
All requests require:
```
x-api-key: your-api-key
```

### Key Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/types` | GET | All plant/tree types |
| `/types/counts` | GET | Type counts |
| `/locations` | GET | Locations (filter by bounds, types) |
| `/locations/:id` | GET | Single location |
| `/clusters` | GET | Clustered locations for map rendering |
| `/user/token` | POST | Login and get JWT |

### Bounding Box Format

```
bounds=swlat,swlng|nelat,nelng

Example (San Francisco Bay Area):
bounds=37.124,-122.519|37.884,-121.208
```

---

## Estimated Costs

| Setup | Monthly Cost | Notes |
|-------|-------------|-------|
| Local Docker | $0 | Runs on your machine |
| AWS EC2 (free tier) | $0 | For 12 months |
| AWS EC2 (after free tier) | ~$12/month | t3.micro + 30GB EBS |
| AWS EC2 t3.small | ~$20/month | Better performance |
| Oracle Cloud (always free) | $0 | 4 vCPU, 24 GB free forever |

---

## Limitations vs. Public API

| Feature | Self-Hosted | Public API |
|---------|-------------|------------|
| Rate limits | None (you control) | Yes |
| API key required | Your own key | Request from Falling Fruit |
| Full dataset | Only if you import it | Yes |
| Photo uploads | Needs S3 config | Built-in |
| Email features | Needs Postmark config | Built-in |
| reCAPTCHA | Optional | Enabled |
| Support | Community / this repo | Falling Fruit team |

---

## License

This setup guide is released under the **GPL-3.0 License**.

The Falling Fruit API source code is copyright Falling Fruit contributors.  
See [their repository](https://github.com/falling-fruit/falling-fruit-api) for their license.

---

## Contributing

Improvements welcome! Please:
1. Fork this repository
2. Create a feature branch
3. Submit a pull request

See issues for known improvements needed.
