output "api_id" {
  description = "HTTP API ID."
  value       = aws_apigatewayv2_api.this.id
}

output "api_endpoint" {
  description = "Base API Gateway endpoint."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "invoke_url" {
  description = "Invoke URL for the default stage."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "execution_arn" {
  description = "Execution ARN of the HTTP API."
  value       = aws_apigatewayv2_api.this.execution_arn
}

output "predict_route_execution_arn" {
  description = "Execution ARN scoped to POST /v1/predict."
  value       = "${aws_apigatewayv2_api.this.execution_arn}/*/POST/v1/predict"
}

output "vpc_link_security_group_id" {
  description = "Security group ID attached to API Gateway VPC Link ENIs."
  value       = aws_security_group.vpc_link.id
}
