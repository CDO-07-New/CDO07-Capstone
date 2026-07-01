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

resource "aws_vpc_security_group_ingress_rule" "vpce_from_vpc" {
  security_group_id = aws_security_group.vpce.id
  description       = "HTTPS from all resources in VPC (including ECS tasks)"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = module.vpc.vpc_cidr_block
}

resource "aws_vpc_security_group_ingress_rule" "vpce_from_lambda" {
  security_group_id            = aws_security_group.vpce.id
  description                  = "HTTPS from Lambda functions"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.lambda.id
}

# NOTE: Lambda egress to VPCE (port 443) is already covered by
# aws_vpc_security_group_egress_rule.lambda_to_vpce above.
# Secrets Manager uses the same VPCE SG — no extra rule needed.

# ---------------------------------------------------------------------------
# InfluxDB Security Group (tf4-cdo07-influxdb-sg)
# Design ref: 03_security_design §1.3 — Timestream (TS) VPC endpoint
#
# Timestream for InfluxDB listens on port 8086 (HTTP/HTTPS).
# Only Lambda SG is allowed inbound — ECS tasks access via same route.
# ---------------------------------------------------------------------------
resource "aws_security_group" "influxdb" {
  name        = "${var.vpc_name}-influxdb-sg"
  description = "Security group for Timestream InfluxDB instance. Inbound 8086 from Lambda and ECS only."
  vpc_id      = module.vpc.vpc_id

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-influxdb-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "influxdb_from_lambda" {
  security_group_id            = aws_security_group.influxdb.id
  description                  = "InfluxDB HTTP from Lambda functions"
  from_port                    = 8086
  to_port                      = 8086
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.lambda.id
}

resource "aws_vpc_security_group_ingress_rule" "influxdb_from_alb" {
  security_group_id            = aws_security_group.influxdb.id
  description                  = "InfluxDB HTTP from ALB / ECS app SG (AI Engine, Mock Services)"
  from_port                    = 8086
  to_port                      = 8086
  ip_protocol                  = "tcp"
  referenced_security_group_id = module.alb.security_group_id
}

# Lambda egress to InfluxDB port 8086
resource "aws_vpc_security_group_egress_rule" "lambda_to_influxdb" {
  security_group_id            = aws_security_group.lambda.id
  description                  = "InfluxDB HTTP to Timestream InfluxDB instance"
  from_port                    = 8086
  to_port                      = 8086
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.influxdb.id
}

# Lambda egress to ALB port 80 (Window Feeder → AI Engine)
resource "aws_vpc_security_group_egress_rule" "lambda_to_alb" {
  security_group_id            = aws_security_group.lambda.id
  description                  = "HTTP to ALB for AI Engine predict endpoint (Window Feeder)"
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  referenced_security_group_id = module.alb.security_group_id
}

# ALB ingress from Lambda (Window Feeder calling AI Engine)
resource "aws_vpc_security_group_ingress_rule" "alb_from_lambda" {
  security_group_id            = module.alb.security_group_id
  description                  = "HTTP from Lambda Window Feeder to AI Engine"
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.lambda.id
}
