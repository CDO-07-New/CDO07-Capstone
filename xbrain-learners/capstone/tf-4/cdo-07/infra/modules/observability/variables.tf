variable "project" {
  type        = string
  description = "Project name"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
}

variable "tags" {
  type        = map(string)
  description = "Common tags for resources"
  default     = {}
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of private subnet IDs for Grafana VPC configuration"
}

variable "security_group_ids" {
  type        = list(string)
  description = "List of security group IDs for Grafana VPC configuration"
}
