# 💰 AWS Cost Optimization Guide

Keep your self-hosted Falling Fruit API running at minimal cost, including completely free options using the AWS Free Tier.

---

## AWS Free Tier Overview

New AWS accounts get **12 months of free tier** benefits:

| Service | Free Tier Allowance | After Free Tier |
|---------|---------------------|-----------------|
| EC2 (t3.micro) | 750 hours/month | ~$8/month |
| EBS Storage (gp2/gp3) | 30 GB/month | ~$2.40/month |
| Data Transfer Out | 15 GB/month | $0.09/GB |
| RDS (db.t3.micro) | 750 hours/month | ~$13/month |
| RDS Storage | 20 GB/month | ~$2.30/month |
| Elastic IP (while attached) | 1 IP free | $3.65/month if unused |

**Estimated monthly cost for free tier users: $0**  
**Estimated monthly cost after free tier: $10–25/month**

---

## Architecture Options by Cost

### Option 1: Fully Free (During Free Tier)

```
EC2 t3.micro (1 vCPU, 1 GB RAM)
  └─ PostgreSQL + PostGIS (local, on the same instance)
  └─ Node.js API

Total: $0/month for 12 months
Storage: 30 GB EBS (free tier)
Data transfer: 15 GB/month free
```

**Best for**: Development, small projects, testing

**Limitations**:
- 1 GB RAM limits large datasets
- No database backups by default
- Instance stops if you terminate it

### Option 2: Cost-Effective Production

```
EC2 t3.small (2 vCPU, 2 GB RAM) ~$15/month
  └─ PostgreSQL + PostGIS (local)
  └─ Node.js API

Total: ~$15-20/month
```

**Best for**: Small to medium production workloads

### Option 3: Scalable with RDS

```
EC2 t3.micro (API only) + RDS db.t3.micro (PostgreSQL)

EC2:  ~$8/month
RDS:  ~$13/month (or free during free tier)
EBS:  ~$2.40/month

Total: ~$23/month (~$2/month during free tier)
```

**Best for**: Production with automated backups, managed database

### Option 4: Serverless (Advanced)

```
AWS Lambda + RDS Aurora Serverless v2

Lambda: ~$0-2/month (pay per request)
Aurora: ~$0.06/ACU-hour (scales to zero)

Total: ~$0-10/month depending on traffic
```

**Best for**: Intermittent/unpredictable traffic

---

## Cost Breakdown: EC2 Instance Types

| Instance | vCPU | RAM | Storage | Price/month | Recommended For |
|----------|------|-----|---------|------------|-----------------|
| t3.micro | 1 | 1 GB | EBS | FREE (12 mo) / ~$8 | Dev/testing |
| t3.small | 2 | 2 GB | EBS | ~$15 | Small production |
| t3.medium | 2 | 4 GB | EBS | ~$30 | Medium workloads |
| t3.large | 2 | 8 GB | EBS | ~$60 | Large datasets |
| t3.xlarge | 4 | 16 GB | EBS | ~$120 | High traffic |

*Prices for us-east-1 (N. Virginia), on-demand pricing. Spot instances can be 70-90% cheaper.*

---

## 10 Cost Savings Strategies

### 1. Use Reserved Instances (Save 40-60%)

After the free tier, buy a 1-year Reserved Instance:

```
t3.small On-Demand:   ~$15/month
t3.small 1-year RI:   ~$9/month (40% savings)
t3.small 3-year RI:   ~$6/month (60% savings)
```

Buy from the AWS Console: EC2 → Reserved Instances → Purchase Reserved Instances

### 2. Use Spot Instances for Non-Critical Workloads (Save 70-90%)

```bash
# Spot pricing example (varies):
t3.small On-Demand: ~$15/month
t3.small Spot:      ~$2/month

# Note: Spot instances can be terminated with 2-minute notice
# Use only if your app can handle interruptions
```

### 3. Stop Instance When Not in Use

```bash
# Stop instance (keeps data, no compute charges)
aws ec2 stop-instances --instance-ids i-YOUR-INSTANCE-ID

# Start again when needed
aws ec2 start-instances --instance-ids i-YOUR-INSTANCE-ID

# Cost: Only pay for EBS storage (~$2.40/month for 30GB)
```

**Note**: Your public IP changes when you stop/start (use Elastic IP to keep it stable)

### 4. Use gp3 Instead of gp2 Storage (20% Cheaper)

```bash
# gp2: $0.10/GB/month
# gp3: $0.08/GB/month (also better performance!)

# Change volume type in AWS Console:
# EC2 → Volumes → Select volume → Actions → Modify volume
# Change type from gp2 to gp3
```

### 5. Stay in Free Tier Data Transfer (First 15 GB Free)

- Keep responses small — use `limit` and `offset` parameters
- Implement caching in your frontend (cache types for 1+ hour)
- Use `clusters` endpoint instead of `locations` for map views

### 6. Use CloudFront CDN for Caching (Often Free)

```
CloudFront Free Tier: 1 TB data transfer + 10M requests/month

Setup:
1. Create CloudFront distribution pointing to your EC2 API
2. Cache GET requests for types (TTL: 3600s)
3. Cache location queries (TTL: 60s)

This dramatically reduces EC2 data transfer costs.
```

### 7. Schedule Auto-Shutdown for Development Instances

```bash
# Automatically stop the instance at 10 PM every day
# Create a CloudWatch Event / EventBridge rule

# Or use a cron job on the instance itself:
crontab -e
# Add: 0 22 * * * /usr/bin/aws ec2 stop-instances --instance-ids $(curl -s http://169.254.169.254/latest/meta-data/instance-id) --region us-east-1
```

### 8. Use AWS Savings Plans

Commit to a certain amount of compute usage per hour:

```
Compute Savings Plan (most flexible):
- 1-year, all upfront: save ~35%
- 3-year, all upfront: save ~55%
- Applies to EC2, Lambda, Fargate
```

### 9. Monitor and Set Billing Alerts

```bash
# Set up a billing alert in AWS Console:
# AWS Budgets → Create Budget → Cost Budget
# Alert when actual cost > $5/month
```

This prevents surprise bills if your instance gets compromised or you forget it's running.

### 10. Consider Lightsail (Simpler Pricing)

AWS Lightsail offers simpler, predictable pricing:

| Plan | RAM | Storage | Transfer | Price |
|------|-----|---------|----------|-------|
| Lightsail Micro | 1 GB | 40 GB | 2 TB | $5/month |
| Lightsail Small | 2 GB | 60 GB | 3 TB | $10/month |
| Lightsail Medium | 4 GB | 80 GB | 4 TB | $20/month |

```bash
# Lightsail vs EC2:
# Pros: Fixed monthly price, includes data transfer
# Cons: Less flexible, can't use all AWS services
```

---

## Database Cost Optimization

### Local PostgreSQL vs RDS

**Local PostgreSQL (on EC2):**
- Cost: $0 extra (uses EC2's resources)
- Backup: Manual or use pg_dump + S3
- Management: You manage updates and maintenance

**AWS RDS:**
- Cost: ~$13-25/month (or free during free tier)
- Backup: Automatic, point-in-time recovery
- Management: AWS handles updates

**Recommendation**: Start with local PostgreSQL. Switch to RDS if you need managed backups and the budget allows.

### Database Backups to S3 (Cheap Insurance)

```bash
#!/bin/bash
# backup-db.sh — Run via cron, costs ~$0.023/GB/month on S3

DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="/tmp/falling-fruit-backup-${DATE}.sql.gz"
S3_BUCKET="your-backup-bucket"

# Create backup
sudo -u postgres pg_dump falling_fruit | gzip > "$BACKUP_FILE"

# Upload to S3
aws s3 cp "$BACKUP_FILE" "s3://${S3_BUCKET}/backups/"

# Clean up local file
rm "$BACKUP_FILE"

echo "Backup complete: s3://${S3_BUCKET}/backups/falling-fruit-backup-${DATE}.sql.gz"
```

```bash
# Set up daily backups at 3 AM
crontab -e
# Add: 0 3 * * * /home/ubuntu/backup-db.sh >> /var/log/db-backup.log 2>&1
```

S3 costs: ~$0.023/GB/month. A typical Falling Fruit database backup is 100-500 MB = **$0.002-0.01/month**.

---

## Monitoring Costs with AWS Cost Explorer

1. Go to **AWS Console → Cost Explorer**
2. View cost breakdown by service
3. Set up **AWS Budgets** alerts at $5/month to catch surprises

### Key Metrics to Watch

```
EC2 Instance Hours: Should match your instance uptime
EBS: Should be ~$2.40/month for 30 GB
Data Transfer: Should be <15 GB/month to stay free
```

---

## Cost Calculator

Use the [AWS Pricing Calculator](https://calculator.aws/) to estimate your specific costs:

1. Go to `https://calculator.aws/`
2. Add EC2 service
3. Select your region and instance type
4. Add EBS storage
5. Estimate data transfer

**Example estimate (after free tier, us-east-1):**
```
EC2 t3.micro:           $8.47/month
EBS 30 GB gp3:          $2.40/month
Data Transfer (15 GB):  $0.90/month (above 15 GB free)
Elastic IP (attached):  $0.00/month
                        ──────────
Total:                  ~$12/month
```

---

## Completely Free Alternatives to AWS EC2

If the AWS cost is a concern after the free tier:

| Platform | Free Tier | PostgreSQL | Notes |
|----------|-----------|------------|-------|
| **Oracle Cloud** | Always free 2x VMs | Yes (via Docker) | t.ampere.a1 = 4 vCPU, 24 GB RAM free! |
| **Render** | 750 hrs/month | 90-day free DB | Easy deployment |
| **Railway** | $5 credit/month | Included | Simple setup |
| **Fly.io** | 3 shared VMs free | 3 GB free | Good for Docker |
| **Google Cloud** | e2-micro always free | Cloud SQL (not free) | Use Docker for DB |

**Oracle Cloud Always Free** is the best alternative — you get 2 VMs with 4 vCPUs and 24 GB RAM total, forever free.
