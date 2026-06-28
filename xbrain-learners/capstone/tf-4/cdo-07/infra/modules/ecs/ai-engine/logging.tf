# =============================================================================
# CloudWatch Log Groups — Foresight Lens AI Engine
# =============================================================================
# Contract: Deployment Contract §Observability
#   - App Log: retention 14 days (debug/info)
# Note:     Audit log group is handled separately by another team member.
# =============================================================================

# -----------------------------------------------------------------------------
# App Logs — general application logs (debug, info, error)
# Contract: "CloudWatch Logs (retention 14 ngày) cho debug/info"
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.environment}/foresight-lens-engine"
  retention_in_days = 14

  tags = merge(var.tags, {
    Purpose = "AI Engine application logs"
  })
}
