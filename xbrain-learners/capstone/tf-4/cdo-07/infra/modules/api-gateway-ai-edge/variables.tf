variable "project" {
  description = "Project identifier used for resource naming."
  type        = string
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the API Gateway VPC Link ENIs are created."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the API Gateway VPC Link."
  type        = list(string)
}

variable "alb_listener_arn" {
  description = "ALB listener ARN used as the HTTP API private integration target."
  type        = string
}

variable "alb_security_group_id" {
  description = "Security group ID of the ALB that receives traffic from API Gateway VPC Link."
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources."
  type        = map(string)
  default     = {}
}
