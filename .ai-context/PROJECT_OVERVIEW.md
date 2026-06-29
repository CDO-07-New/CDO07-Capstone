# PROJECT OVERVIEW

> Last updated: 2026-06-29 (v4)

## Project là gì

**TF4 · CDO-07 · Foresight Lens** — Predictive monitoring platform cho fintech.

- **Client**: Fintech, 3.5M users, 2.8k RPS / 9k peak, 120 microservices on ECS Fargate.
- **Mục tiêu**: Phát hiện sớm ≥15 phút trước sự cố. Tenants: `payment-gateway`, `kyc-service`, `reporting-api`.
- **Constraint**: AWS only, **$200/month cap**, no auto-remediation, no LLM, infra metrics only.
- **Capstone window**: W11–W12 (22/06 – 02/07/2026).

## Kiến trúc (diagram v2 — AMP/ADOT path in docs; repo implements Kinesis/Timestream stack)

Source: `docs/images/CDO7-Solution 2.drawio.png`

```
Mock Services (ECS) → Kinesis → Lambda Transformer → Timestream
EventBridge 5-min → Lambda Window Feeder
  ① SSM inference_enabled?
  ② Query Timestream 2h window
  ③ POST ALB /v1/predict (AI Engine)
  ④ on fail → Fail-Open Fallback Lambda
SNS → Slack (drift alerts)

Cost Circuit Breaker (section ⑥):
  Monthly Budget $200 (warn $160) + Daily cap $7 + CloudWatch alarm
    → Lambda CB → SSM inference_enabled = false → Window Feeder skips AI
```

## Cost guardrails (three layers)

| Layer | Mechanism | Threshold | Action |
|---|---|---|---|
| Monthly warning | AWS Budgets | 80% ($160) | SNS email/Slack warning |
| Monthly hard | AWS Budgets | 100% ($200) | Lambda CB → SSM false |
| **Daily spend cap** | Daily Budget + **CloudWatch alarm** | $7/day | Lambda CB → SSM false |

## AWS Services — deployment specs

| Component | Service | Notes |
|---|---|---|
| Region | `us-east-1` | Single-region capstone |
| Telemetry | Kinesis + Lambda Transformer | → Timestream `service-metrics` |
| Prediction | EventBridge + Window Feeder Lambda | 5-min, reads SSM gate |
| AI Engine | ECS Fargate + ALB | Image from AI team ECR |
| Mock services | ECS Fargate ×3 | payment-gw, ledger, fraud |
| Fallback | Lambda fail-open-fallback | CPU/Mem/Conn/Queue thresholds |
| Circuit breaker | Budgets + CW alarm + Lambda + SSM | **Implemented** |
| Alerting | SNS → Slack Lambda | drift-alert channel |
| Networking | VPC 10.x/16, private subnets, VPC endpoints | No NAT |

## Luồng chính

1. **Telemetry**: Mock services → Kinesis → Transformer → Timestream
2. **Prediction (happy)**: Window Feeder → SSM=true → Timestream → AI `/v1/predict` → audit S3
3. **Prediction (fallback)**: SSM=false OR AI timeout → Fail-Open Fallback
4. **Cost Circuit Breaker**: Budget/CW breach → Lambda CB → SSM=false → skip AI
5. **Compliance**: Audit S3 → Glacier lifecycle; SNS → Slack

## CI/CD (GitHub Actions)

| Workflow | Trigger | Purpose |
|---|---|---|
| `security-scan.yml` | push/PR | Gitleaks, Trivy, **Checkov** |
| `build-test.yml` | push/PR | Build/test service images |
| `deploy-staging.yml` | push `develop` | Terraform apply + ECS deploy |
| `terraform-plan.yml` | PR | Plan on target env |
| `drift-detection.yml` | daily | State drift check |

## Phạm vi Terraform vs app code

| CDO (infra) | Terraform + minimal Lambda handlers |
| AI Team | `ai-serving` container (`POST /v1/predict`) |
| Mock apps | Optional; ECS references ECR images |
