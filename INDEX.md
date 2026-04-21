# 📚 Documentation Index

Welcome to the Falling Fruit API self-hosted setup guide. This index helps you find the right documentation for your needs.

---

## Quick Navigation

| I want to... | Go to |
|--------------|-------|
| Get started quickly | [GETTING-STARTED.md](GETTING-STARTED.md) |
| Run locally with Docker | [DOCKER-SETUP.md](DOCKER-SETUP.md) |
| Deploy on AWS EC2 | [README.md](README.md) |
| See API examples | [QUICK-REFERENCE.md](QUICK-REFERENCE.md) |
| Integrate into my app | [INTEGRATION-GUIDE.md](INTEGRATION-GUIDE.md) |
| Fix a problem | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| Understand AWS costs | [COST-OPTIMIZATION.md](COST-OPTIMIZATION.md) |
| Get a project overview | [SUMMARY.md](SUMMARY.md) |

---

## Documentation Files

### 🚀 Setup & Deployment

| File | Description | Audience |
|------|-------------|----------|
| [README.md](README.md) | Complete 7-step AWS EC2 setup guide | Everyone |
| [GETTING-STARTED.md](GETTING-STARTED.md) | Decision tree: Docker vs AWS, verification checklist | Beginners |
| [DOCKER-SETUP.md](DOCKER-SETUP.md) | Local Docker development with docker-compose | Developers |

### 📖 Reference

| File | Description | Audience |
|------|-------------|----------|
| [QUICK-REFERENCE.md](QUICK-REFERENCE.md) | curl examples, JS/Python snippets, common commands | All developers |
| [INTEGRATION-GUIDE.md](INTEGRATION-GUIDE.md) | React, Python, Swift, Node.js integration | App developers |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | 9+ common issues with detailed solutions | Everyone |
| [COST-OPTIMIZATION.md](COST-OPTIMIZATION.md) | AWS free tier, cost breakdown, savings strategies | AWS users |
| [SUMMARY.md](SUMMARY.md) | Project overview, tech stack, what's included | Everyone |

---

## Configuration Files

| File | Description |
|------|-------------|
| [.env.example](.env.example) | Example environment variables for local development |
| [templates/.env.production](templates/.env.production) | Production environment template |
| [templates/falling-fruit-api.service](templates/falling-fruit-api.service) | Systemd service file for EC2 |

---

## Docker Files

| File | Description |
|------|-------------|
| [Dockerfile](Dockerfile) | Multi-stage Alpine-based Node.js image |
| [docker-compose.yml](docker-compose.yml) | Development environment (API + PostgreSQL/PostGIS) |
| [docker-compose.prod.yml](docker-compose.prod.yml) | Production-like testing environment |
| [.dockerignore](.dockerignore) | Build optimization |

---

## Scripts

| File | Description |
|------|-------------|
| [scripts/setup.sh](scripts/setup.sh) | Automated EC2 setup (Node, Yarn, PostgreSQL, PostGIS, systemd) |
| [scripts/import-from-api.sh](scripts/import-from-api.sh) | Import location data from the public Falling Fruit API |
| [scripts/init-db.sql](scripts/init-db.sql) | PostgreSQL schema initialization with PostGIS |

---

## CI/CD

| File | Description |
|------|-------------|
| [.github/workflows/test.yml](.github/workflows/test.yml) | GitHub Actions automated tests |

---

## Learning Path

### If you're completely new:
1. → [SUMMARY.md](SUMMARY.md) — Understand what this is
2. → [GETTING-STARTED.md](GETTING-STARTED.md) — Choose your setup method
3. → [DOCKER-SETUP.md](DOCKER-SETUP.md) or [README.md](README.md) — Follow the setup guide
4. → [QUICK-REFERENCE.md](QUICK-REFERENCE.md) — Learn the API
5. → [INTEGRATION-GUIDE.md](INTEGRATION-GUIDE.md) — Build your app

### If you just want to run it quickly:
1. → [GETTING-STARTED.md](GETTING-STARTED.md) — 5-minute decision guide
2. → [DOCKER-SETUP.md](DOCKER-SETUP.md) — Docker quick start

### If something is broken:
1. → [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — Find your issue

### If you're worried about AWS costs:
1. → [COST-OPTIMIZATION.md](COST-OPTIMIZATION.md) — Cost breakdown

---

## External Resources

- [Falling Fruit API GitHub](https://github.com/falling-fruit/falling-fruit-api) — Source code
- [Falling Fruit Website](https://fallingfruit.org) — The main application
- [PostgreSQL Documentation](https://www.postgresql.org/docs/14/) — Database docs
- [PostGIS Documentation](https://postgis.net/documentation/) — Geographic extension
- [AWS EC2 User Guide](https://docs.aws.amazon.com/ec2/) — AWS documentation
- [Docker Documentation](https://docs.docker.com/) — Container docs
