###############################################################################
# Security Groups — CDO-07 Network Security Design (03_security_design §1.2)
###############################################################################

# ---------------------------------------------------------------------------
# Lambda Security Group (tf4-cdo07-lambda-sg)
# Design: No inbound (triggered by internal AWS event source mapping).
#         Outbound: HTTPS 443 to VPC Endpoints.
# ---------------------------------------------------------------------------
resource "aws_security_group" "lambda" {
  name        = "${var.vpc_name}-lambda-sg"
  description = "Security group for Lambda functions. Outbound to VPC Endpoints only."
  vpc_id      = module.vpc.vpc_id

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-lambda-sg"
  })
}

resource "aws_vpc_security_group_egress_rule" "lambda_to_vpce" {
  security_group_id            = aws_security_group.lambda.id
  description                  = "HTTPS to VPC Endpoints"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.vpce.id
}

# ---------------------------------------------------------------------------
# VPC Endpoint Security Group (tf4-cdo07-vpce-sg)
# Design: Inbound 443 from app-sg (ALB module SG) + lambda-sg.
#         No outbound needed (endpoints are AWS-managed).
# ---------------------------------------------------------------------------
resource "aws_security_group" "vpce" {
  name        = "${var.vpc_name}-vpce-sg"
  description = "Security group for VPC Interface Endpoints. Inbound HTTPS from app and Lambda SGs."
  vpc_id      = module.vpc.vpc_id

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-vpce-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "vpce_from_alb" {
  security_group_id            = aws_security_group.vpce.id
  description                  = "HTTPS from ALB / ECS tasks"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = module.alb.security_group_id
}

resource "aws_vpc_security_group_ingress_rule" "vpce_from_lambda" {
  security_group_id            = aws_security_group.vpce.id
  description                  = "HTTPS from Lambda functions"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.lambda.id
}
