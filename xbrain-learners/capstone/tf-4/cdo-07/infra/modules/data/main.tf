###############################################################################
# S3 Audit Log Bucket — CDO-07 AI Decision Audit Trail
#
# Design ref: 02_infra_design §2 "Storage", 03_security_design §5.2, ADR-004
#
# Stores AI prediction audit logs with lifecycle (2 stages per ADR-004):
#   Standard (0–90d) → Glacier Deep Archive (90–365d) → Expire (365d)
#
# Separate from baseline bucket per security design: audit logs require
# write-only access (no delete) and different retention policies.
###############################################################################

terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# ---------------------------------------------------------------------------
# 1. S3 Bucket
# ---------------------------------------------------------------------------
#checkov:skip=CKV_AWS_18:Access logging via CloudTrail data events; separate log bucket is out of capstone scope.
#checkov:skip=CKV_AWS_144:Cross-region replication out of scope for single-region capstone.
#checkov:skip=CKV2_AWS_62:Event notifications not required for audit log storage.
resource "aws_s3_bucket" "audit" {
  bucket = "${var.project}-${var.environment}-audit-log"

  tags = merge(var.tags, {
    Name      = "${var.project}-${var.environment}-audit-log"
    Component = "audit-storage"
    Purpose   = "AI prediction audit trail"
  })
}

# ---------------------------------------------------------------------------
# 2. Versioning — immutable audit trail
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "audit" {
  bucket = aws_s3_bucket.audit.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ---------------------------------------------------------------------------
# 3. Server-Side Encryption — KMS CMK (03_security_design §4.1)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }

    bucket_key_enabled = true
  }
}

# ---------------------------------------------------------------------------
# 4. Block Public Access
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "audit" {
  bucket = aws_s3_bucket.audit.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# 5. Ownership Controls
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_ownership_controls" "audit" {
  bucket = aws_s3_bucket.audit.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ---------------------------------------------------------------------------
# 6. Lifecycle Rules (03_security_design §5.2, ADR-004)
#    2-stage policy:
#      Stage 1: S3 Standard  (0–90d)   — hot tier, SRE Athena queries
#      Stage 2: Glacier Deep Archive (90–365d) — cold compliance tier
#      Expire after 365d
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id

  rule {
    id     = "audit-log-tiering"
    status = "Enabled"

    filter {
      prefix = ""
    }

    # Stage 2: Move to Glacier Deep Archive after 90 days
    transition {
      days          = 90
      storage_class = "DEEP_ARCHIVE"
    }

    # Expire after 1 year (compliance retention limit)
    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ---------------------------------------------------------------------------
# 7. Bucket Policy — deny insecure transport
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "audit" {
  bucket = aws_s3_bucket.audit.id
  policy = data.aws_iam_policy_document.audit_bucket.json
}

data "aws_iam_policy_document" "audit_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.audit.arn,
      "${aws_s3_bucket.audit.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

###############################################################################
# Timestream for InfluxDB — Managed Time-Series Database
#
# Design ref: 02_infra_design §2 "Database", ADR-002
#
# Replaces the original Timestream for LiveAnalytics plan after discovering
# the shared AWS account has AccessDeniedException on `timestream-write` API.
# Timestream for InfluxDB is available in this account (list-db-instances OK).
#
# Architecture:
#   Lambda Transformer writes via InfluxDB HTTP Line Protocol (port 8086)
#   Lambda Window Feeder reads via Flux query API (port 8086)
#   Amazon Managed Grafana connects via native InfluxDB datasource plugin
#
# Network: Single-AZ, VPC-only, no public access (03_security_design §1.3)
###############################################################################

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  influxdb_name = "${var.project}-${var.environment}-influxdb"
}

# Auto-generate a strong password if not provided via variable
# InfluxDB password constraint: alphanumeric only ^[a-zA-Z0-9]+$
resource "random_password" "influxdb" {
  length  = 20
  special = false
  upper   = true
  lower   = true
  numeric = true
}

# ---------------------------------------------------------------------------
# Timestream InfluxDB Instance
# Single-AZ for capstone (cost optimization — design doc §3.3 trade-off)
# ---------------------------------------------------------------------------
#checkov:skip=CKV_AWS_354:Multi-AZ not required for capstone Single-AZ design (02_infra_design §2).
resource "aws_timestreaminfluxdb_db_instance" "main" {
  name                = local.influxdb_name
  db_instance_type    = var.influxdb_db_instance_type
  allocated_storage   = var.influxdb_allocated_storage
  username            = var.influxdb_username
  password            = var.influxdb_password != null ? var.influxdb_password : random_password.influxdb.result
  bucket              = var.influxdb_bucket
  organization        = var.influxdb_org
  publicly_accessible = var.influxdb_publicly_accessible

  # VPC placement — must be in private subnets (03_security_design §1.3)
  vpc_subnet_ids         = var.influxdb_subnet_ids
  vpc_security_group_ids = var.influxdb_vpc_security_group_ids

  tags = merge(var.tags, {
    Name      = local.influxdb_name
    Component = "timestream-influxdb"
    Purpose   = "time-series metrics storage"
  })
}

# ---------------------------------------------------------------------------
# Store InfluxDB endpoint URL in SSM for Lambda consumption
# (avoids hardcoding endpoint — follows 03_security_design §3.1 pattern)
# ---------------------------------------------------------------------------
resource "aws_ssm_parameter" "influxdb_endpoint" {
  name        = "/${var.project}/${var.environment}/influxdb-endpoint"
  type        = "String"
  value       = "https://${aws_timestreaminfluxdb_db_instance.main.endpoint}:8086"
  description = "Timestream InfluxDB HTTP endpoint for Lambda Transformer and Window Feeder"

  tags = var.tags
}

# Store the InfluxDB bucket name for Lambda env vars
resource "aws_ssm_parameter" "influxdb_bucket" {
  name        = "/${var.project}/${var.environment}/influxdb-bucket"
  type        = "String"
  value       = var.influxdb_bucket
  description = "InfluxDB bucket name (logical table) — service-metrics"

  tags = var.tags
}

# Store the InfluxDB org for Lambda env vars
resource "aws_ssm_parameter" "influxdb_org" {
  name        = "/${var.project}/${var.environment}/influxdb-org"
  type        = "String"
  value       = var.influxdb_org
  description = "InfluxDB organization name"

  tags = var.tags
}

# ---------------------------------------------------------------------------
# NOTE: InfluxDB admin password and operator token are returned as sensitive
# outputs from aws_timestreaminfluxdb_db_instance (influxAuthParametersSecretArn).
# They are stored in Secrets Manager automatically by AWS — we read the ARN
# from the resource and store it in SSM for Lambda to discover.
# ---------------------------------------------------------------------------
resource "aws_ssm_parameter" "influxdb_secret_arn" {
  name        = "/${var.project}/${var.environment}/influxdb-secret-arn"
  type        = "String"
  value       = aws_timestreaminfluxdb_db_instance.main.influx_auth_parameters_secret_arn
  description = "Secrets Manager ARN containing InfluxDB operator token — used by Lambdas to get write/read token"

  tags = var.tags
}
