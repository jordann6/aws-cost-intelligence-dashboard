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
  default     = ["Environment", "Project", "ManagedBy"]
}

variable "llm_gateway_table_name" {
  description = "Name of the LLM gateway request log DynamoDB table to pull cost data from."
  type        = string
  default     = "llm-gateway-dev-request-log"
}
