locals {
  name = "${var.project}-${var.environment}-ai-edge"
}

resource "aws_security_group" "vpc_link" {
  name        = "${local.name}-vpclink-sg"
  description = "API Gateway VPC Link egress to AI Engine ALB"
  vpc_id      = var.vpc_id

  egress {
    description     = "Forward API Gateway traffic to ALB HTTP listener"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  tags = merge(var.tags, {
    Name      = "${local.name}-vpclink-sg"
    Component = "api-gateway-ai-edge"
  })
}

resource "aws_security_group_rule" "alb_from_vpc_link" {
  type                     = "ingress"
  description              = "Allow API Gateway VPC Link to call AI Engine route on ALB"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = var.alb_security_group_id
  source_security_group_id = aws_security_group.vpc_link.id
}

resource "aws_apigatewayv2_api" "this" {
  name          = "${local.name}-api"
  protocol_type = "HTTP"
  description   = "IAM-authenticated edge for AI Engine /v1/predict"

  tags = merge(var.tags, {
    Name      = "${local.name}-api"
    Component = "api-gateway-ai-edge"
  })
}

resource "aws_apigatewayv2_vpc_link" "this" {
  name               = "${local.name}-vpclink"
  subnet_ids         = var.private_subnet_ids
  security_group_ids = [aws_security_group.vpc_link.id]

  tags = merge(var.tags, {
    Name      = "${local.name}-vpclink"
    Component = "api-gateway-ai-edge"
  })
}

resource "aws_apigatewayv2_integration" "alb" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "POST"
  integration_uri        = var.alb_listener_arn
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.this.id
  payload_format_version = "1.0"
  timeout_milliseconds   = 5000
}

resource "aws_apigatewayv2_route" "predict" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /v1/predict"
  authorization_type = "AWS_IAM"
  target             = "integrations/${aws_apigatewayv2_integration.alb.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  tags = merge(var.tags, {
    Name      = "${local.name}-default-stage"
    Component = "api-gateway-ai-edge"
  })
}
