variable "function_name" {
  description = "The name of the Lambda function."
  type        = string
}

variable "function_description" {
  description = "A description for the Lambda function."
  type        = string
  default     = null
}

variable "package_path" {
  description = "Path to the pre-built Lambda deployment zip."
  type        = string
}

variable "handler" {
  description = "Lambda handler."
  type        = string
}

variable "runtime" {
  description = "Lambda runtime."
  type        = string
}

variable "timeout_seconds" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 5
}

variable "memory_mb" {
  description = "Lambda memory size in MB."
  type        = number
  default     = 256
}

variable "reserved_concurrency" {
  description = "Reserved concurrency for the Lambda function."
  type        = number
  default     = -1 # -1 means unreserved
}

variable "environment_variables" {
  description = "A map of environment variables for the Lambda function."
  type        = map(string)
  default     = {}
}

variable "iam_policy_document_json" {
  description = "A JSON-encoded IAM policy document to attach to the Lambda's execution role."
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs for Lambda VPC configuration."
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "List of security group IDs for Lambda VPC configuration."
  type        = list(string)
  default     = []
}

variable "schedule_expression" {
  description = "EventBridge schedule expression (e.g., 'rate(5 minutes)' or a cron expression)."
  type        = string
}

variable "schedule_enabled" {
  description = "Enable or disable the EventBridge schedule."
  type        = bool
  default     = true
}

variable "event_payload" {
  description = "A map representing the static JSON payload to send to the Lambda function."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "Specifies the number of days you want to retain log events in the specified log group."
  type        = number
  default     = 30
}

variable "tags" {
  description = "A map of tags to assign to all resources."
  type        = map(string)
  default     = {}
}