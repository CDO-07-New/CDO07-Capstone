###############################################################################
# Kinesis Data Streams — CDO-07 Telemetry Ingestion
# Design ref: 02_infra_design §2 "Event Streaming"
#
# Buffer between Mock Services (producers) and Lambda Transformer (consumer).
# Partition key = service_id for multi-tenant isolation.
# 24h retention for data replay during AI model testing.
###############################################################################

terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

resource "aws_kinesis_stream" "telemetry" {
  name             = "${var.project}-${var.environment}-ingest-stream"
  retention_period = var.retention_period_hours

  stream_mode_details {
    stream_mode = var.stream_mode
  }

  # KMS encryption at rest (03_security_design §4.1)
  encryption_type = "KMS"
  kms_key_id      = var.kms_key_arn

  tags = merge(var.tags, {
    Name      = "${var.project}-${var.environment}-ingest-stream"
    Component = "streaming"
  })
}
