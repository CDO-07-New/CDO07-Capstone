output "audit_bucket_name" {
  description = "Name of the S3 audit log bucket — used as AUDIT_S3_BUCKET env var."
  value       = aws_s3_bucket.audit.bucket
}

output "audit_bucket_arn" {
  description = "ARN of the S3 audit log bucket — used to scope IAM policies."
  value       = aws_s3_bucket.audit.arn
}

# ---------------------------------------------------------------------------
# Timestream InfluxDB outputs
# ---------------------------------------------------------------------------

output "influxdb_instance_id" {
  description = "Timestream InfluxDB instance identifier."
  value       = aws_timestreaminfluxdb_db_instance.main.id
}

output "influxdb_endpoint" {
  description = "Timestream InfluxDB HTTP endpoint (without port/scheme — use SSM parameter for full URL)."
  value       = aws_timestreaminfluxdb_db_instance.main.endpoint
}

output "influxdb_endpoint_url" {
  description = "Full InfluxDB HTTP endpoint URL (https://host:8086) — pass as INFLUXDB_URL env var."
  value       = "https://${aws_timestreaminfluxdb_db_instance.main.endpoint}:8086"
}

output "influxdb_bucket" {
  description = "InfluxDB bucket name (service-metrics) — pass as INFLUXDB_BUCKET env var."
  value       = aws_timestreaminfluxdb_db_instance.main.bucket
}

output "influxdb_org" {
  description = "InfluxDB organization name — pass as INFLUXDB_ORG env var."
  value       = aws_timestreaminfluxdb_db_instance.main.organization
}

output "influxdb_secret_arn" {
  description = "Secrets Manager ARN containing InfluxDB operator token — Lambda reads token from here."
  value       = aws_timestreaminfluxdb_db_instance.main.influx_auth_parameters_secret_arn
}

output "influxdb_endpoint_ssm_name" {
  description = "SSM parameter name storing the full InfluxDB endpoint URL."
  value       = aws_ssm_parameter.influxdb_endpoint.name
}

output "influxdb_secret_arn_ssm_name" {
  description = "SSM parameter name storing the Secrets Manager ARN for InfluxDB auth."
  value       = aws_ssm_parameter.influxdb_secret_arn.name
}
