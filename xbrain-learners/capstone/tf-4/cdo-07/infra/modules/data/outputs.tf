output "audit_bucket_name" {
  description = "Name of the S3 audit log bucket — used as AUDIT_S3_BUCKET env var."
  value       = aws_s3_bucket.audit.bucket
}

output "audit_bucket_arn" {
  description = "ARN of the S3 audit log bucket — used to scope IAM policies."
  value       = aws_s3_bucket.audit.arn
}
