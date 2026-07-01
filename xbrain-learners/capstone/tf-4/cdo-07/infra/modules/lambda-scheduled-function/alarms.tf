###############################################################################
# CloudWatch Alarms for Scheduled Lambda (Window Feeder)
###############################################################################

# 1. Window Feeder Errors (Fail-Open Fallback Trigger)
resource "aws_cloudwatch_metric_alarm" "feeder_errors" {
  alarm_name          = "${var.function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Window Feeder gap loi (vi du 503 Timeout tu AI Engine). Canh bao Engine down, khoi dong Fail-open Rule-based alert."
  alarm_actions       = var.alert_sns_topic_arn != "" ? [var.alert_sns_topic_arn] : []
  ok_actions          = var.alert_sns_topic_arn != "" ? [var.alert_sns_topic_arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.this.function_name
  }

  tags = var.tags
}
