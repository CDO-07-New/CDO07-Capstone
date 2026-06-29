variable "project" {
  description = "Project prefix used for named AWS resources."
  type        = string
}

variable "environment" {
  description = "Deployment environment label."
  type        = string
}

variable "aws_region" {
  description = "AWS region for regional resources."
  type        = string
}

variable "monthly_budget_limit_usd" {
  description = "Monthly account cost budget limit in USD."
  type        = number
  default     = 200
}

variable "daily_spend_cap_usd" {
  description = "Maximum estimated daily AWS spend before the circuit breaker fires. Defaults to monthly cap / 30."
  type        = number
  default     = null
}

variable "warning_threshold_percent" {
  description = "Budget warning threshold as a percentage of the monthly limit."
  type        = number
  default     = 80
}

variable "hard_threshold_percent" {
  description = "Budget threshold that disables AI inference through the circuit breaker."
  type        = number
  default     = 100
}

variable "ssm_parameter_name" {
  description = "SSM parameter read by the Window Feeder before calling the AI engine."
  type        = string
}

variable "lambda_timeout_seconds" {
  description = "Timeout for the cost circuit breaker Lambda."
  type        = number
  default     = 10
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the cost circuit breaker Lambda."
  type        = number
  default     = 30
}

variable "warning_email_addresses" {
  description = "Optional email subscribers for the 80 percent budget warning."
  type        = list(string)
  default     = []
}

variable "kms_key_arn" {
  description = "ARN or alias ARN of the KMS CMK for encrypting SSM SecureString parameter and Lambda logs."
  type        = string
  default     = ""
}

variable "alert_sns_topic_arn" {
  description = "ARN of the SNS alert topic. Lambda publishes here when the circuit breaker trips."
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Private subnet IDs for VPC-attached Lambda. Leave empty for public Lambda."
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security group IDs for VPC-attached Lambda."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common tags to apply to taggable resources."
  type        = map(string)
  default     = {}
}
