module "networking" {
  source = "../../modules/networking"

  vpc_name              = "cdo-07-staging-vpc"
  vpc_cidr              = "10.1.0.0/16"
  private_subnet_cidr_a = "10.1.1.0/24"
  private_subnet_cidr_b = "10.1.2.0/24"

  tags = {
    Environment = "Staging"
  }
}

module "mock_services" {
  source = "../../modules/ecs/mock-services"

  environment           = "staging"
  vpc_id                = module.networking.vpc_id
  private_subnet_ids    = module.networking.private_subnets
  alb_security_group_id = module.networking.alb_security_group_id
  alb_http_listener_arn = module.networking.alb_http_listener_arn

  tags = {
    Environment = "Staging"
  }
}

# ---------- S3 Baseline Storage (AI Engine) ----------
module "s3_baseline" {
  source = "../../modules/s3_baseline"

  environment = "staging"

  tags = {
    Environment = "Staging"
  }
}

# ---------- AI Engine — Foresight Lens ----------
module "ai_engine" {
  source = "../../modules/ecs/ai-engine"

  environment           = "staging"
  vpc_id                = module.networking.vpc_id
  private_subnet_ids    = module.networking.private_subnets
  alb_security_group_id = module.networking.alb_security_group_id
  alb_http_listener_arn = module.networking.alb_http_listener_arn
  alb_arn_suffix        = module.networking.alb_arn_suffix
  baseline_s3_bucket     = module.s3_baseline.bucket_name
  baseline_s3_bucket_arn = module.s3_baseline.bucket_arn

  tags = {
    Environment = "Staging"
  }
}
