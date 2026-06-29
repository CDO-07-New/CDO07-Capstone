# COST CIRCUIT BREAKER CONTEXT

> Last updated: 2026-06-29 (v4 — daily spend cap CloudWatch alarm, Checkov hardening, VPC-attached Lambda)

## Implementation status (2026-06-29)

| Item | Status |
|---|---|
| Terraform module | `infra/modules/cost-circuit-breaker` |
| Environment roots | `sandbox`, `staging`, `prod` — all wired with VPC subnets + lambda SG |
| Lambda runtime | Python 3.12, VPC-attached, `reserved_concurrent_executions = 1` |
| SSM path | `/tf4-cdo07/{environment}/inference_enabled` (SecureString + bootstrap KMS CMK) |
| Initial SSM value | `true` |
| Terraform lifecycle | `ignore_changes = [value]` — Terraform will not re-enable inference after CB trips |
| Monthly budget | `$200/month`, warning `80%` (`$160`), hard trigger `100%` (`$200`) |
| **Daily spend cap** | `$7/day` (ceil of `$200/30`) via **daily AWS Budget + CloudWatch alarm** |
| Trigger bridge | Budget / CloudWatch alarm → SNS hard-trigger topic → Lambda CB |
| Lambda behavior | `ssm.put_parameter(SecureString, false)` + optional SNS alert to Slack topic |
| Encryption | Bootstrap KMS CMK for SSM + Lambda logs/env; SNS uses `alias/aws/sns` |
| Checkov | CB module passes with 0 failures (2026-06-29 local scan) |
| Unit test | `lambda/test_cost_circuit_breaker.py` — covers SSM + SNS publish |

## Cost guardrails flow (complete)

```
Layer A — Monthly AWS Budget ($200)
  Warning 80% ($160)  → SNS budget-warning (notify only)
  Hard 100% ($200)    → SNS budget-hard-trigger → Lambda CB

Layer B — Daily AWS Budget ($7/day)
  Hard 100%           → SNS budget-hard-trigger → Lambda CB

Layer C — CloudWatch alarm (daily spend cap)
  Metric: AWS/Billing EstimatedCharges (USD)
  Threshold: $7 (daily_spend_cap_usd)
  Breach              → SNS budget-hard-trigger → Lambda CB

Lambda CB (VPC-attached)
  1. ssm.put_parameter(inference_enabled = "false", SecureString)
  2. sns.publish(alert topic) — Slack drift-alert channel
    ↓
Lambda Window Feeder (5-min EventBridge)
  check SSM inference_enabled
    ├── true  → query Timestream → call AI Engine
    └── false → skip AI / Fail-Open Fallback
```

**Diagram**: `docs/images/CDO7-Solution 2.drawio.png` section ⑥. Deploy path uses Budget/SNS/Lambda (not direct Budget→Lambda) because AWS Budgets notifications require SNS subscriber.

## AWS Resources in module

| Resource | Purpose |
|---|---|
| `aws_budgets_budget.monthly_cost` | Monthly `$200`, 80% warning, 100% hard trigger |
| `aws_budgets_budget.daily_cost` | Daily `$7` hard trigger (daily spend cap) |
| `aws_cloudwatch_metric_alarm.daily_spend_cap` | **CloudWatch alarm** on `EstimatedCharges` |
| `aws_cloudwatch_metric_alarm.circuit_breaker_lambda_errors` | Ops alarm if CB Lambda fails |
| `aws_sns_topic.budget_warning` | Warning notifications |
| `aws_sns_topic.budget_hard_trigger` | Invokes Lambda CB (Budgets + CloudWatch allowed) |
| `aws_lambda_function.cost_circuit_breaker` | Sets SSM + publishes Slack alert |
| `aws_ssm_parameter.inference_enabled` | SecureString circuit-breaker flag |
| `aws_iam_role` + policy | SSM Put, logs, KMS, SNS, VPC ENI, DLQ |
| `aws_sqs_queue.lambda_dlq` | Lambda DLQ |
| `aws_cloudwatch_log_group.lambda` | KMS-encrypted logs |

## Budget numbers — CONFIRMED

| Threshold | Value | Action |
|---|---|---|
| Monthly limit | $200 | Hard cap |
| Warning | $160 (80%) | Notify only |
| Hard trigger | $200 (100%) | Lambda CB → SSM false |
| Daily cap | $7 (ceil 200/30) | Daily budget + CloudWatch alarm → Lambda CB |

## Lambda handler (`cost_circuit_breaker.py`)

- Writes `SecureString` (matches Terraform SSM type).
- Publishes JSON alert to `ALERT_SNS_TOPIC_ARN` when configured.
- Env vars: `SSM_PARAMETER_NAME`, `DISABLED_VALUE`, `ALERT_SNS_TOPIC_ARN`, `CIRCUIT_BREAKER_REASON`.

## Module inputs (new in v4)

| Variable | Default | Notes |
|---|---|---|
| `daily_spend_cap_usd` | `ceil(monthly/30)` | Override per env if needed |
| `subnet_ids` | `[]` | Set from `module.networking.private_subnets` in env roots |
| `security_group_ids` | `[]` | Set from `module.networking.lambda_security_group_id` |
| `kms_key_arn` | required | Bootstrap alias ARN; resolved to CMK via `data.aws_kms_key` |
| `alert_sns_topic_arn` | optional | `module.sns_to_slack.sns_topic_arn` in all envs |

## Reset mechanism

**Manual only** (no auto-remediation per client requirement):

```powershell
aws ssm put-parameter --name /tf4-cdo07/staging/inference_enabled --type SecureString --value true --overwrite
```

## CI / Checkov notes

- CB module: 0 Checkov failures after 2026-06-29 hardening.
- Full `infra/` scan passes CI with capstone-appropriate global skips in `.github/workflows/security-scan.yml`.
- Billing CloudWatch alarm requires **billing alerts enabled** in AWS account (Console → Billing → preferences). Not enforceable via Terraform.

## Out of scope

- Window Feeder / Fail-Open Fallback application logic (separate modules).
- Auto-reset of `inference_enabled` after budget recovery.
- NAT Gateway (Lambdas use VPC endpoints).
