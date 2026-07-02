# =============================================================================
# IAM Roles — AI Engine ECS Tasks
# =============================================================================
# Two roles following AWS ECS best practice:
#   1. Task Execution Role — used by ECS agent to pull image, write logs
#   2. Task Role           — used by container at runtime for S3 baseline read
#
# All policies follow least-privilege principle with resource-scoped ARNs.
# =============================================================================

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# =============================================================================
# 1. Task Execution Role — ECS agent permissions
# =============================================================================
resource "aws_iam_role" "task_execution" {
  name = "${var.environment}-foresight-lens-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# Attach AWS managed policy for standard ECS task execution
resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# =============================================================================
# 2. Task Role — Container runtime permissions
# =============================================================================
resource "aws_iam_role" "task" {
  name = "${var.environment}-foresight-lens-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# S3 + CloudWatch + KMS access — 03_security_design §2.1 tf4-cdo07-ai-engine-task-role
resource "aws_iam_policy" "task" {
  name        = "${var.environment}-foresight-lens-task-policy"
  description = "AI Engine runtime: S3 read/write, CloudWatch metrics, KMS decrypt"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3: Read baselines
      {
        Sid      = "ListBaselineBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [var.baseline_s3_bucket_arn]
      },
      {
        Sid      = "ReadBaselines"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${var.baseline_s3_bucket_arn}/baselines/*"]
      },
      # S3: Write audit logs (03_security_design §5.2)
      {
        Sid      = "WriteAuditLogs"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${var.audit_s3_bucket_arn}/audit/*"]
      },
      # CloudWatch: Custom metrics (02_infra_design §6)
      {
        Sid      = "PublishCustomMetrics"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = ["*"]
      },
      # KMS: Decrypt baseline data + encrypt audit data
      {
        Sid    = "KMSOperations"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
        ]
        Resource = [var.kms_key_arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "task" {
  role       = aws_iam_role.task.name
  policy_arn = aws_iam_policy.task.arn
}
