###############################################################################
# VPC Endpoints — CDO-07 (03_security_design §1.3)
#
# Eliminates need for NAT Gateway by routing all AWS API traffic through
# private VPC Endpoints. Design specifies no NAT (cost optimization).
###############################################################################

locals {
  # Interface endpoints required by the architecture
  interface_endpoints = {
    ecr_api = {
      service = "ecr.api"
    }
    ecr_dkr = {
      service = "ecr.dkr"
    }
    logs = {
      service = "logs"
    }
    ssm = {
      service = "ssm"
    }
    kms = {
      service = "kms"
    }
    kinesis_streams = {
      service = "kinesis-streams"
    }
    secretsmanager = {
      service = "secretsmanager"
    }
  }
}

# ---------------------------------------------------------------------------
# Interface Endpoints — ECR, CloudWatch Logs, SSM, KMS, Kinesis
# ---------------------------------------------------------------------------
resource "aws_vpc_endpoint" "interface" {
  for_each = var.enable_vpc_endpoints ? local.interface_endpoints : {}

  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_availability_zones.available.id != "" ? regex("^[a-z]+-[a-z]+-[0-9]+", data.aws_availability_zones.available.names[0]) : "us-east-1"}.${each.value.service}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [aws_security_group.vpce.id]

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-vpce-${each.key}"
  })
}

# ---------------------------------------------------------------------------
# Gateway Endpoint — S3 (no cost, no SG needed)
# ---------------------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${regex("^[a-z]+-[a-z]+-[0-9]+", data.aws_availability_zones.available.names[0])}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = module.vpc.private_route_table_ids

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-vpce-s3"
  })
}
