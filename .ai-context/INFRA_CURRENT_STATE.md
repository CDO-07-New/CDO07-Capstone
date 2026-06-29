# INFRA CURRENT STATE

> Last updated: 2026-06-29 (v4 — full runtime stack + hardened Cost Circuit Breaker)

## Repo path

```text
xbrain-learners/capstone/tf-4/cdo-07/infra/
```

## Terraform structure (runtime — implemented)

```
infra/
├── bootstrap/              # S3 state, KMS, OIDC, IAM deploy roles, ECR (one-time)
├── modules/
│   ├── cost-circuit-breaker/   # ✅ Budgets + daily cap CW alarm + Lambda CB + SSM
│   ├── networking/             # VPC, ALB, SGs, VPC endpoints
│   ├── streaming/              # Kinesis Data Streams
│   ├── data/                   # S3 audit bucket
│   ├── s3_baseline/            # ML baselines bucket
│   ├── sns_to_slack/           # SNS → Lambda → Slack
│   ├── ecs/
│   │   ├── mock-services/      # payment-gw, ledger, fraud (3 Fargate services)
│   │   └── ai-engine/          # AI Engine ECS + CodeDeploy
│   ├── lambda/
│   │   ├── transformer/        # Kinesis → Timestream
│   │   └── fail-open-fallback/ # SNS-triggered fallback
│   └── lambda-scheduled-function/  # Window Feeder (EventBridge 5 min)
├── lambda/window-feeder/       # App source; ZIP built in CI before apply
└── environments/
    ├── sandbox/    # ✅ full stack wired
    ├── staging/    # ✅ full stack wired (CI deploy target)
    └── prod/       # ✅ full stack wired
```

## Cost Circuit Breaker module resources (2026-06-29)

| Resource | Detail |
|---|---|
| Monthly budget | $200, 80% warning, 100% hard |
| Daily budget | $7/day (daily spend cap) |
| CloudWatch alarm | `EstimatedCharges` ≥ daily cap → hard-trigger SNS |
| Lambda CB | VPC-attached, KMS-encrypted env, DLQ, concurrency=1 |
| SSM | `/tf4-cdo07/{env}/inference_enabled` SecureString |
| SNS | Warning + hard-trigger topics (`alias/aws/sns` encryption) |

## Validation status (2026-06-29)

| Command | Result |
|---|---|
| `terraform fmt -check -recursive` | Pass |
| `terraform validate` (sandbox/staging/prod) | Pass |
| `checkov` CB module only | 0 failures |
| `checkov` full `infra/` with CI skip list | 0 failures |
| `python test_cost_circuit_breaker.py` | Pass |

## Bootstrap (unchanged)

| Item | Value |
|---|---|
| Terraform | `>= 1.10, < 2.0` |
| AWS provider | `~> 5.0` (lock: `5.100.0`) |
| Region | `us-east-1` |
| State bucket | `tf4-cdo07-tf-state-{account-id}-use1` |
| KMS alias | `alias/tf4-cdo07-bootstrap` |
| ECR repos | `ingest-service`, `ingest-worker`, `ai-serving` |

## Known gaps (deploy checklist)

| Gap | Priority | Notes |
|---|---|---|
| Timestream DB/table not in Terraform | 🔴 | Window Feeder + Transformer expect `tf4-cdo07-{env}/service-metrics` |
| Transformer handler stub | 🔴 | Timestream write not fully implemented |
| `slack_webhook_url = PLACEHOLDER` in sandbox/staging | 🟡 | Replace with real webhook or SSM lookup |
| `services/ingest-*` Dockerfiles missing | 🟢 | CI skips image build when absent |
| Billing alerts preference in AWS account | 🟡 | Required for daily CloudWatch alarm to fire |

## Application code boundaries

| Owner | Scope |
|---|---|
| CDO (Terraform) | All AWS resources, Lambda handlers in modules, window-feeder `app.py` |
| AI Team | `ai-serving` container image (ECR digest URI via CI var) |
| Mock services | ECS task defs reference images; app code optional/separate |
