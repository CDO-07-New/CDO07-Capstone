data "aws_availability_zones" "available" {}

locals {
  name = var.vpc_name
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = var.vpc_cidr

  # AWS ALB requires at least 2 AZs. We add a second AZ/Subnet to fulfill this requirement.
  azs             = [data.aws_availability_zones.available.names[0], data.aws_availability_zones.available.names[1]]
  private_subnets = [var.private_subnet_cidr_a, var.private_subnet_cidr_b]
  public_subnets  = [var.public_subnet_cidr_a, var.public_subnet_cidr_b]

  # Enable IGW for internet-facing ALB
  # No NAT Gateway needed - VPC Endpoints handle all AWS API traffic
  enable_nat_gateway = false
  single_nat_gateway = false

  tags = var.tags
}
