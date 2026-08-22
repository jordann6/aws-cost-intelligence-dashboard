variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment label (dev / prod)."
  type        = string
  default     = "dev"
}

variable "alert_email" {
  description = "Email address for anomaly alerts. Leave empty to disable."
  type        = string
  default     = ""
}

variable "required_tags" {
  description = "Tag keys every resource must have for compliance scanning."
  type        = list(string)
  default     = ["Environment", "Project", "ManagedBy", "CostCenter"]
}

variable "cost_center" {
  description = "Cost allocation dimension — who to bill for this spend."
  type        = string
  default     = "platform-eng"
}

variable "team" {
  description = "Owning team, second cost allocation dimension."
  type        = string
  default     = "cloud-platform"
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget; alerts fire at 80% actual and 100% forecast."
  type        = number
  default     = 50
}

variable "enable_cost_allocation_tag_activation" {
  description = <<-EOT
    Activate Project/Environment/CostCenter/Team as cost allocation tags.
    Off by default: CE only activates a tag key it has already seen in billing
    data, so a brand-new deployment fails with "Tag keys not found". Turn on in
    a second apply once the tags have propagated (up to ~24h).
  EOT
  type        = bool
  default     = false
}

variable "enable_native_anomaly_monitor" {
  description = <<-EOT
    Create an AWS-managed SERVICE anomaly monitor + subscription. Off by
    default: AWS allows only one dimensional (SERVICE) monitor per account, so
    this errors if the account already has one. The custom z-score analyzer and
    the budget still provide detection.
  EOT
  type        = bool
  default     = false
}

variable "llm_gateway_table_name" {
  description = "Name of the LLM gateway request log DynamoDB table to pull cost data from."
  type        = string
  default     = "llm-gateway-dev-request-log"
}
