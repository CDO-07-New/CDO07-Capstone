# Temporary import blocks — delete after successful terraform apply
# CloudWatch Log Groups already exist from previous partial apply

import {
  to = module.ai_engine.module.ai_engine_service.module.container_definition["foresight-lens"].aws_cloudwatch_log_group.this[0]
  id = "/aws/ecs/foresight-lens-engine/foresight-lens-engine"
}

import {
  to = module.mock_services.module.fraud_detection.module.container_definition["fraud"].aws_cloudwatch_log_group.this[0]
  id = "/aws/ecs/fraud-detection/fraud-detection"
}

import {
  to = module.mock_services.module.ledger_svc.module.container_definition["ledger"].aws_cloudwatch_log_group.this[0]
  id = "/aws/ecs/ledger-svc/ledger-svc"
}

import {
  to = module.mock_services.module.payment_gw.module.container_definition["payment"].aws_cloudwatch_log_group.this[0]
  id = "/aws/ecs/payment-gw/payment-gw"
}

# AutoScaling policies will be created fresh by Terraform
# (target and policies are managed by autoscaling.tf)
