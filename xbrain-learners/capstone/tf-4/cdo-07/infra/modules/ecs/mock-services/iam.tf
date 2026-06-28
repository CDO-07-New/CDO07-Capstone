###############################################################################
# IAM Roles — Mock Services ECS Tasks
#
# Design ref: 03_security_design §2.1 tf4-cdo07-mock-svc-task-role
#
# Shared roles across all 3 mock services (payment-gw, ledger-svc, fraud-detection)
# since they all need the same permissions: write to Kinesis, publish metrics.
###############################################################################

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# 1. Task Execution Role — ECS agent permissions (pull image, write logs)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "mock_task_execution" {
  name = "${var.environment}-mock-svc-exec-role"

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

resource "aws_iam_role_policy_attachment" "mock_task_execution" {
  role       = aws_iam_role.mock_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------------------------------------------------------------------------
# 2. Task Role — Container runtime permissions
#    - kinesis:PutRecord/PutRecords — write telemetry
#    - cloudwatch:PutMetricData — custom metrics
#    - kms:GenerateDataKey — encrypt Kinesis records
# ---------------------------------------------------------------------------
resource "aws_iam_role" "mock_task" {
  name = "${var.environment}-mock-svc-task-role"

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

resource "aws_iam_policy" "mock_task" {
  name        = "${var.environment}-mock-svc-task-policy"
  description = "Mock services runtime: Kinesis write, CloudWatch metrics, KMS encrypt"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Kinesis: Write telemetry records
      {
        Sid    = "AllowKinesisWrite"
        Effect = "Allow"
        Action = [
          "kinesis:PutRecord",
          "kinesis:PutRecords",
        ]
        Resource = [var.kinesis_stream_arn]
      },
      # CloudWatch: Custom metrics
      {
        Sid      = "PublishCustomMetrics"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = ["*"]
      },
      # KMS: Encrypt Kinesis records at rest
      {
        Sid    = "AllowKMSEncrypt"
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:DescribeKey",
        ]
        Resource = [var.kms_key_arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "mock_task" {
  role       = aws_iam_role.mock_task.name
  policy_arn = aws_iam_policy.mock_task.arn
}
