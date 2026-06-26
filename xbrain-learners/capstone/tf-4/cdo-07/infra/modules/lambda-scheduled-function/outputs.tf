output "lambda_function_name" {
  description = "The name of the Lambda function."
  value       = aws_lambda_function.this.function_name
}

output "lambda_function_arn" {
  description = "The ARN of the Lambda function."
  value       = aws_lambda_function.this.arn
}

output "event_rule_name" {
  description = "The name of the EventBridge rule."
  value       = aws_cloudwatch_event_rule.schedule.name
}

output "event_rule_arn" {
  description = "The ARN of the EventBridge rule."
  value       = aws_cloudwatch_event_rule.schedule.arn
}