variable "environment" {
  description = "Environment name used as bucket name prefix (e.g., sandbox, staging, prod)"
  type        = string
  default     = "capstone"
}

variable "baseline_prefix" {
  description = "S3 key prefix for per-service baseline JSON files. Maps to BASELINE_S3_PREFIX env var."
  type        = string
  default     = "baselines/"
}



variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Capstone"
    Team        = "CDO-07"
  }
}
