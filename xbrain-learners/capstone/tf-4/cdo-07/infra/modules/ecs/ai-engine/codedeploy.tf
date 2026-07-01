# =============================================================================
# CodeDeploy Blue/Green — Foresight Lens AI Engine
# =============================================================================

data "aws_iam_policy_document" "codedeploy_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codedeploy.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codedeploy" {
  name               = "tf4-cdo07-${var.environment}-foresight-lens-codedeploy-role"
  assume_role_policy = data.aws_iam_policy_document.codedeploy_assume_role.json
  description        = "CodeDeploy service role for ${var.environment} Foresight Lens ECS blue/green deployments."

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "codedeploy_ecs" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

resource "aws_codedeploy_app" "ai_engine" {
  name             = "tf4-cdo07-${var.environment}-foresight-lens-engine"
  compute_platform = "ECS"

  tags = var.tags
}

resource "aws_codedeploy_deployment_group" "ai_engine" {
  app_name               = aws_codedeploy_app.ai_engine.name
  deployment_group_name  = "tf4-cdo07-${var.environment}-foresight-lens-engine"
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
  service_role_arn       = aws_iam_role.codedeploy.arn

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }

  ecs_service {
    cluster_name = local.cluster_name
    service_name = module.ai_engine_service.name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [var.alb_http_listener_arn]
      }

      target_group {
        name = aws_lb_target_group.ai_engine.name
      }

      target_group {
        name = aws_lb_target_group.ai_engine_green.name
      }
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  alarm_configuration {
    enabled = true
    alarms = [
      aws_cloudwatch_metric_alarm.error_rate_high.alarm_name,
      aws_cloudwatch_metric_alarm.latency_p99_high.alarm_name,
    ]
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.codedeploy_ecs,
    module.ai_engine_service,
  ]
}
