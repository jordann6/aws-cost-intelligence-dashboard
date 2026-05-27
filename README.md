# AWS Cost Intelligence Dashboard

Terraform-managed AWS cost visibility platform that ingests Cost Explorer data into DynamoDB daily, runs z-score anomaly detection and 14-day linear regression forecasting, and surfaces results through a React frontend served via S3 and CloudFront. Three separate Lambda execution roles enforce least-privilege access at each layer.

## Live Demo

| | |
|---|---|
| **Dashboard** | https://d14t0xtekufzdr.cloudfront.net |
| **API** | https://nb43vilrub.execute-api.us-east-1.amazonaws.com |

## Architecture

![Architecture](docs/architecture.png)

| Component | Resource | Purpose |
|---|---|---|
| EventBridge Scheduler | `daily-ingest` (01:00 UTC) | Triggers cost ingestion |
| EventBridge Scheduler | `daily-analyze` (02:00 UTC) | Triggers anomaly detection + forecast |
| Lambda Ingester | `lambda-cost-dashboard-ingester-{env}` | Pulls Cost Explorer data + scans tag compliance |
| Lambda Analyzer | `lambda-cost-dashboard-analyzer-{env}` | Z-score anomaly detection, linear regression forecast |
| Lambda API | `lambda-cost-dashboard-api-{env}` | Serves `/costs`, `/anomalies`, `/forecast`, `/tags` |
| DynamoDB | `cost-dashboard-{env}` | Single-table store for all record types |
| API Gateway | HTTP API | REST interface for the frontend |
| SNS | `cost-dashboard-alerts-{env}` | Email alerts on anomaly detection |
| S3 + CloudFront | `cost-dashboard-ui-{env}-{suffix}` | React frontend with OAC |

## Features

- **Cost ingestion** — 90-day rolling window from Cost Explorer API, grouped by service, stored daily
- **Z-score anomaly detection** — flags services where spend deviates >2.5σ from their 30-day rolling baseline
- **14-day linear regression forecast** — projects total daily spend based on observed trend
- **Tag compliance scanning** — surfaces resources missing required tags (`Environment`, `Project`, `ManagedBy`)
- **SNS alerts** — email notification on every anomaly detection run that finds outliers
- **Three IAM execution roles** — ingester, analyzer, and API each have the minimum permissions required
- **React frontend** — cost trend chart, forecast chart, anomaly feed, tag compliance table; served from S3 via CloudFront with OAC (no public bucket access)
- **OIDC CI/CD** — GitHub Actions deploys Terraform then builds and syncs the frontend; no stored credentials

## Prerequisites

- AWS account with Cost Explorer enabled (AWS console → Billing → Cost Explorer → Enable)
- Existing S3 backend from the backup project (`tf-state-jordprojs`)
- Terraform >= 1.6, Node.js >= 20, AWS CLI

## Deploy

```bash
# Authenticate
aws sso login   # or export AWS_PROFILE=...

# Initialize
cd terraform
terraform init

# Plan
terraform plan -var="alert_email=you@example.com"

# Apply
terraform apply -var="alert_email=you@example.com"
```

## Seed Data (Manual Run)

After deploy, run the ingester and analyzer manually to populate DynamoDB before the scheduled jobs fire:

```bash
INGESTER=$(terraform output -raw ingester_function_name)
ANALYZER=$(terraform output -raw analyzer_function_name)

# Ingest 90 days of cost data
aws lambda invoke --function-name "$INGESTER" --payload '{}' /tmp/ingest.json
cat /tmp/ingest.json

# Run anomaly detection + forecasting
aws lambda invoke --function-name "$ANALYZER" --payload '{}' /tmp/analyze.json
cat /tmp/analyze.json
```

## Frontend (Local Dev)

```bash
cd frontend
npm install

# Point at your deployed API
VITE_API_URL=$(cd ../terraform && terraform output -raw api_url) npm run dev
```

## Variables

| Variable | Default | Description |
|---|---|---|
| `region` | `us-east-1` | AWS region |
| `environment` | `dev` | Environment tag suffix |
| `alert_email` | `""` | SNS email subscription — leave empty to disable |
| `required_tags` | `["Environment","Project","ManagedBy"]` | Tags required for compliance |

## CI/CD

GitHub Actions authenticates via OIDC. Configure these repository secrets:

| Secret | Description |
|---|---|
| `AWS_ROLE_ARN` | IAM role ARN with OIDC trust for GitHub Actions |
| `ALERT_EMAIL` | Passed to `terraform plan -var` (optional) |

Push to `main` runs Terraform then builds and deploys the frontend. Pull requests run plan only.

## Outputs

| Output | Description |
|---|---|
| `api_url` | API Gateway invoke URL |
| `cloudfront_url` | Frontend URL |
| `frontend_bucket` | S3 bucket name for static assets |
| `cloudfront_distribution_id` | CloudFront distribution ID |
| `dynamodb_table_name` | DynamoDB table name |
| `ingester_function_name` | Ingester Lambda name |
| `analyzer_function_name` | Analyzer Lambda name |

## Tech Stack

- **Terraform** `>= 1.6` · `aws ~> 5.0` · `random ~> 3.0` · `archive ~> 2.0`
- **AWS Lambda** (Python 3.12) — ingester, analyzer, API; stdlib only (boto3, statistics)
- **AWS DynamoDB** — PAY_PER_REQUEST, single-table design
- **AWS API Gateway** — HTTP API with CORS
- **AWS EventBridge Scheduler** — two daily schedules, dedicated IAM invoke role
- **AWS SNS** — anomaly alert email subscription
- **AWS S3 + CloudFront** — React frontend with Origin Access Control
- **React** + **Vite** + **recharts** — cost trend, forecast, anomaly, and tag compliance views
- **GitHub Actions** — OIDC federated auth, two-job pipeline (terraform → frontend)
