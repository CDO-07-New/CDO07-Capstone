output "bucket_name" {
  description = "S3 bucket name — used as BASELINE_S3_BUCKET and AUDIT_S3_BUCKET env vars"
  value       = aws_s3_bucket.baseline.bucket
}

output "bucket_arn" {
  description = "S3 bucket ARN — used to scope IAM policies for ECS task role"
  value       = aws_s3_bucket.baseline.arn
}

output "baseline_prefix" {
  description = "S3 key prefix for baseline files — used as BASELINE_S3_PREFIX env var"
  value       = var.baseline_prefix
}


