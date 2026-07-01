###############################################################################
# CloudWatch Alarms for Lambda Transformer
###############################################################################

# 1. Lambda Transformer Errors
resource "aws_cloudwatch_metric_alarm" "transformer_errors" {
  alarm_name          = "${var.project}-${var.environment}-transformer-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Lambda Transformer Error Rate > 0. Canh bao dut gay pipeline tien xu ly."
  alarm_actions       = var.alert_sns_topic_arn != "" ? [var.alert_sns_topic_arn] : []
  ok_actions          = var.alert_sns_topic_arn != "" ? [var.alert_sns_topic_arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.transformer.function_name
  }

  tags = var.tags
}
