variable "project" {
  description = "Project prefix for resource naming."
  type        = string
  default     = "tf4-cdo07"
}

variable "environment" {
  description = "Deployment environment (sandbox, staging, prod)."
  type        = string
}

variable "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream to consume events from."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS CMK for decrypting Kinesis records."
  type        = string
}

# ---------------------------------------------------------------------------
# InfluxDB connection variables (replaces Timestream LiveAnalytics vars)
# ---------------------------------------------------------------------------

variable "influxdb_url" {
  description = "Full HTTPS URL for Timestream InfluxDB instance, e.g. https://<host>:8086"
  type        = string
}

variable "influxdb_secret_arn" {
  description = "Secrets Manager ARN containing InfluxDB operator token (key: operator_token)."
  type        = string
}

variable "influxdb_bucket" {
  description = "InfluxDB bucket name to write records into (service-metrics)."
  type        = string
  default     = "service-metrics"
}

variable "influxdb_org" {
  description = "InfluxDB organization name."
  type        = string
  default     = "cdo-07"
}

# ---------------------------------------------------------------------------
# Legacy variables kept for backward-compatibility — no longer used in code
# but may be referenced by existing environment main.tf calls.
# Will be removed in a future cleanup pass.
# ---------------------------------------------------------------------------

variable "timestream_database_name" {
  description = "DEPRECATED — was Timestream LiveAnalytics DB name. Kept for tf compat. Use influxdb_bucket."
  type        = string
  default     = ""
}

variable "timestream_table_name" {
  description = "DEPRECATED — was Timestream LiveAnalytics table name. Kept for tf compat. Use influxdb_bucket."
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Private subnet IDs for Lambda VPC configuration."
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security group IDs for Lambda ENIs when VPC mode is enabled."
  type        = list(string)
  default     = []
}

variable "kinesis_batch_size" {
  description = "Maximum number of Kinesis records per Lambda invocation."
  type        = number
  default     = 100
}

variable "log_level" {
  description = "Log level for the Lambda function (DEBUG, INFO, WARNING, ERROR)."
  type        = string
  default     = "INFO"
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
