locals {
  aws_region  = "us-east-1"
  project     = "tf4-cdo07"
  environment = "staging"

  # Bootstrap KMS key ARN — shared across all modules for encryption at rest.
  # This value comes from `terraform output` of the bootstrap workspace.
  kms_key_arn = "arn:aws:kms:us-east-1:${data.aws_caller_identity.current.account_id}:key/6b3a4d47-1c1b-4732-b104-0cc1b4fca7d6"

  common_tags = {
    Project     = local.project
    Environment = local.environment
    ManagedBy   = "Terraform"
    Owner       = "CDO-07"
    TaskForce   = "TF4"
  }
}

data "aws_caller_identity" "current" {}
