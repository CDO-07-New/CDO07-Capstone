module "payment_gw" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.0"

  name        = "payment-gw"
  cluster_arn = module.ecs_cluster.cluster_arn

  cpu           = 256 # 0.25 vCPU
  memory        = 512 # 0.5 GB
  desired_count = 1

  # Use custom IAM roles (defined in iam.tf)
  create_task_exec_iam_role = false
  create_tasks_iam_role     = false
  task_exec_iam_role_arn    = aws_iam_role.mock_task_execution.arn
  tasks_iam_role_arn        = aws_iam_role.mock_task.arn

  # Task Definition
  container_definitions = {
    payment = {
      name      = "payment-gw"
      image     = var.ecr_image_uri_payment
      essential = true
      port_mappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "SERVICE_NAME", value = "payment-gw" },
        { name = "KINESIS_STREAM_NAME", value = var.kinesis_stream_name },
        { name = "AWS_REGION", value = var.aws_region },
      ]

      log_configuration = {
        log_driver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.mock_services.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "payment-gw"
        }
      }
    }
  }

  # Service
  subnet_ids = var.private_subnet_ids
  security_group_rules = {
    ingress_alb = {
      type                     = "ingress"
      from_port                = 3000
      to_port                  = 3000
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

  # Load Balancer Configuration
  load_balancer = {
    service = {
      target_group_arn = aws_lb_target_group.payment.arn
      container_name   = "payment-gw"
      container_port   = 3000
    }
  }

  depends_on = [aws_lb_target_group.payment]
}

resource "aws_lb_target_group" "payment" {
  name        = "${var.environment}-payment-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener_rule" "payment" {
  listener_arn = var.alb_http_listener_arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.payment.arn
  }

  condition {
    path_pattern {
      values = ["/payment*"]
    }
  }
}
