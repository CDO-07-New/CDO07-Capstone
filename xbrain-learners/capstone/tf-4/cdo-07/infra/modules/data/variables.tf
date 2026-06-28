variable "project" {
  description = "Project prefix for resource naming."
  type        = string
}

variable "environment" {
  description = "Deployment environment (sandbox, staging, prod)."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS CMK for S3 SSE-KMS encryption."
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
