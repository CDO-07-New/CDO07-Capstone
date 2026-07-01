###############################################################################
# CDO-07 · Task Force 4 · Sandbox Environment
###############################################################################

# --- Layer 1: Cost Governance ---
module "cost_circuit_breaker" {
  source = "../../modules/cost-circuit-breaker"

  project                   = local.project
  environment               = local.environment
  aws_region                = local.aws_region
  monthly_budget_limit_usd  = 200
  warning_threshold_percent = 80
  hard_threshold_percent    = 100
  ssm_parameter_name        = "/${local.project}/${local.environment}/inference_enabled"
  warning_email_addresses   = []
  lambda_timeout_seconds    = 10
  log_retention_days        = 30
  kms_key_arn               = local.kms_key_arn
  alert_sns_topic_arn       = module.sns_to_slack.sns_topic_arn
  tags                      = local.common_tags
}

# --- Layer 2: Networking ---
module "networking" {
  source = "../../modules/networking"

  vpc_name              = "cdo-07-sandbox-vpc"
  vpc_cidr              = "10.0.0.0/16"
  private_subnet_cidr_a = "10.0.1.0/24"
  private_subnet_cidr_b = "10.0.2.0/24"
  public_subnet_cidr_a  = "10.0.101.0/24"
  public_subnet_cidr_b  = "10.0.102.0/24"
  enable_vpc_endpoints  = true

  tags = local.common_tags
}

# --- Layer 2.5: SNS → Slack ---
module "sns_to_slack" {
  source = "../../modules/sns_to_slack"

  project     = local.project
  environment = local.environment

  # ⚠️ SECURITY: Webhook URL is NEVER hardcoded here.
  # Store it once manually in SSM Parameter Store (SecureString, KMS-encrypted):
  #
  #   aws ssm put-parameter \
  #     --name "/tf4-cdo07/sandbox/slack-webhook-url" \
  #     --type "SecureString" \
  #     --value "https://hooks.slack.com/services/xxx/yyy/zzz" \
  #     --key-id "alias/tf4-cdo07-bootstrap" \
  #     --region us-east-1
  #
  # Terraform will NOT manage the value (only reads ARN at runtime via Lambda).
  slack_webhook_parameter_name = "/${local.project}/${local.environment}/slack-webhook-url"
  slack_webhook_url            = null # Never put the URL here
  kms_key_arn                  = local.kms_key_arn

  tags = local.common_tags
}

# --- Layer 3a: Storage ---
module "s3_baseline" {
  source = "../../modules/s3_baseline"

  environment = local.environment
  tags        = local.common_tags
}

module "audit_s3" {
  source = "../../modules/data"

  project     = local.project
  environment = local.environment
  kms_key_arn = local.kms_key_arn

  # Timestream InfluxDB — placed in private subnets, protected by influxdb SG
  influxdb_subnet_ids             = module.networking.private_subnets
  influxdb_vpc_security_group_ids = [module.networking.influxdb_security_group_id]
  influxdb_db_instance_type       = "db.influx.medium"
  influxdb_allocated_storage      = 20 # Minimum for sandbox/staging
  influxdb_bucket                 = "service-metrics"
  influxdb_org                    = "cdo-07"

  tags = local.common_tags
}

# --- Layer 3b: Streaming ---
module "streaming" {
  source = "../../modules/streaming"

  project             = local.project
  environment         = local.environment
  kms_key_arn         = local.kms_key_arn
  alert_sns_topic_arn = module.sns_to_slack.sns_topic_arn
  tags                = local.common_tags
}

# --- Layer 3c: Mock Services ---
module "mock_services" {
  source = "../../modules/ecs/mock-services"

  environment           = local.environment
  vpc_id                = module.networking.vpc_id
  private_subnet_ids    = module.networking.private_subnets
  alb_security_group_id = module.networking.alb_security_group_id
  alb_http_listener_arn = module.networking.alb_http_listener_arn
  aws_region            = local.aws_region
  kinesis_stream_arn    = module.streaming.stream_arn
  kinesis_stream_name   = module.streaming.stream_name
  kms_key_arn           = local.kms_key_arn

  # ECR Image URIs - Real mock services instead of nginx placeholders
  ecr_image_uri_payment = local.ecr_image_uri_payment
  ecr_image_uri_ledger  = local.ecr_image_uri_ledger
  ecr_image_uri_fraud   = local.ecr_image_uri_fraud

  tags = local.common_tags
}

# --- Layer 3d: AI Engine ---
module "ai_engine" {
  source = "../../modules/ecs/ai-engine"

  environment            = local.environment
  vpc_id                 = module.networking.vpc_id
  private_subnet_ids     = module.networking.private_subnets
  alb_security_group_id  = module.networking.alb_security_group_id
  alb_http_listener_arn  = module.networking.alb_http_listener_arn
  alb_arn_suffix         = module.networking.alb_arn_suffix
  baseline_s3_bucket     = module.s3_baseline.bucket_name
  baseline_s3_bucket_arn = module.s3_baseline.bucket_arn
  audit_s3_bucket        = module.audit_s3.audit_bucket_name
  audit_s3_bucket_arn    = module.audit_s3.audit_bucket_arn
  kms_key_arn            = local.kms_key_arn
  alert_sns_topic_arn    = module.sns_to_slack.sns_topic_arn
  ecr_image_uri          = "201023212626.dkr.ecr.us-east-1.amazonaws.com/tf4-cdo07-ai-serving:sha-5a1403e90bc7-28486362173"
  tags                   = local.common_tags
}

# --- Layer 4a: Lambda Transformer ---
module "transformer" {
  source = "../../modules/lambda/transformer"

  project            = local.project
  environment        = local.environment
  kinesis_stream_arn = module.streaming.stream_arn
  kms_key_arn        = local.kms_key_arn

  # InfluxDB connection — replaces Timestream LiveAnalytics (AccessDeniedException)
  influxdb_url        = module.audit_s3.influxdb_endpoint_url
  influxdb_secret_arn = module.audit_s3.influxdb_secret_arn
  influxdb_bucket     = module.audit_s3.influxdb_bucket
  influxdb_org        = module.audit_s3.influxdb_org

  subnet_ids          = module.networking.private_subnets
  security_group_ids  = [module.networking.lambda_security_group_id]
  alert_sns_topic_arn = module.sns_to_slack.sns_topic_arn
  tags                = local.common_tags
}

# --- Layer 4b.0: Legacy AI Engine API Edge (not used by Window Feeder) ---
module "ai_predict_api" {
  source = "../../modules/api-gateway-ai-edge"

  project               = local.project
  environment           = local.environment
  vpc_id                = module.networking.vpc_id
  private_subnet_ids    = module.networking.private_subnets
  alb_listener_arn      = module.networking.alb_http_listener_arn
  alb_security_group_id = module.networking.alb_security_group_id

  tags = local.common_tags
}

# --- Layer 4b: Window Feeder ---
module "window_feeder" {
  source = "../../modules/lambda-scheduled-function"

  function_name        = "${local.project}-${local.environment}-window-feeder"
  function_description = "Queries Timestream, feeds AI Engine, writes audit, emits drift alerts."
  package_path         = "${path.module}/../../lambda/window-feeder/build/window-feeder.zip"
  handler              = "app.handler"
  runtime              = "python3.12"
  timeout_seconds      = 30
  memory_mb            = 256
  reserved_concurrency = -1 # sandbox: use unreserved concurrency pool
  subnet_ids           = module.networking.private_subnets
  security_group_ids   = [module.networking.lambda_security_group_id]
  schedule_expression  = "rate(5 minutes)"
  schedule_enabled     = true
  event_payload        = { source = "eventbridge", window = "2h", predict_path = "/v1/predict" }

  environment_variables = {
    # InfluxDB connection (replaces Timestream LiveAnalytics)
    INFLUXDB_URL                  = module.audit_s3.influxdb_endpoint_url
    INFLUXDB_BUCKET               = module.audit_s3.influxdb_bucket
    INFLUXDB_ORG                  = module.audit_s3.influxdb_org
    INFLUXDB_SECRET_ARN           = module.audit_s3.influxdb_secret_arn
    INFLUXDB_QUERY_WINDOW         = "2h"
    METRIC_WINDOW_STEP_SECONDS    = "300"
    FORWARD_FILL_LOOKBACK_SECONDS = "900"
    # AI Engine URL - Window Feeder calls ALB directly inside the VPC path.
    AI_ENGINE_PREDICT_URL            = "http://${module.networking.alb_dns_name}/v1/predict"
    AI_ENGINE_TIMEOUT_SECONDS        = "5"
    DEPLOYMENT_VERSION               = "${local.project}-${local.environment}"
    BASELINE_S3_BUCKET               = module.s3_baseline.bucket_name
    INFERENCE_ENABLED_PARAMETER_NAME = "/${local.project}/${local.environment}/inference_enabled"
    DRIFT_ALERT_SNS_TOPIC_ARN        = module.sns_to_slack.sns_topic_arn
  }

  iam_policy_document_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "WriteLambdaLogs", Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "arn:aws:logs:${local.aws_region}:*:log-group:/aws/lambda/${local.project}-${local.environment}-window-feeder:*" },
      # InfluxDB auth token — read operator token from Secrets Manager
      { Sid = "ReadInfluxDBToken", Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = [module.audit_s3.influxdb_secret_arn] },
      { Sid = "ReadInferenceGate", Effect = "Allow", Action = ["ssm:GetParameter"], Resource = "arn:aws:ssm:${local.aws_region}:*:parameter/${local.project}/${local.environment}/inference_enabled" },
      { Sid = "ReadBaselines", Effect = "Allow", Action = ["s3:GetObject", "s3:ListBucket"], Resource = [module.s3_baseline.bucket_arn, "${module.s3_baseline.bucket_arn}/*"] },
      { Sid = "PublishDriftAlerts", Effect = "Allow", Action = ["sns:Publish"], Resource = module.sns_to_slack.sns_topic_arn },
      { Sid = "ManageVpcENIs", Effect = "Allow", Action = ["ec2:CreateNetworkInterface", "ec2:DeleteNetworkInterface", "ec2:DescribeNetworkInterfaces"], Resource = "*" },
      { Sid = "KMSDecrypt", Effect = "Allow", Action = ["kms:Decrypt", "kms:DescribeKey"], Resource = [local.kms_key_arn] },
    ]
  })

  alert_sns_topic_arn = module.sns_to_slack.sns_topic_arn
  tags                = local.common_tags
}

# --- Layer 4c: Fail-Open Fallback ---
module "fail_open_fallback" {
  source = "../../modules/lambda/fail-open-fallback"

  project                       = local.project
  environment                   = local.environment
  window_feeder_failure_sns_arn = module.sns_to_slack.sns_topic_arn
  alert_sns_topic_arn           = module.sns_to_slack.sns_topic_arn
  audit_s3_bucket_name          = module.audit_s3.audit_bucket_name
  audit_s3_bucket_arn           = module.audit_s3.audit_bucket_arn
  kms_key_arn                   = local.kms_key_arn
  tags                          = local.common_tags
}
