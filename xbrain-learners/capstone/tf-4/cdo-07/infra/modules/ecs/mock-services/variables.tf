variable "environment" {
  description = "The environment name (e.g., sandbox, staging, prod)"
  type        = string
  default     = "capstone"
}

variable "vpc_id" {
  description = "The ID of the VPC where target groups will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs where ECS tasks will run"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "The security group ID of the ALB to allow ingress traffic to ECS tasks"
  type        = string
}

variable "alb_http_listener_arn" {
  description = "The ARN of the ALB HTTP listener for path-based routing rules"
  type        = string
}

variable "aws_region" {
  description = "AWS region for CloudWatch log configuration."
  type        = string
  default     = "us-east-1"
}

variable "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream. Used for IAM policy scoping."
  type        = string
}

variable "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream. Passed as env var to containers."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS CMK for encrypting Kinesis records."
  type        = string
}

variable "ecr_image_uri_payment" {
  description = "Container image URI for payment-gw. Default is placeholder nginx."
  type        = string
  default     = "public.ecr.aws/nginx/nginx:alpine"
}

variable "ecr_image_uri_ledger" {
  description = "Container image URI for ledger-svc. Default is placeholder nginx."
  type        = string
  default     = "public.ecr.aws/nginx/nginx:alpine"
}

variable "ecr_image_uri_fraud" {
  description = "Container image URI for fraud-detection. Default is placeholder nginx."
  type        = string
  default     = "public.ecr.aws/nginx/nginx:alpine"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Capstone"
    Team        = "CDO-07"
  }
}
