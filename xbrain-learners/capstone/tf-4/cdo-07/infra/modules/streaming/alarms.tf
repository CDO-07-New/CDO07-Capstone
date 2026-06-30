###############################################################################
# CloudWatch Alarms for Kinesis Data Streams
###############################################################################

# 1. Iterator Age High (Consumer Lag)
resource "aws_cloudwatch_metric_alarm" "iterator_age_high" {
  alarm_name          = "${var.project}-${var.environment}-kinesis-iterator-age-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  namespace           = "AWS/Kinesis"
  period              = 60
  statistic           = "Maximum"
  threshold           = 60000 # 60 seconds (Lag qua 60s)
  alarm_description   = "Kinesis Iterator Age > 60s. Transformer dang bi cham hoac qua tai."

  dimensions = {
    StreamName = aws_kinesis_stream.telemetry.name
  }

  tags = var.tags
}

# 2. Incoming Records Spike
resource "aws_cloudwatch_metric_alarm" "incoming_records_spike" {
  alarm_name          = "${var.project}-${var.environment}-kinesis-incoming-records-spike"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "IncomingRecords"
  namespace           = "AWS/Kinesis"
  period              = 60
  statistic           = "Sum"
  threshold           = 3000000 # 50,000 / sec * 60 = 3,000,000 (Vuot limit thiet ke)
  alarm_description   = "Luu luong Kinesis vuot 50k events/sec. Kinesis On-Demand tu dong scale."

  dimensions = {
    StreamName = aws_kinesis_stream.telemetry.name
  }

  tags = var.tags
}
