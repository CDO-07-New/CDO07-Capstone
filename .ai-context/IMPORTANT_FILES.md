# IMPORTANT FILES

> Last updated: 2026-06-29

## Cost Circuit Breaker — read first

| File | Why |
|---|---|
| `infra/modules/cost-circuit-breaker/main.tf` | Budgets, daily cap CW alarm, SNS, Lambda, SSM, IAM |
| `infra/modules/cost-circuit-breaker/lambda/cost_circuit_breaker.py` | Handler: SecureString + SNS alert |
| `infra/modules/cost-circuit-breaker/lambda/test_cost_circuit_breaker.py` | Unit test |
| `infra/modules/cost-circuit-breaker/variables.tf` | `daily_spend_cap_usd`, VPC, KMS inputs |
| `infra/environments/staging/main.tf` | Full env wiring (CB + networking + lambdas) |
| `.github/workflows/security-scan.yml` | Checkov skip list for capstone |
| `.github/workflows/deploy-staging.yml` | CI terraform apply staging |

## Validation commands

```powershell
# Unit test
python xbrain-learners\capstone\tf-4\cdo-07\infra\modules\cost-circuit-breaker\lambda\test_cost_circuit_breaker.py

# Terraform
terraform -chdir=xbrain-learners\capstone\tf-4\cdo-07\infra fmt -check -recursive
terraform -chdir=xbrain-learners\capstone\tf-4\cdo-07\infra\environments\staging validate

# Checkov (CB module)
checkov -d xbrain-learners\capstone\tf-4\cdo-07\infra\modules\cost-circuit-breaker --framework terraform
```

## Bootstrap

| File | Purpose |
|---|---|
| `infra/bootstrap/iam.tf` | GitHub OIDC deploy role |
| `infra/bootstrap/kms.tf` | CMK for SSM SecureString |
| `infra/bootstrap/state_bucket.tf` | Remote state |

## Architecture docs

| File | Purpose |
|---|---|
| `docs/images/CDO7-Solution 2.drawio.png` | Architecture source of truth |
| `docs/05_cost_analysis.md` | Cost guardrails §5 |
| `docs/deploy-checklist.md` | Deploy order + known gaps |
| `docs/03_security_design.md` | SSM SecureString, Lambda SG, VPC endpoints |

## Other runtime modules

| File | Purpose |
|---|---|
| `infra/modules/networking/` | VPC, ALB, lambda-sg |
| `infra/lambda/window-feeder/app.py` | Reads `INFERENCE_ENABLED_PARAMETER_NAME` |
| `infra/modules/lambda/fail-open-fallback/` | Static threshold fallback |
| `infra/modules/sns_to_slack/` | Slack alerting (CB publishes here) |

## CB troubleshooting

1. **Checkov fails** → run module-only scan; fix CB first, then check workflow `skip_check` list.
2. **CB not tripping** → confirm billing alerts enabled in AWS account for CW alarm.
3. **SSM still true after breach** → check Lambda logs `/aws/lambda/tf4-cdo07-{env}-cost-circuit-breaker`.
4. **Manual reset** → `aws ssm put-parameter --name /tf4-cdo07/{env}/inference_enabled --value true --type SecureString --overwrite`.
