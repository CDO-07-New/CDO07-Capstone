###############################################################################
# CloudWatch Log Group — Mock Services
###############################################################################

resource "aws_cloudwatch_log_group" "mock_services" {
  name              = "/ecs/${var.environment}/mock-services"
  retention_in_days = 7

  tags = var.tags
}
