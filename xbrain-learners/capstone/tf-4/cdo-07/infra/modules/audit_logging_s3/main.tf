# -----------------------------------------------------------------------------
# 1. Gọi dữ liệu KMS Key (CMK) đã có sẵn qua mã định danh/alias
# -----------------------------------------------------------------------------
data "aws_kms_key" "audit_cmk" {
  key_id = var.kms_key_alias
}

# -----------------------------------------------------------------------------
# 2. S3 Bucket Định Danh Chính Xác
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "audit_log" {
  bucket        = "tf4-cdo07-audit-log"
  force_destroy = false

  tags = var.default_tags
}

# -----------------------------------------------------------------------------
# 3. Kích Hoạt Versioning (Hỗ trợ Compliance & Khôi phục dữ liệu)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "audit_log" {
  bucket = aws_s3_bucket.audit_log.id
  versioning_configuration {
    status = "Enabled"
  }
}

# -----------------------------------------------------------------------------
# 4. Ép Buộc Mã Hóa Bằng Customer Managed Key (CMK)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "audit_log" {
  bucket = aws_s3_bucket.audit_log.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = data.aws_kms_key.audit_cmk.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true # Tối ưu hóa số lượng API call để giảm chi phí KMS
  }
}

# -----------------------------------------------------------------------------
# 5. Khóa Hoàn Toàn Truy Cập Công Cộng (Block Public Access)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "audit_log" {
  bucket = aws_s3_bucket.audit_log.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# 6. Ép Quyền Sở Hữu Toàn Diện (BucketOwnerEnforced)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_ownership_controls" "audit_log" {
  bucket = aws_s3_bucket.audit_log.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# -----------------------------------------------------------------------------
# 7. Lifecycle Rule: Chuyển thẳng sang Deep Archive sau 90 ngày (Không qua S3 IA)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "audit_log" {
  depends_on = [aws_s3_bucket_versioning.audit_log]
  bucket     = aws_s3_bucket.audit_log.id

  rule {
    id     = "compliance-90-days-to-deep-archive"
    status = "Enabled"

    filter {} # Áp dụng cho toàn bộ object log trong bucket

    # Dữ liệu hiện tại chuyển thẳng sang Deep Archive sau 90 ngày ở lớp Hot
    transition {
      days          = 90
      storage_class = "DEEP_ARCHIVE"
    }

    # Dữ liệu phiên bản cũ cũng chuyển thẳng sang Deep Archive sau 90 ngày
    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "DEEP_ARCHIVE"
    }

    # Tổng thời gian tuân thủ lưu giữ 1 năm (90 ngày hot + 275 ngày cold = 365 ngày hết hạn)
    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }

    # Tự động hủy các mảnh file upload dở dang sau 7 ngày để tránh rác dung lượng
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# -----------------------------------------------------------------------------
# 8. S3 Bucket Policy: Ép HTTPS & Chỉ cho phép truy cập qua S3 VPC Gateway Endpoint
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "audit_log" {
  bucket = aws_s3_bucket.audit_log.id
  policy = data.aws_iam_policy_document.audit_log_policy.json
}

data "aws_iam_policy_document" "audit_log_policy" {
  # Điều kiện 1: Đấm chặn mọi kết nối không mã hóa HTTP
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.audit_log.arn,
      "${aws_s3_bucket.audit_log.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Điều kiện 2: Chỉ cho phép các thao tác đọc/ghi đi qua con S3 VPC Gateway Endpoint của đội mình
  statement {
    sid    = "RestrictAccessToVPCendpoint"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.audit_log.arn,
      "${aws_s3_bucket.audit_log.arn}/*",
    ]

    condition {
      test     = "StringNotEquals"
      variable = "aws:sourceVpce"
      values   = [var.vpc_endpoint_id]
    }
  }
}