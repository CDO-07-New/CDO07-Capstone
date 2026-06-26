################################################################################
# Layer 4 - EventBridge: Window Feeder Schedule
#
# Module-ready boundary:
# - This file owns only scheduling and invoke permission.
# - Lambda implementation details stay in layer4-lambda.tf.
################################################################################

variable "window_feeder_schedule_expression" {
  description = "EventBridge schedule expression for the Window Feeder."
  type        = string
  default     = "rate(5 minutes)"
}

variable "window_feeder_schedule_enabled" {
  description = "Enable or disable the Window Feeder schedule."
  type        = bool
  default     = true
}

variable "window_feeder_event_payload" {
  description = "Static event payload sent by EventBridge to the Window Feeder."
  type        = map(string)
  default = {
    source       = "eventbridge"
    window       = "2h"
    predict_path = "/v1/predict"
  }
}

resource "aws_cloudwatch_event_rule" "window_feeder" {
  name                = "${local.window_feeder_name}-schedule"
  description         = "Trigger Window Feeder every 5 minutes to query AMP and feed AI Engine."
  schedule_expression = var.window_feeder_schedule_expression
  state               = var.window_feeder_schedule_enabled ? "ENABLED" : "DISABLED"

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "window_feeder" {
  rule      = aws_cloudwatch_event_rule.window_feeder.name
  target_id = "window-feeder-lambda"
  arn       = aws_lambda_function.window_feeder.arn

  input = jsonencode(merge(var.window_feeder_event_payload, {
    schedule_name = aws_cloudwatch_event_rule.window_feeder.name
  }))

  retry_policy {
    maximum_event_age_in_seconds = 300
    maximum_retry_attempts       = 1
  }
}

resource "aws_lambda_permission" "allow_eventbridge_window_feeder" {
  statement_id  = "AllowExecutionFromEventBridgeWindowFeeder"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.window_feeder.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.window_feeder.arn
}

output "window_feeder_schedule_rule_name" {
  description = "EventBridge rule name for Window Feeder."
  value       = aws_cloudwatch_event_rule.window_feeder.name
}

output "window_feeder_schedule_rule_arn" {
  description = "EventBridge rule ARN for Window Feeder."
  value       = aws_cloudwatch_event_rule.window_feeder.arn
}
