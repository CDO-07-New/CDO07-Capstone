locals {
  name_prefix = "tf4-cdo"

  common_tags = {
    Project     = "tf4-foresight-lens"
    Owner       = "cdo-platform"
    Layer       = "layer4-event-orchestration"
    ManagedBy   = "terraform"
    ModuleReady = "true"
  }

  window_feeder = {
    name           = "${local.name_prefix}-window-feeder"
    runtime        = "python3.12"
    handler        = "app.handler"
    timeout        = 5
    memory_size    = 256
    artifact_path  = "${path.module}/artifacts/window-feeder.zip"
    log_retention  = 30
    query_window   = "2h"
    predict_path   = "/v1/predict"
    inference_flag = "/${local.name_prefix}/window-feeder/inference-enabled"
  }
}

variable "amp_workspace_id" {
  description = "Amazon Managed Prometheus workspace id used by Window Feeder."
  type        = string
}

variable "ai_engine_endpoint" {
  description = "Private AI Engine HTTP endpoint, for example http://ai-engine.service.local:8080."
  type        = string
}

variable "baseline_bucket_name" {
  description = "S3 bucket that stores model baselines."
  type        = string
}

variable "audit_bucket_name" {
  description = "S3 bucket that stores Lambda audit logs."
  type        = string
}

variable "drift_alert_topic_arn" {
  description = "SNS topic ARN used for drift alerts."
  type        = string
}

resource "aws_ssm_parameter" "window_feeder_inference_enabled" {
  name        = local.window_feeder.inference_flag
  description = "Runtime kill switch for Window Feeder inference calls."
  type        = "String"
  value       = "true"

  tags = local.common_tags

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_iam_role" "window_feeder" {
  name = "${local.window_feeder.name}-role"

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
  name = "${local.window_feeder.name}-policy"
  role = aws_iam_role.window_feeder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.window_feeder.arn}:*"
      },
      {
        Sid    = "QueryPrometheus"
        Effect = "Allow"
        Action = [
          "aps:QueryMetrics",
          "aps:GetLabels",
          "aps:GetMetricMetadata",
          "aps:GetSeries"
        ]
        Resource = "arn:aws:aps:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:workspace/${var.amp_workspace_id}"
      },
      {
        Sid    = "ReadBaselines"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.baseline_bucket_name}",
          "arn:aws:s3:::${var.baseline_bucket_name}/*"
        ]
      },
      {
        Sid    = "WriteAuditLogs"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectTagging"
        ]
        Resource = "arn:aws:s3:::${var.audit_bucket_name}/window-feeder/*"
      },
      {
        Sid    = "ReadInferenceFlag"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = aws_ssm_parameter.window_feeder_inference_enabled.arn
      },
      {
        Sid    = "PublishDriftAlert"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.drift_alert_topic_arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "window_feeder" {
  name              = "/aws/lambda/${local.window_feeder.name}"
  retention_in_days = local.window_feeder.log_retention

  tags = local.common_tags
}

resource "aws_lambda_function" "window_feeder" {
  function_name = local.window_feeder.name
  description   = "Queries a rolling AMP window, calls AI Engine, writes audit output, and emits drift alerts."
  role          = aws_iam_role.window_feeder.arn

  runtime       = local.window_feeder.runtime
  handler       = local.window_feeder.handler
  filename      = local.window_feeder.artifact_path
  architectures = ["arm64"]

  memory_size = local.window_feeder.memory_size
  timeout     = local.window_feeder.timeout

  source_code_hash = filebase64sha256(local.window_feeder.artifact_path)

  environment {
    variables = {
      AMP_WORKSPACE_ID        = var.amp_workspace_id
      QUERY_WINDOW            = local.window_feeder.query_window
      AI_ENGINE_ENDPOINT      = var.ai_engine_endpoint
      AI_ENGINE_PREDICT_PATH  = local.window_feeder.predict_path
      BASELINE_BUCKET         = var.baseline_bucket_name
      AUDIT_BUCKET            = var.audit_bucket_name
      AUDIT_PREFIX            = "window-feeder/"
      INFERENCE_ENABLED_PARAM = aws_ssm_parameter.window_feeder_inference_enabled.name
      DRIFT_ALERT_TOPIC_ARN   = var.drift_alert_topic_arn
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.window_feeder,
    aws_iam_role_policy.window_feeder
  ]

  tags = local.common_tags
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
