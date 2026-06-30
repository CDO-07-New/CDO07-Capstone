locals {
  aws_region  = "us-east-1"
  project     = "tf4-cdo07"
  environment = "sandbox"

  kms_key_arn = "arn:aws:kms:us-east-1:${data.aws_caller_identity.current.account_id}:key/6b3a4d47-1c1b-4732-b104-0cc1b4fca7d6"

  # ECR Image URIs for Mock Services
  # Update these after building and pushing images to ECR
  # Default to placeholders if not yet pushed
  ecr_account_id = data.aws_caller_identity.current.account_id
  ecr_region     = local.aws_region
  
  ecr_image_uri_payment = "${local.ecr_account_id}.dkr.ecr.${local.ecr_region}.amazonaws.com/cdo-07-payment-gw:latest"
  ecr_image_uri_ledger  = "${local.ecr_account_id}.dkr.ecr.${local.ecr_region}.amazonaws.com/cdo-07-ledger-svc:latest"
  ecr_image_uri_fraud   = "${local.ecr_account_id}.dkr.ecr.${local.ecr_region}.amazonaws.com/cdo-07-fraud-detection:latest"

  common_tags = {
    Project     = local.project
    Environment = local.environment
    ManagedBy   = "Terraform"
    Owner       = "CDO-07"
    TaskForce   = "TF4"
  }
}

data "aws_caller_identity" "current" {}
