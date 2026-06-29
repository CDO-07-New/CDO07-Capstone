locals {
  aws_region  = "us-east-1"
  project     = "tf4-cdo07"
  environment = "prod"

  kms_key_arn = "arn:aws:kms:us-east-1:${data.aws_caller_identity.current.account_id}:alias/${local.project}-bootstrap"

  common_tags = {
    Project     = local.project
    Environment = local.environment
    ManagedBy   = "Terraform"
    Owner       = "CDO-07"
    TaskForce   = "TF4"
  }
}

data "aws_caller_identity" "current" {}
