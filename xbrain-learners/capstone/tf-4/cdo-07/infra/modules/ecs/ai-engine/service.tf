# =============================================================================
# ECS Fargate Service — Foresight Lens AI Engine
# =============================================================================
# Contract: Deployment Contract §Compute
#   - Service name:  foresight-lens-engine
#   - CPU:           512 (0.5 vCPU)
#   - Memory:        1024 MB
#   - Container port: 8080
#   - Image source:  ECR repo URI + image tag (placeholder until AI team delivers)
#
# Contract: Deployment Contract §Health check
#   - Path:               /health
#   - Port:               8080
#   - Interval:           30 seconds
#   - Healthy threshold:  2 consecutive 200
#   - Unhealthy threshold: 3 consecutive non-200
#
# Contract: Deployment Contract §Secrets (env vars)
#   - AWS_REGION, BASELINE_BACKEND, BASELINE_S3_BUCKET, BASELINE_S3_PREFIX
# =============================================================================

module "ai_engine_service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.0"

  name        = "foresight-lens-engine"
  cluster_arn = module.ecs_cluster.cluster_arn

  cpu    = 512  # 0.5 vCPU  — Contract §Compute
  memory = 1024 # 1024 MB   — Contract §Compute

  desired_count = 2 # Contract §Scaling: min replicas

  # Disable built-in autoscaling — managed by autoscaling.tf (aws_appautoscaling_*)
  enable_autoscaling = false

  deployment_controller = {
    type = "CODE_DEPLOY"
  }

  # Use custom IAM roles (defined in iam.tf)
  create_task_exec_iam_role = false
  create_tasks_iam_role     = false
  task_exec_iam_role_arn    = aws_iam_role.task_execution.arn
  tasks_iam_role_arn        = aws_iam_role.task.arn

  # ---------- Container Definition ----------
  container_definitions = {
    foresight-lens = {
      name      = "foresight-lens-engine"
      image     = var.ecr_image_uri
      essential = true

      port_mappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        # Deployment Contract §Secrets — baseline
        { name = "AWS_REGION", value = var.aws_region },
        { name = "BASELINE_BACKEND", value = "s3" },
        { name = "BASELINE_S3_BUCKET", value = var.baseline_s3_bucket },
        { name = "BASELINE_S3_PREFIX", value = var.baseline_s3_prefix },
        # Deployment Contract §Secrets — audit log (S3 + KMS)
        { name = "AUDIT_BACKEND", value = "s3" },
        { name = "AUDIT_S3_BUCKET", value = var.audit_s3_bucket },
        { name = "AUDIT_KMS_KEY_ID", value = var.kms_key_arn },
      ]

      # CloudWatch log configuration
      log_configuration = {
        log_driver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "foresight-lens"
        }
      }
    }
  }

  # ---------- Load Balancer ----------
  # Required for ALBRequestCountPerTarget autoscaling metric (autoscaling.tf)
  load_balancer = {
    service = {
      target_group_arn = aws_lb_target_group.ai_engine.arn
      container_name   = "foresight-lens-engine"
      container_port   = 8080
    }
  }

  # ---------- Networking ----------
  subnet_ids = var.private_subnet_ids

  security_group_rules = {
    ingress_alb = {
      type                     = "ingress"
      from_port                = 8080
      to_port                  = 8080
      protocol                 = "tcp"
      source_security_group_id = var.alb_security_group_id
    }
    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tags = var.tags

  ignore_task_definition_changes = true
}

# =============================================================================
# ALB Target Group — AI Engine Health Check
# =============================================================================
resource "aws_lb_target_group" "ai_engine" {
  name        = "${var.environment}-ai-engine-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health" # Contract §Health check
    matcher             = "200"
    interval            = 30 # Contract: 30 seconds
    timeout             = 5
    healthy_threshold   = 2 # Contract: 2 consecutive 200
    unhealthy_threshold = 3 # Contract: 3 consecutive non-200
  }

  tags = var.tags
}

resource "aws_lb_target_group" "ai_engine_green" {
  name        = "${var.environment}-ai-engine-green-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = var.tags
}

# =============================================================================
# ALB Listener Rule — route /v1/* to AI Engine
# =============================================================================
# API Contract: POST /v1/predict
resource "aws_lb_listener_rule" "ai_engine" {
  listener_arn = var.alb_http_listener_arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ai_engine.arn
  }

  condition {
    path_pattern {
      values = ["/v1/*"]
    }
  }
}
