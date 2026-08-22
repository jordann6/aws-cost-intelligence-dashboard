# =============================================================================
# FinOps controls: cost allocation tag activation, native anomaly detection,
# and a monthly budget. These complement the custom z-score analyzer with
# AWS-managed signals so the dashboard does not depend on a single detector.
# =============================================================================

# --- Cost allocation tag activation ------------------------------------------
# User-defined tags do NOT appear in Cost Explorer GROUP BY until activated.
# Without this, tags exist on resources but cannot slice spend by owner.
# NOTE: activation is account-wide and can take up to 24h to backfill; only
# tag keys already present on at least one resource can be activated.

resource "aws_ce_cost_allocation_tag" "project" {
  count   = var.enable_cost_allocation_tag_activation ? 1 : 0
  tag_key = "Project"
  status  = "Active"
}

resource "aws_ce_cost_allocation_tag" "environment" {
  count   = var.enable_cost_allocation_tag_activation ? 1 : 0
  tag_key = "Environment"
  status  = "Active"
}

resource "aws_ce_cost_allocation_tag" "cost_center" {
  count   = var.enable_cost_allocation_tag_activation ? 1 : 0
  tag_key = "CostCenter"
  status  = "Active"
}

resource "aws_ce_cost_allocation_tag" "team" {
  count   = var.enable_cost_allocation_tag_activation ? 1 : 0
  tag_key = "Team"
  status  = "Active"
}

# --- Native Cost Anomaly Detection -------------------------------------------
# Managed, free service. Runs alongside the custom analyzer as a second signal.

resource "aws_ce_anomaly_monitor" "services" {
  count             = var.enable_native_anomaly_monitor ? 1 : 0
  name              = "${local.project}-service-monitor-${local.environment}"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
  tags              = local.common_tags
}

resource "aws_ce_anomaly_subscription" "alerts" {
  count            = var.enable_native_anomaly_monitor ? 1 : 0
  name             = "${local.project}-anomaly-sub-${local.environment}"
  frequency        = "DAILY"
  monitor_arn_list = [aws_ce_anomaly_monitor.services[0].arn]

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.alerts.arn
  }

  # Only alert on anomalies with total impact above this USD threshold.
  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = ["10"]
    }
  }

  tags = local.common_tags

  # Cost Anomaly Detection publishes to SNS as a service principal.
  depends_on = [aws_sns_topic_policy.cost_anomaly]
}

# SNS topic must allow both Cost Anomaly Detection and Budgets to publish.
data "aws_iam_policy_document" "sns_cost_anomaly" {
  statement {
    sid     = "AllowCostServicesPublish"
    actions = ["SNS:Publish"]
    principals {
      type        = "Service"
      identifiers = ["costalerts.amazonaws.com", "budgets.amazonaws.com"]
    }
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_sns_topic_policy" "cost_anomaly" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.sns_cost_anomaly.json
}

# --- Monthly budget ----------------------------------------------------------
# Alerts at 80% of actual spend and 100% of forecast spend.

resource "aws_budgets_budget" "monthly" {
  name         = "${local.project}-monthly-${local.environment}"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }

  # Budgets validates it can publish to the topic at create time.
  depends_on = [aws_sns_topic_policy.cost_anomaly]
}
