output "cost_circuit_breaker_budget_name" {
  description = "Monthly budget name for the cost circuit breaker."
  value       = module.cost_circuit_breaker.budget_name
}

output "cost_circuit_breaker_lambda_name" {
  description = "Lambda function that disables inference at the hard budget threshold."
  value       = module.cost_circuit_breaker.lambda_function_name
}

output "inference_enabled_parameter_name" {
  description = "SSM parameter read by the Window Feeder before AI inference."
  value       = module.cost_circuit_breaker.ssm_parameter_name
}

output "alb_dns_name" {
  description = "DNS name of the internal ALB."
  value       = module.networking.alb_dns_name
}

output "ai_predict_api_url" {
  description = "IAM-authenticated API Gateway URL for AI Engine predict route."
  value       = "${module.ai_predict_api.invoke_url}/v1/predict"
}

output "kinesis_stream_name" {
  description = "Kinesis Data Stream name for telemetry ingestion."
  value       = module.streaming.stream_name
}

output "audit_s3_bucket" {
  description = "S3 bucket for audit logs."
  value       = module.audit_s3.audit_bucket_name
}

output "sns_alert_topic_arn" {
  description = "SNS topic ARN for Slack alerts."
  value       = module.sns_to_slack.sns_topic_arn
}
