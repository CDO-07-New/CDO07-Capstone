###############################################################################
# S3 Audit Log Bucket — CDO-07 AI Decision Audit Trail
#
# Design ref: 02_infra_design §2 "Storage", 03_security_design §5.2
#
# Stores AI prediction audit logs with lifecycle:
#   Standard → IA (30d) → Glacier Deep Archive (90d) → Expire (365d)
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
# 6. Lifecycle Rules (03_security_design §5.2)
#    Standard → IA (30d) → Glacier Deep Archive (90d) → Expire (365d)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id

  rule {
    id     = "audit-log-tiering"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "DEEP_ARCHIVE"
    }

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
