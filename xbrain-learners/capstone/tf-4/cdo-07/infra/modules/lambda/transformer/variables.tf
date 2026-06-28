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

variable "timestream_database_name" {
  description = "Amazon Timestream database name for writing validated records."
  type        = string
}

variable "timestream_table_name" {
  description = "Amazon Timestream table name for writing validated records."
  type        = string
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
