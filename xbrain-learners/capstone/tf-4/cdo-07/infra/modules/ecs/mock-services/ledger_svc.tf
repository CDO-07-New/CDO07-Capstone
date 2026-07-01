module "ledger_svc" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.0"

  name        = "ledger-svc"
  cluster_arn = module.ecs_cluster.cluster_arn

  depends_on = [
    null_resource.push_mock_image["ledger-svc"],
    aws_lb_target_group.ledger
  ]

  cpu    = 256 # 0.25 vCPU
  memory = 512 # 0.5 GB

  # Use custom IAM roles (defined in iam.tf)
  create_task_exec_iam_role = false
  create_tasks_iam_role     = false
  task_exec_iam_role_arn    = aws_iam_role.mock_task_execution.arn
  tasks_iam_role_arn        = aws_iam_role.mock_task.arn

  container_definitions = {
    ledger = {
      name      = "ledger-svc"
      image     = var.ecr_image_uri_ledger
      essential = true
      port_mappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "SERVICE_NAME", value = "ledger-svc" },
        { name = "KINESIS_STREAM_NAME", value = var.kinesis_stream_name },
        { name = "AWS_REGION", value = var.aws_region },
      ]

      log_configuration = {
        log_driver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.mock_services.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ledger-svc"
        }
      }
    }
  }

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
      target_group_arn = aws_lb_target_group.ledger.arn
      container_name   = "ledger-svc"
      container_port   = 3000
    }
  }


}

resource "aws_lb_target_group" "ledger" {
  name        = "${var.environment}-ledger-tg"
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

resource "aws_lb_listener_rule" "ledger" {
  listener_arn = var.alb_http_listener_arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ledger.arn
  }

  condition {
    path_pattern {
      values = ["/ledger*"]
    }
  }
}
