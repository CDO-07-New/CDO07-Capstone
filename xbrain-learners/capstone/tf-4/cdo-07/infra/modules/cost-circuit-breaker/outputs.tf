output "budget_name" {
  description = "AWS Budgets monthly cost budget name."
  value       = aws_budgets_budget.monthly_cost.name
}

output "daily_budget_name" {
  description = "AWS Budgets daily cost budget name."
  value       = aws_budgets_budget.daily_cost.name
}

output "daily_spend_cap_alarm_name" {
  description = "CloudWatch alarm name for the daily spend cap guardrail."
  value       = aws_cloudwatch_metric_alarm.daily_spend_cap.alarm_name
}

output "daily_spend_cap_usd" {
  description = "Configured daily spend cap in USD."
  value       = local.daily_spend_cap_usd
}

output "lambda_function_name" {
  description = "Cost circuit breaker Lambda function name."
  value       = aws_lambda_function.cost_circuit_breaker.function_name
}

output "lambda_function_arn" {
  description = "Cost circuit breaker Lambda function ARN."
  value       = aws_lambda_function.cost_circuit_breaker.arn
}

output "ssm_parameter_name" {
  description = "SSM parameter toggled by the cost circuit breaker."
  value       = aws_ssm_parameter.inference_enabled.name
}

output "budget_warning_topic_arn" {
  description = "SNS topic used for budget warning notifications."
  value       = aws_sns_topic.budget_warning.arn
}

output "budget_hard_trigger_topic_arn" {
  description = "SNS topic that invokes the circuit breaker Lambda at the hard budget threshold."
  value       = aws_sns_topic.budget_hard_trigger.arn
}
