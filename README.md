# AWS Cost Intelligence Dashboard

[![Security Gate](https://github.com/jordann6/aws-cost-intelligence-dashboard/actions/workflows/security-gate.yml/badge.svg)](https://github.com/jordann6/aws-cost-intelligence-dashboard/actions/workflows/security-gate.yml)

Terraform-managed AWS cost visibility platform that ingests Cost Explorer data and LLM API spend into DynamoDB daily, runs z-score anomaly detection and 14-day linear regression forecasting across all cost sources, and surfaces results through a React frontend served via S3 and CloudFront. Four separate Lambda execution roles enforce least-privilege access at each layer.

## Deployment Status

Infrastructure is provisioned on demand and torn down after demos to keep AWS spend near zero (the FinOps way). Deploy your own copy with the Terraform instructions below.

## Architecture

![Architecture](docs/architecture.png)

| Component | Resource | Purpose |
|---|---|---|
| EventBridge Scheduler | `daily-llm-ingest` (00:30 UTC) | Triggers LLM API cost ingestion |
| EventBridge Scheduler | `daily-ingest` (01:00 UTC) | Triggers AWS Cost Explorer ingestion |
| EventBridge Scheduler | `daily-analyze` (02:00 UTC) | Triggers anomaly detection + forecast |
| Lambda LLM Ingester | `lambda-cost-dashboard-llm-ingester-{env}` | Scans LLM Gateway request log, aggregates spend by provider, writes `LLM/Openai` and `LLM/Anthropic` DAILY records |
| Lambda Ingester | `lambda-cost-dashboard-ingester-{env}` | Pulls Cost Explorer data (by service + by `TAG:Project`), RI/Savings Plans coverage, scans EC2 for waste, scans tag compliance |
| Lambda Analyzer | `lambda-cost-dashboard-analyzer-{env}` | Z-score anomaly detection, linear regression forecast across all services including LLM providers |
| Lambda API | `lambda-cost-dashboard-api-{env}` | Serves `/costs`, `/costs-by-tag`, `/coverage`, `/waste`, `/anomalies`, `/forecast`, `/tags` |
| DynamoDB | `cost-dashboard-{env}` | Single-table store (`DAILY`, `DAILY_TAG`, `COVERAGE`, `WASTE`, `ANOMALY`, `FORECAST`, `TAG_ISSUE`) |
| API Gateway | HTTP API | REST interface for the frontend |
| Budgets | `cost-dashboard-monthly-{env}` | Monthly budget, alerts at 80% actual / 100% forecast to SNS |
| SNS | `cost-dashboard-alerts-{env}` | Email alerts on anomaly detection and budget breaches |
| S3 + CloudFront | `cost-dashboard-ui-{env}-{suffix}` | React frontend with OAC |

## Features

- **LLM API cost ingestion** — scans the LLM Gateway's DynamoDB request log daily, aggregates `estimated_cost_cents` by provider (OpenAI, Anthropic), and writes `LLM/Provider` records into the same DAILY partition as AWS service costs; anomaly detection and forecasting run on LLM spend automatically
- **AWS cost ingestion** — 90-day rolling window from Cost Explorer API, grouped by service, stored daily
- **Cost allocation by owner** — a second Cost Explorer query groups the same 90-day window by the `Project` cost allocation tag, so the dashboard answers "what does each project/owner cost," not just "what does each service cost." Untagged spend surfaces as its own row
- **Z-score anomaly detection** — flags any service, including LLM providers, where spend deviates >2.5σ from its 30-day rolling baseline
- **Native Cost Anomaly Detection** — an AWS-managed `SERVICE` anomaly monitor runs alongside the custom analyzer and publishes to the same SNS topic, so detection does not depend on a single detector
- **Monthly budget** — AWS Budgets alerts at 80% of actual and 100% of forecast monthly spend
- **RI / Savings Plans coverage** — daily coverage percentages surfaced so low coverage on steady-state spend is visible
- **Waste scan** — flags unattached EBS volumes, unassociated Elastic IPs, and legacy gp2 volumes (gp3 is ~20% cheaper), each with an estimated monthly dollar cost
- **14-day linear regression forecast** — projects total daily spend across all cost sources based on observed trend
- **Tag compliance scanning** — surfaces resources missing required tags (`Environment`, `Project`, `ManagedBy`, `CostCenter`). Provider-level `default_tags` applies the canonical TitleCase tag set to every resource so nothing is created untagged
- **SNS alerts** — email notification on every anomaly detection run that finds outliers
- **Four IAM execution roles** — llm-ingester, ingester, analyzer, and API each have the minimum permissions required
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

### Account-constrained features (opt-in)

Two FinOps controls depend on account state, so they default **off** and are enabled with a variable once the account is ready:

| Variable | Default | Why it is gated |
|---|---|---|
| `enable_cost_allocation_tag_activation` | `false` | `aws_ce_cost_allocation_tag` only activates a tag key Cost Explorer has already seen in billing data. On a fresh deploy it fails with `Tag keys not found`. Enable in a second apply once the tags have propagated (up to ~24h). |
| `enable_native_anomaly_monitor` | `false` | AWS allows only one **dimensional** (`SERVICE`) anomaly monitor per account. If one already exists, creation fails with `Limit exceeded`. The custom z-score analyzer and the budget still provide detection. |

The tags themselves are always applied (provider `default_tags`), and `/costs-by-tag` still works — untagged spend surfaces under `No Project` until activation completes.

```bash
# Once the tags have propagated and if no other SERVICE monitor exists:
terraform apply -var="alert_email=you@example.com" \
  -var="enable_cost_allocation_tag_activation=true" \
  -var="enable_native_anomaly_monitor=true"
```

## Seed Data (Manual Run)

After deploy, run all three ingesters and the analyzer manually to populate DynamoDB before the scheduled jobs fire:

```bash
LLM_INGESTER=$(terraform output -raw llm_ingester_function_name)
INGESTER=$(terraform output -raw ingester_function_name)
ANALYZER=$(terraform output -raw analyzer_function_name)

# Ingest yesterday's LLM API spend from the gateway request log
aws lambda invoke --function-name "$LLM_INGESTER" --payload '{}' /tmp/llm_ingest.json
cat /tmp/llm_ingest.json

# Ingest 90 days of AWS Cost Explorer data
aws lambda invoke --function-name "$INGESTER" --payload '{}' /tmp/ingest.json
cat /tmp/ingest.json

# Run anomaly detection + forecasting across all cost sources
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
| `llm_gateway_table_name` | `llm-gateway-dev-request-log` | DynamoDB request log table name from the LLM Gateway project |

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
| `llm_ingester_function_name` | LLM Ingester Lambda name |
| `ingester_function_name` | Ingester Lambda name |
| `analyzer_function_name` | Analyzer Lambda name |

## Tech Stack

- **Terraform** `>= 1.6` · `aws ~> 5.0` · `random ~> 3.0` · `archive ~> 2.0`
- **AWS Lambda** (Python 3.12) — llm-ingester, ingester, analyzer, API; stdlib only (boto3, statistics)
- **AWS DynamoDB** — PAY_PER_REQUEST, single-table design
- **AWS API Gateway** — HTTP API with CORS
- **AWS EventBridge Scheduler** — three daily schedules (00:30, 01:00, 02:00 UTC), dedicated IAM invoke role
- **AWS SNS** — anomaly alert email subscription
- **AWS S3 + CloudFront** — React frontend with Origin Access Control
- **React** + **Vite** + **recharts** — cost trend, forecast, anomaly, and tag compliance views
- **GitHub Actions** — OIDC federated auth, two-job pipeline (terraform → frontend)
