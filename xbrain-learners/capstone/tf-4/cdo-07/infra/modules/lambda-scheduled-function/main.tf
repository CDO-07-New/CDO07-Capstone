################################################################################
# Module: lambda-scheduled-function
#
# Creates a Lambda function with an IAM role, CloudWatch Log Group, and an
# EventBridge rule to trigger it on a schedule.
################################################################################

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_iam_role" "lambda" {
  name = "${var.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.function_name}-policy"
  role   = aws_iam_role.lambda.id
  policy = var.iam_policy_document_json
}

resource "aws_lambda_function" "this" {
  function_name = var.function_name
  description   = var.function_description

  role    = aws_iam_role.lambda.arn
  runtime = var.runtime
  handler = var.handler

  filename         = var.package_path
  source_code_hash = filebase64sha256(var.package_path)

  timeout                        = var.timeout_seconds
  memory_size                    = var.memory_mb
  reserved_concurrent_executions = var.reserved_concurrency

  dynamic "vpc_config" {
    for_each = length(var.subnet_ids) > 0 && length(var.security_group_ids) > 0 ? [1] : []

    content {
      subnet_ids         = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
  }

  environment {
    variables = var.environment_variables
  }

  tags = var.tags
}

# EventBridge Schedule
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.function_name}-schedule"
  description         = "Triggers the ${var.function_name} Lambda function."
  schedule_expression = var.schedule_expression
  state               = var.schedule_enabled ? "ENABLED" : "DISABLED"

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "${var.function_name}-target"
  arn       = aws_lambda_function.this.arn

  input = jsonencode(merge(var.event_payload, {
    # Automatically add the rule name to the payload for context
    schedule_name = aws_cloudwatch_event_rule.schedule.name
  }))

  retry_policy {
    maximum_event_age_in_seconds = 300
    maximum_retry_attempts       = 1
  }
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}