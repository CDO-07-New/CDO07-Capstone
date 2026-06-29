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

# ---------------------------------------------------------------------------
# Timestream for InfluxDB — instance configuration
# ---------------------------------------------------------------------------

variable "influxdb_subnet_ids" {
  description = "Private subnet IDs for Timestream InfluxDB instance (requires ≥2 AZs for Multi-AZ, 1 for Single-AZ)."
  type        = list(string)
  default     = []
}

variable "influxdb_vpc_security_group_ids" {
  description = "Security group IDs to attach to the Timestream InfluxDB instance."
  type        = list(string)
  default     = []
}

variable "influxdb_db_instance_type" {
  description = "Instance type for Timestream InfluxDB. db.influx.medium is the minimum for capstone."
  type        = string
  default     = "db.influx.medium"
}

variable "influxdb_allocated_storage" {
  description = "Allocated storage in GiB for Timestream InfluxDB magnetic store."
  type        = number
  default     = 20 # Minimum; design doc specifies 300GB for prod but 20GB is sufficient for capstone
}

variable "influxdb_username" {
  description = "Admin username for Timestream InfluxDB (stored in SSM after creation)."
  type        = string
  default     = "admin"
}

variable "influxdb_password" {
  description = "Admin password for Timestream InfluxDB. Min 8 chars, must include uppercase, lowercase, number, symbol."
  type        = string
  sensitive   = true
  default     = null
}

variable "influxdb_bucket" {
  description = "Initial InfluxDB bucket name — matches the logical table name in the design."
  type        = string
  default     = "service-metrics"
}

variable "influxdb_org" {
  description = "InfluxDB organization name."
  type        = string
  default     = "cdo-07"
}

variable "influxdb_publicly_accessible" {
  description = "Whether the InfluxDB instance is publicly accessible. Must be false for VPC-only deployments."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
