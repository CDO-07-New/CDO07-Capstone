# =============================================================================
# Application Auto Scaling — AI Engine
# =============================================================================
# Contract: Deployment Contract §Scaling
#   - Replicas:           min 2, max 4
#   - Autoscale trigger 1: Target CPU 70%
#   - Autoscale trigger 2: Target request count 80 RPS per task
#   - Scale-up cooldown:  60 seconds
#   - Scale-down cooldown: 300 seconds
# =============================================================================

resource "aws_appautoscaling_target" "ai_engine" {
  max_capacity       = 4 # Contract: max 4
  min_capacity       = 2 # Contract: min 2
  resource_id        = "service/${local.cluster_name}/foresight-lens-engine"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  depends_on = [module.ai_engine_service]
}

# -----------------------------------------------------------------------------
# Policy 1: CPU Utilization Target Tracking
# Contract: "Autoscale trigger 1 — Target CPU 70%"
# -----------------------------------------------------------------------------
resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.environment}-ai-engine-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ai_engine.resource_id
  scalable_dimension = aws_appautoscaling_target.ai_engine.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ai_engine.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = 70  # Contract: 70%
    scale_in_cooldown  = 300 # Contract: 300 seconds
    scale_out_cooldown = 60  # Contract: 60 seconds
  }
}

# -----------------------------------------------------------------------------
# Policy 2: ALB Request Count Per Target
# Contract: "Autoscale trigger 2 — Target request count 80 RPS per task"
# -----------------------------------------------------------------------------
resource "aws_appautoscaling_policy" "request_count" {
  name               = "${var.environment}-ai-engine-rps-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ai_engine.resource_id
  scalable_dimension = aws_appautoscaling_target.ai_engine.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ai_engine.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${var.alb_arn_suffix}/${aws_lb_target_group.ai_engine.arn_suffix}"
    }

    target_value       = 80  # Contract: 80 RPS per task
    scale_in_cooldown  = 300 # Contract: 300 seconds
    scale_out_cooldown = 60  # Contract: 60 seconds
  }
}
