output "audit_bucket_id" {
  value       = aws_s3_bucket.audit_log.id
  description = "Tên định danh (ID) của Audit Log Bucket"
}

output "audit_bucket_arn" {
  value       = aws_s3_bucket.audit_log.arn
  description = "Amazon Resource Name (ARN) của Audit Log Bucket"
}

output "kms_key_arn_used" {
  value       = data.aws_kms_key.audit_cmk.arn
  description = "ARN của CMK được sử dụng để thực hiện mã hóa"
}