output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "alb_arn" {
  description = "The ARN of the ALB"
  value       = module.alb.arn
}

output "alb_dns_name" {
  description = "The DNS name of the load balancer"
  value       = module.alb.dns_name
}

output "alb_http_listener_arn" {
  description = "The ARN of the ALB HTTP listener"
  value       = module.alb.listeners["http"].arn
}

output "alb_security_group_id" {
  description = "The ID of the ALB security group"
  value       = module.alb.security_group_id
}

output "alb_arn_suffix" {
  description = "The ARN suffix of the ALB — required for ALBRequestCountPerTarget autoscaling metric"
  value       = module.alb.arn_suffix
}

# --- Security Groups ---

output "lambda_security_group_id" {
  description = "Security group ID for Lambda functions — use for VPC-attached Lambdas"
  value       = aws_security_group.lambda.id
}

output "vpce_security_group_id" {
  description = "Security group ID for VPC Interface Endpoints"
  value       = aws_security_group.vpce.id
}

output "influxdb_security_group_id" {
  description = "Security group ID for Timestream InfluxDB instance — attach to db instance via module.data"
  value       = aws_security_group.influxdb.id
}
