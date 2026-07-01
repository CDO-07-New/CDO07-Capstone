###############################################################################
# CloudWatch Alarms for ECS AI Engine
###############################################################################

# 1. Memory Leak Alarm
resource "aws_cloudwatch_metric_alarm" "memory_leak" {
  alarm_name          = "${var.environment}-ai-engine-memory-leak"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "Trigger rolling restart task khi bi memory leak (> 90%)"
  alarm_actions       = var.alert_sns_topic_arn != "" ? [var.alert_sns_topic_arn] : []
  ok_actions          = var.alert_sns_topic_arn != "" ? [var.alert_sns_topic_arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.cluster_name
    ServiceName = "foresight-lens-engine"
  }

  tags = var.tags
}

# 2. P99 Latency Alarm (Canary Rollback)
resource "aws_cloudwatch_metric_alarm" "latency_p99_high" {
  alarm_name          = "${var.environment}-ai-engine-latency-p99-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  extended_statistic  = "p99"
  threshold           = 0.8 # 800ms
  alarm_description   = "API P99 Latency > 800ms. Trigger CodeDeploy Rollback & SLO breach."
  alarm_actions       = var.alert_sns_topic_arn != "" ? [var.alert_sns_topic_arn] : []
  ok_actions          = var.alert_sns_topic_arn != "" ? [var.alert_sns_topic_arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = aws_lb_target_group.ai_engine.arn_suffix
  }

  tags = var.tags
}

# 3. 5xx Error Rate Alarm (Canary Rollback)
resource "aws_cloudwatch_metric_alarm" "error_rate_high" {
  alarm_name          = "${var.environment}-ai-engine-error-rate-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  alarm_description   = "API 5xx Error Rate > 1%. Trigger CodeDeploy Rollback & SLO breach."
  alarm_actions       = var.alert_sns_topic_arn != "" ? [var.alert_sns_topic_arn] : []
  ok_actions          = var.alert_sns_topic_arn != "" ? [var.alert_sns_topic_arn] : []
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "e1"
    expression  = "m2 / m1 * 100"
    label       = "Error Rate"
    return_data = true
  }

  metric_query {
    id = "m1"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
        TargetGroup  = aws_lb_target_group.ai_engine.arn_suffix
      }
    }
  }

  metric_query {
    id = "m2"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
        TargetGroup  = aws_lb_target_group.ai_engine.arn_suffix
      }
    }
  }

  threshold = 1 # 1% error rate
  tags      = var.tags
}
