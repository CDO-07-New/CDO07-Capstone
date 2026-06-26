locals {
  window_feeder_schedule = {
    name                = "${local.name_prefix}-window-feeder-5m"
    description         = "Trigger Window Feeder every 5 minutes."
    schedule_expression = "rate(5 minutes)"
    max_event_age       = 300
    retry_attempts      = 1
  }
}

resource "aws_sqs_queue" "window_feeder_dlq" {
  name                      = "${local.window_feeder.name}-dlq"
  message_retention_seconds = 1209600

  tags = local.common_tags
}

resource "aws_sqs_queue_policy" "window_feeder_dlq" {
  queue_url = aws_sqs_queue.window_feeder_dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgeSendMessage"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.window_feeder_dlq.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.window_feeder.arn
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "window_feeder" {
  name                = local.window_feeder_schedule.name
  description         = local.window_feeder_schedule.description
  schedule_expression = local.window_feeder_schedule.schedule_expression

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "window_feeder" {
  rule      = aws_cloudwatch_event_rule.window_feeder.name
  target_id = "lambda-window-feeder"
  arn       = aws_lambda_function.window_feeder.arn

  input = jsonencode({
    source       = "eventbridge.schedule"
    service      = "window-feeder"
    query_window = local.window_feeder.query_window
    timeout_s    = local.window_feeder.timeout
  })

  retry_policy {
    maximum_event_age_in_seconds = local.window_feeder_schedule.max_event_age
    maximum_retry_attempts       = local.window_feeder_schedule.retry_attempts
  }

  dead_letter_config {
    arn = aws_sqs_queue.window_feeder_dlq.arn
  }
}

resource "aws_lambda_permission" "allow_eventbridge_window_feeder" {
  statement_id  = "AllowExecutionFromEventBridgeWindowFeeder"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.window_feeder.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.window_feeder.arn
}
