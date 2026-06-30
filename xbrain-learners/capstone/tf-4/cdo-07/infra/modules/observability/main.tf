###############################################################################
# Observability Module
# Creates Amazon Managed Grafana Workspace
###############################################################################

terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  workspace_name = "${var.project}-${var.environment}-grafana"
}

# ---------------------------------------------------------------------------
# IAM Role for Grafana Workspace
# ---------------------------------------------------------------------------
resource "aws_iam_role" "grafana" {
  name = "${local.workspace_name}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "grafana.amazonaws.com"
        }
      }
    ]
  })
  tags = var.tags
}

# Allow Grafana to read from Timestream and CloudWatch
resource "aws_iam_role_policy_attachment" "grafana_cloudwatch" {
  role       = aws_iam_role.grafana.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "grafana_timestream" {
  role       = aws_iam_role.grafana.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonTimestreamReadOnlyAccess"
}

# ---------------------------------------------------------------------------
# Amazon Managed Grafana Workspace
# ---------------------------------------------------------------------------
resource "aws_grafana_workspace" "main" {
  name                     = local.workspace_name
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana.arn

  data_sources = ["CLOUDWATCH", "TIMESTREAM"]

  tags = var.tags
}
