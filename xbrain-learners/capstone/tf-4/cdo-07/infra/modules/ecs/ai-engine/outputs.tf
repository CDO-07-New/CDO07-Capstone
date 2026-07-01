output "cluster_arn" {
  description = "ARN of the AI Engine ECS cluster (tf-4-aiops-cluster)"
  value       = module.ecs_cluster.cluster_arn
}

output "service_id" {
  description = "ID of the Foresight Lens Engine ECS service"
  value       = module.ai_engine_service.id
}

output "service_name" {
  description = "Name of the ECS service — used in deployment scripts"
  value       = module.ai_engine_service.name
}

output "task_execution_role_arn" {
  description = "ARN of the task execution IAM role — used in CI/CD pipeline"
  value       = aws_iam_role.task_execution.arn
}

output "task_role_arn" {
  description = "ARN of the task IAM role — used for IAM audit"
  value       = aws_iam_role.task.arn
}

output "security_group_id" {
  description = "Security group ID of the AI Engine tasks — used for SG-to-SG references"
  value       = module.ai_engine_service.security_group_id
}

output "target_group_arn" {
  description = "ARN of the AI Engine ALB target group — used for health check monitoring"
  value       = aws_lb_target_group.ai_engine.arn
}

output "green_target_group_arn" {
  description = "ARN of the AI Engine green ALB target group used by CodeDeploy blue/green deployments."
  value       = aws_lb_target_group.ai_engine_green.arn
}

output "codedeploy_app_name" {
  description = "Name of the CodeDeploy ECS application for AI Engine blue/green deployments."
  value       = aws_codedeploy_app.ai_engine.name
}

output "codedeploy_deployment_group_name" {
  description = "Name of the CodeDeploy ECS deployment group for AI Engine blue/green deployments."
  value       = aws_codedeploy_deployment_group.ai_engine.deployment_group_name
}
