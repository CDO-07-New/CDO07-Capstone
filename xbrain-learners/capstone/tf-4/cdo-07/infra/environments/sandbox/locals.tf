locals {
  aws_region  = "us-east-1"
  project     = "tf4-cdo07"
  environment = "sandbox"

  kms_key_arn = aws_kms_key.sandbox.arn

  # ECR Image URIs for Mock Services
  # Update these after building and pushing images to ECR
  # Default to placeholders if not yet pushed
  ecr_account_id = data.aws_caller_identity.current.account_id
  ecr_region     = local.aws_region
  
  ecr_image_uri_payment = "${local.ecr_account_id}.dkr.ecr.${local.ecr_region}.amazonaws.com/cdo-07-payment-gw:v1.0.0"
  ecr_image_uri_ledger  = "${local.ecr_account_id}.dkr.ecr.${local.ecr_region}.amazonaws.com/cdo-07-ledger-svc:v1.0.0"
  ecr_image_uri_fraud   = "${local.ecr_account_id}.dkr.ecr.${local.ecr_region}.amazonaws.com/cdo-07-fraud-detection:v1.0.0"

  common_tags = {
    Project     = local.project
    Environment = local.environment
    ManagedBy   = "Terraform"
    Owner       = "CDO-07"
    TaskForce   = "TF4"
  }
}

data "aws_caller_identity" "current" {}
