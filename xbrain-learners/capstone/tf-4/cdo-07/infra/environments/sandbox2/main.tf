###############################################################################
# CDO-07 · Task Force 4 · Sandbox 2 Environment (Minimal for ECS testing)
###############################################################################

module "networking" {
  source = "../../modules/networking"

  vpc_name              = "cdo-07-sandbox2-vpc"
  vpc_cidr              = "10.1.0.0/16"
  private_subnet_cidr_a = "10.1.1.0/24"
  private_subnet_cidr_b = "10.1.2.0/24"
  public_subnet_cidr_a  = "10.1.101.0/24"
  public_subnet_cidr_b  = "10.1.102.0/24"
  enable_vpc_endpoints  = true

  tags = local.common_tags
}

module "mock_services" {
  source = "../../modules/ecs/mock-services"

  environment           = local.environment
  vpc_id                = module.networking.vpc_id
  private_subnet_ids    = module.networking.private_subnets
  alb_security_group_id = module.networking.alb_security_group_id
  alb_http_listener_arn = module.networking.alb_http_listener_arn
  aws_region            = local.aws_region
  
  # Dummy values for stripped modules
  kinesis_stream_arn    = "arn:aws:kinesis:us-east-1:123456789012:stream/dummy"
  kinesis_stream_name   = "dummy-stream"
  kms_key_arn           = local.kms_key_arn
  
  ecr_image_uri_payment = local.ecr_image_uri_payment
  ecr_image_uri_ledger  = local.ecr_image_uri_ledger
  ecr_image_uri_fraud   = local.ecr_image_uri_fraud
  
  tags                  = local.common_tags
}

module "ai_engine" {
  source = "../../modules/ecs/ai-engine"

  environment            = local.environment
  vpc_id                 = module.networking.vpc_id
  private_subnet_ids     = module.networking.private_subnets
  alb_security_group_id  = module.networking.alb_security_group_id
  alb_http_listener_arn  = module.networking.alb_http_listener_arn
  alb_arn_suffix         = module.networking.alb_arn_suffix
  
  # Dummy S3 values for sandbox2 testing
  baseline_s3_bucket     = "dummy-baseline-bucket"
  baseline_s3_bucket_arn = "arn:aws:s3:::dummy-baseline-bucket"
  audit_s3_bucket        = "dummy-audit-bucket"
  audit_s3_bucket_arn    = "arn:aws:s3:::dummy-audit-bucket"
  kms_key_arn            = local.kms_key_arn
  
  ecr_image_uri          = local.ecr_image_uri_ai
  
  tags                   = local.common_tags
}
