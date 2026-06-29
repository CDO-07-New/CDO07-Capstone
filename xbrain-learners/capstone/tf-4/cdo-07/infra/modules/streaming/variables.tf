variable "project" {
  description = "Project prefix for resource naming."
  type        = string
}

variable "environment" {
  description = "Deployment environment (sandbox, staging, prod)."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS CMK for Kinesis stream encryption at rest."
  type        = string
}

variable "stream_mode" {
  description = "Kinesis stream capacity mode. ON_DEMAND or PROVISIONED."
  type        = string
  default     = "ON_DEMAND"
}

variable "retention_period_hours" {
  description = "Data retention period in hours. Design specifies 24h for replay."
  type        = number
  default     = 24
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
