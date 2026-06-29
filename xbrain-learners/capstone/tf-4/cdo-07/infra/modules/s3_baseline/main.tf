# =============================================================================
# S3 Baseline Storage — Foresight Lens AI Engine
# =============================================================================
# Purpose:  Store per-service ML baselines (STL seasonal profiles).
# Contract: Deployment Contract §Storage & State, §Secrets
# Pattern:  Mirrors bootstrap/state_bucket.tf (versioning, public block, SSE-KMS,
#           bucket policy deny HTTP).
# Note:     Audit log storage is handled separately by another team member.
# =============================================================================

# -----------------------------------------------------------------------------
# 1. S3 Bucket
# -----------------------------------------------------------------------------
#checkov:skip=CKV_AWS_18:Access logging via CloudTrail data events; separate log bucket is out of capstone scope.
#checkov:skip=CKV_AWS_144:Cross-region replication out of scope for single-region capstone.
#checkov:skip=CKV2_AWS_62:Event notifications not required for baseline storage.
resource "aws_s3_bucket" "baseline" {
  bucket = "${var.environment}-foresight-lens-baselines"

  tags = merge(var.tags, {
    Name    = "${var.environment}-foresight-lens-baselines"
    Purpose = "AI baseline storage"
  })
}

# -----------------------------------------------------------------------------
# 2. Versioning — keep ≥2 baseline versions for rollback (contract spec)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "baseline" {
  bucket = aws_s3_bucket.baseline.id

  versioning_configuration {
    status = "Enabled"
  }
}

# -----------------------------------------------------------------------------
# 3. Server-Side Encryption — AWS managed key (alias/aws/s3)
#    Consistent with SNS pattern (alias/aws/sns) in sns_to_slack module.
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "baseline" {
  bucket = aws_s3_bucket.baseline.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
      # Omitting kms_master_key_id uses the AWS managed key (alias/aws/s3)
    }

    bucket_key_enabled = true # Reduce KMS API calls and cost
  }
}

# -----------------------------------------------------------------------------
# 4. Block Public Access — completely
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "baseline" {
  bucket = aws_s3_bucket.baseline.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# 5. Ownership Controls — BucketOwnerEnforced (consistent with state_bucket.tf)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_ownership_controls" "baseline" {
  bucket = aws_s3_bucket.baseline.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# -----------------------------------------------------------------------------
# 6. Lifecycle Rules
#    - Noncurrent versions: expire after 90 days (keep recent for rollback)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "baseline" {
  bucket = aws_s3_bucket.baseline.id

  rule {
    id     = "cleanup-noncurrent-versions"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# -----------------------------------------------------------------------------
# 7. Bucket Policy — deny insecure transport (HTTP)
#    Consistent with bootstrap/state_bucket.tf pattern.
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "baseline" {
  bucket = aws_s3_bucket.baseline.id
  policy = data.aws_iam_policy_document.baseline_bucket.json
}

data "aws_iam_policy_document" "baseline_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.baseline.arn,
      "${aws_s3_bucket.baseline.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}
