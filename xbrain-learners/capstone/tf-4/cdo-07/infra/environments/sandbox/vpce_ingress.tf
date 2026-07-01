# =============================================================================
# VPC Endpoint Security Group Ingress Rules
# =============================================================================
# Allow ECS tasks to communicate with AWS API endpoints (ECR, Logs, etc.) via 443
# This fixes the ResourceInitializationError when ECS tasks cannot reach CloudWatch Logs

resource "aws_vpc_security_group_ingress_rule" "vpce_from_ai_engine" {
  security_group_id            = module.networking.vpce_security_group_id
  description                  = "HTTPS from AI Engine ECS tasks"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = module.ai_engine.security_group_id
}

resource "aws_vpc_security_group_ingress_rule" "vpce_from_payment" {
  security_group_id            = module.networking.vpce_security_group_id
  description                  = "HTTPS from Payment GW ECS tasks"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = module.mock_services.payment_security_group_id
}

resource "aws_vpc_security_group_ingress_rule" "vpce_from_ledger" {
  security_group_id            = module.networking.vpce_security_group_id
  description                  = "HTTPS from Ledger Svc ECS tasks"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = module.mock_services.ledger_security_group_id
}

resource "aws_vpc_security_group_ingress_rule" "vpce_from_fraud" {
  security_group_id            = module.networking.vpce_security_group_id
  description                  = "HTTPS from Fraud Detection ECS tasks"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = module.mock_services.fraud_security_group_id
}
