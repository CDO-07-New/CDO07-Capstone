################################################################################
# Layer 4 - Lambda: Window Feeder
#
# Module-ready boundary:
# - Inputs are expressed as variables.
# - Resource names are derived from local.name_prefix.
# - IAM is scoped to the services the feeder touches in the architecture.
################################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  project_name = "tf4-foresight-lens"
  environment  = "dev"

  name_prefix = "${local.project_name}-${local.environment}"

  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
    Layer       = "layer4-event-driven-orchestration"
  }

  window_feeder_name = "${local.name_prefix}-window-feeder"
}

variable "window_feeder_package_path" {
  description = "Path to the pre-built Lambda deployment zip for Window Feeder."
  type        = string
  default     = "build/window-feeder.zip"
}

variable "window_feeder_handler" {
  description = "Lambda handler for Window Feeder."
  type        = string
  default     = "app.handler"
}

variable "window_feeder_runtime" {
  description = "Lambda runtime for Window Feeder."
  type        = string
  default     = "python3.12"
}

variable "window_feeder_timeout_seconds" {
  description = "Lambda timeout. Keep below ALB /v1/predict timeout budget."
  type        = number
  default     = 5
}

variable "window_feeder_memory_mb" {
  description = "Lambda memory size."
  type        = number
  default     = 256
}

variable "window_feeder_reserved_concurrency" {
  description = "Reserved concurrency to avoid overlapping feeder runs."
  type        = number
  default     = 1
}

variable "window_feeder_subnet_ids" {
  description = "Private subnet IDs for Lambda when calling an internal ALB. Leave empty for public AWS API-only mode."
  type        = list(string)
  default     = []
}

variable "window_feeder_security_group_ids" {
  description = "Security group IDs for Lambda ENIs when VPC mode is enabled."
  type        = list(string)
  default     = []
}

variable "amp_workspace_id" {
  description = "Amazon Managed Prometheus workspace ID used as the metrics source."
  type        = string
}

variable "ai_engine_predict_url" {
  description = "Internal ALB endpoint for AI Engine prediction, for example http://internal-alb/v1/predict."
  type        = string
}

variable "baseline_s3_bucket_name" {
  description = "S3 bucket that stores model baselines read by the feeder or AI path."
  type        = string
}

variable "audit_s3_bucket_name" {
  description = "S3 bucket where Window Feeder writes audit payloads."
  type        = string
}

variable "audit_s3_prefix" {
  description = "S3 prefix for Window Feeder audit objects."
  type        = string
  default     = "window-feeder/"
}

variable "inference_enabled_parameter_name" {
  description = "SSM parameter used as the operational gate for inference."
  type        = string
  default     = "/tf4/foresight-lens/dev/inference-enabled"
}

variable "drift_alert_sns_topic_arn" {
  description = "SNS topic ARN used for drift and feeder failure alerts."
  type        = string
}

resource "aws_cloudwatch_log_group" "window_feeder" {
  name              = "/aws/lambda/${local.window_feeder_name}"
  retention_in_days = 30

  tags = local.common_tags
}

resource "aws_iam_role" "window_feeder" {
  name = "${local.window_feeder_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "window_feeder" {
  name = "${local.window_feeder_name}-policy"
  role = aws_iam_role.window_feeder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteLambdaLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.window_feeder.arn}:*"
      },
      {
        Sid    = "QueryPrometheusWindow"
        Effect = "Allow"
        Action = [
          "aps:GetLabels",
          "aps:GetMetricMetadata",
          "aps:GetSeries",
          "aps:QueryMetrics"
        ]
        Resource = "arn:aws:aps:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:workspace/${var.amp_workspace_id}"
      },
      {
        Sid    = "ReadInferenceGate"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${var.inference_enabled_parameter_name}"
      },
      {
        Sid    = "ReadBaselines"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.baseline_s3_bucket_name}",
          "arn:aws:s3:::${var.baseline_s3_bucket_name}/*"
        ]
      },
      {
        Sid    = "WriteAuditObjects"
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::${var.audit_s3_bucket_name}/${var.audit_s3_prefix}*"
      },
      {
        Sid    = "PublishDriftAlerts"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.drift_alert_sns_topic_arn
      },
      {
        Sid    = "ManageVpcNetworkInterfaces"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSubnets",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "window_feeder" {
  function_name = local.window_feeder_name
  description   = "Queries AMP over a rolling window, feeds AI Engine, writes audit, and emits drift alerts."

  role    = aws_iam_role.window_feeder.arn
  runtime = var.window_feeder_runtime
  handler = var.window_feeder_handler

  filename         = var.window_feeder_package_path
  source_code_hash = try(filebase64sha256(var.window_feeder_package_path), null)

  timeout                        = var.window_feeder_timeout_seconds
  memory_size                    = var.window_feeder_memory_mb
  reserved_concurrent_executions = var.window_feeder_reserved_concurrency

  dynamic "vpc_config" {
    for_each = length(var.window_feeder_subnet_ids) > 0 && length(var.window_feeder_security_group_ids) > 0 ? [1] : []

    content {
      subnet_ids         = var.window_feeder_subnet_ids
      security_group_ids = var.window_feeder_security_group_ids
    }
  }

  environment {
    variables = {
      AMP_WORKSPACE_ID                 = var.amp_workspace_id
      AMP_QUERY_WINDOW                 = "2h"
      AI_ENGINE_PREDICT_URL            = var.ai_engine_predict_url
      AI_ENGINE_TIMEOUT_SECONDS        = tostring(var.window_feeder_timeout_seconds)
      BASELINE_S3_BUCKET               = var.baseline_s3_bucket_name
      AUDIT_S3_BUCKET                  = var.audit_s3_bucket_name
      AUDIT_S3_PREFIX                  = var.audit_s3_prefix
      INFERENCE_ENABLED_PARAMETER_NAME = var.inference_enabled_parameter_name
      DRIFT_ALERT_SNS_TOPIC_ARN        = var.drift_alert_sns_topic_arn
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.window_feeder,
    aws_iam_role_policy.window_feeder
  ]

  tags = local.common_tags
}

output "window_feeder_lambda_name" {
  description = "Window Feeder Lambda function name."
  value       = aws_lambda_function.window_feeder.function_name
}

output "window_feeder_lambda_arn" {
  description = "Window Feeder Lambda function ARN."
  value       = aws_lambda_function.window_feeder.arn
}
