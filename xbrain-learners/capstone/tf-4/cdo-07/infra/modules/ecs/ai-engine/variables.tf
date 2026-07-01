variable "environment" {
  description = "Environment name (e.g., sandbox, staging, prod). Used in resource naming."
  type        = string
  default     = "capstone"
}

variable "vpc_id" {
  description = "VPC ID where target groups will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs where ECS tasks will run. Contract: subnet type = private."
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID of the ALB to allow ingress traffic. Contract: SG-to-SG reference."
  type        = string
}

variable "alb_http_listener_arn" {
  description = "ARN of the ALB HTTP listener for path-based routing rules"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the ALB (e.g., app/my-alb/xxxxx) — required for ALBRequestCountPerTarget autoscaling metric."
  type        = string
}

variable "ecr_image_uri" {
  description = "Container image URI. Placeholder until AI team delivers via ECR repo 'ai-serving'. Change this variable only."
  type        = string
  default     = "public.ecr.aws/nginx/nginx:1.26-alpine"
}

variable "aws_region" {
  description = "AWS region. Contract: us-east-1 default, engine region-agnostic."
  type        = string
  default     = "us-east-1"
}

variable "baseline_s3_bucket" {
  description = "S3 bucket name for baseline storage. Maps to BASELINE_S3_BUCKET env var."
  type        = string
}

variable "baseline_s3_prefix" {
  description = "S3 key prefix for baseline files. Maps to BASELINE_S3_PREFIX env var."
  type        = string
  default     = "baselines/"
}

variable "baseline_s3_bucket_arn" {
  description = "S3 bucket ARN for IAM policy resource scoping (least-privilege)."
  type        = string
}

variable "audit_s3_bucket_arn" {
  description = "ARN of the S3 audit log bucket for IAM policy scoping."
  type        = string
}

variable "audit_s3_bucket" {
  description = "Name of the S3 audit log bucket. Maps to AUDIT_S3_BUCKET env var."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS CMK for encrypting/decrypting data in S3 and Timestream."
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Capstone"
    Team        = "CDO-07"
  }
}
