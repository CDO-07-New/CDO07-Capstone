output "lambda_function_arn" {
  description = "ARN of the Lambda Transformer function."
  value       = aws_lambda_function.transformer.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda Transformer function."
  value       = aws_lambda_function.transformer.function_name
}

output "lambda_role_arn" {
  description = "ARN of the IAM Execution Role for the Transformer."
  value       = aws_iam_role.transformer.arn
}

output "log_group_name" {
  description = "CloudWatch Log Group for the Transformer Lambda."
  value       = aws_cloudwatch_log_group.transformer.name
}
