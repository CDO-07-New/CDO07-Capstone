###############################################################################
# Lambda Transformer — CDO-07 Kinesis → Timestream InfluxDB Bridge
#
# Design ref: 02_infra_design §2 "Functions", 03_security_design §2.1, ADR-002
#
# Reads raw telemetry from Kinesis Data Streams, validates schema,
# drops PII fields (03_security_design §1.4 PII Firewall), and writes
# clean records to Amazon Timestream for InfluxDB via HTTP Line Protocol.
#
# Auth: reads InfluxDB operator token from Secrets Manager at runtime.
###############################################################################

terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  function_name = "${var.project}-${var.environment}-transformer"
  log_group     = "/aws/lambda/${local.function_name}"
}

# ---------------------------------------------------------------------------
# 1. Package Lambda source code
# ---------------------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/transformer_handler.py"
  output_path = "${path.module}/lambda/transformer_handler.zip"
}

# ---------------------------------------------------------------------------
# 2. IAM Execution Role — least-privilege (03_security_design §2.1)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "transformer" {
  name        = "${local.function_name}-role"
  description = "Execution role for Lambda Transformer - CDO-07 TF4"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "transformer_basic_exec" {
  role       = aws_iam_role.transformer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "transformer" {
  name        = "${local.function_name}-policy"
  description = "Least-privilege policy for Lambda Transformer"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Kinesis: Read records from ingest stream
      {
        Sid    = "AllowKinesisRead"
        Effect = "Allow"
        Action = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:ListShards",
          "kinesis:ListStreams",
        ]
        Resource = [var.kinesis_stream_arn]
      },
      # Secrets Manager: Read InfluxDB operator token (replaces Timestream LiveAnalytics auth)
      # Token ARN is set by Timestream InfluxDB provisioning (aws_timestreaminfluxdb_db_instance)
      {
        Sid    = "AllowInfluxDBTokenRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
        ]
        Resource = [var.influxdb_secret_arn]
      },
      # KMS: Decrypt Kinesis records encrypted at rest
      {
        Sid    = "AllowKMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
        ]
        Resource = [var.kms_key_arn]
      },
      # VPC: ENI management for VPC-attached Lambda
      {
        Sid    = "ManageVpcNetworkInterfaces"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
        ]
        Resource = ["*"]
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "transformer_custom" {
  role       = aws_iam_role.transformer.name
  policy_arn = aws_iam_policy.transformer.arn
}

# ---------------------------------------------------------------------------
# 3. CloudWatch Log Group — 7 days retention (03_security_design §5.2)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "transformer" {
  name              = local.log_group
  retention_in_days = 7

  tags = var.tags
}

# ---------------------------------------------------------------------------
# 4. Lambda Function
# ---------------------------------------------------------------------------
#checkov:skip=CKV_AWS_116:DLQ not required — Kinesis event source has built-in retry with bisect-on-error.
#checkov:skip=CKV_AWS_50:X-Ray tracing disabled for capstone cost optimization.
#checkov:skip=CKV_AWS_272:Code signing not mandated for internal utility Lambda.
resource "aws_lambda_function" "transformer" {
  function_name    = local.function_name
  description      = "Kinesis → Timestream: validates telemetry schema, drops PII, writes clean records"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role             = aws_iam_role.transformer.arn
  handler          = "transformer_handler.handler"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      LOG_LEVEL           = var.log_level
      INFLUXDB_URL        = var.influxdb_url
      INFLUXDB_BUCKET     = var.influxdb_bucket
      INFLUXDB_ORG        = var.influxdb_org
      INFLUXDB_SECRET_ARN = var.influxdb_secret_arn
    }
  }

  dynamic "vpc_config" {
    for_each = length(var.subnet_ids) > 0 && length(var.security_group_ids) > 0 ? [1] : []

    content {
      subnet_ids         = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.transformer,
    aws_iam_role_policy_attachment.transformer_basic_exec,
    aws_iam_role_policy_attachment.transformer_custom,
  ]

  tags = var.tags
}

# ---------------------------------------------------------------------------
# 5. Kinesis Event Source Mapping — Trigger Lambda from KDS
# ---------------------------------------------------------------------------
resource "aws_lambda_event_source_mapping" "kinesis_trigger" {
  event_source_arn  = var.kinesis_stream_arn
  function_name     = aws_lambda_function.transformer.function_name
  starting_position = "LATEST"
  batch_size        = var.kinesis_batch_size

  # On error, bisect the batch and retry smaller chunks
  bisect_batch_on_function_error = true
  maximum_retry_attempts         = 3

  # Limit parallelism to control Timestream write throughput
  parallelization_factor = 1
}
