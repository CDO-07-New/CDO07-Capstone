output "grafana_workspace_id" {
  description = "The ID of the Grafana workspace"
  value       = aws_grafana_workspace.main.id
}

output "grafana_workspace_endpoint" {
  description = "The endpoint of the Grafana workspace"
  value       = aws_grafana_workspace.main.endpoint
}
