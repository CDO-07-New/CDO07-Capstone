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

# S3 access — read baselines (least-privilege)
resource "aws_iam_policy" "task_s3" {
  name        = "${var.environment}-foresight-lens-s3-policy"
  description = "Allow AI Engine to read baselines from S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListBaselineBucket"
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = var.baseline_s3_bucket_arn
      },
      {
        Sid    = "ReadBaselines"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
        ]
        Resource = "${var.baseline_s3_bucket_arn}/baselines/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "task_s3" {
  role       = aws_iam_role.task.name
  policy_arn = aws_iam_policy.task_s3.arn
}
