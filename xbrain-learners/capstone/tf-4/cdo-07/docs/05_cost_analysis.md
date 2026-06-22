# Cost Analysis - Task Force 4 · CDO-07

<!-- Doc owner: CDO-07
     Status: Skeleton (W11 T6 Pack #1) → Measured actual (W12 T4 Pack #2)
     Word target: 800-1500 từ
     Last updated: 2026-06-22 -->

> **W11 T6**: Điền §1 + §2 + §3 + §4 với forecast estimate.
> **W12 T4**: Cập nhật §5 với measured actual từ AWS Cost Explorer.

---

## 1. Cost model per service/month (forecast)

<!-- TODO: Điền sau khi lock differentiation angle (T3 W11) -->
<!-- Unit cost lấy từ AWS pricing calculator: https://calculator.aws -->

| Component | Unit cost | Service avg usage | $/service/month |
|---|---|---|---|
| Compute (Fargate/Lambda) | `$X/hr` | `Y hr` | `$Z` |
| Time-series storage (Timestream/AMP) | `$X/GB-month` | `Y GB` | `$Z` |
| S3 (audit log + IaC state) | $0.023/GB | ~2 GB | ~$0.05 |
| Data transfer | $0.09/GB out | `Y GB` | `$Z` |
| AI inference (Bedrock) | `$X/1k tokens` | `Y calls` | `$Z` |
| CloudWatch Logs | $0.50/GB ingested | `Y GB` | `$Z` |
| Secrets Manager | $0.40/secret + $0.05/10k API calls | 4 secrets | ~$2 |
| Grafana (Managed) | $9/user/month | 2 users | $18 |
| **Total / service / month** | | | **`$N`** |

> **Budget ceiling**: $200 / 2 tuần capstone. Circuit breaker CloudWatch alarm tại $160 (80%).

## 2. Cost at scale

| Service count | Monthly total (forecast) | Avg per-service |
|---|---|---|
| 3 (capstone demo) | `$X` | `$N` |
| 10 | `$X` | `$N (shared fixed amortize)` |
| 50 | `$X` | `$N` |
| 120 (production target) | `$X` | `$N` |

*Fixed cost (VPC, ALB, Grafana) amortize theo số service → per-service cost giảm dần.*

## 3. Cost optimization applied

- [ ] Fargate Spot cho ingest layer (non-critical) → ~70% saving vs on-demand
- [ ] Lambda cho AI engine nếu request rate thấp (pay-per-invocation, zero idle)
- [ ] S3 lifecycle: Standard (30 ngày) → IA (90 ngày) → Glacier (1 năm)
- [ ] Timestream: Data retention split - memory store 7 ngày, magnetic store 90 ngày
- [ ] CloudWatch log retention: 14 ngày (không giữ forever)
- [ ] VPC endpoints thay NAT Gateway → tiết kiệm $0.045/GB data processing
- [ ] Bedrock prompt caching (nếu AI team support) → reduce token cost repeat prompts
- [ ] Right-sizing: Lambda 256MB → 512MB nếu CPU-bound (benchmark trước)

## 4. Cost vs alternatives (cùng TF4)

<!-- TODO: Điền sau khi biết angle của 2 CDO còn lại (T3 W11) -->

| Angle | $/service/month forecast | Why different |
|---|---|---|
| CDO-07: `< TODO angle >` | `$N` | `< TODO lý do >` |
| CDO-XX: TBD | TBD | TBD |
| CDO-YY: TBD | TBD | TBD |

## 5. Measured actual (W12 T4 - fill sau khi build)

### 5.1 2-week capstone actual spend

<!-- Lấy từ AWS Cost Explorer sau code freeze T4 W12 -->

| Service | Forecast | Actual | Delta |
|---|---|---|---|
| Compute | $X | — | — |
| Time-series storage | $X | — | — |
| S3 | $X | — | — |
| AI inference (Bedrock) | $X | — | — |
| CloudWatch / observability | $X | — | — |
| Data transfer | $X | — | — |
| **Total** | **$X** | **—** | **—** |

### 5.2 Per-service actual (3 test services)

| Service | Load profile | $/day measured | Extrapolate $/month |
|---|---|---|---|
| payment-gateway | medium (synthetic) | — | — |
| kyc-service | low | — | — |
| reporting-service | batch-heavy | — | — |

### 5.3 Cost-per-correct-prediction (joint với AI eval)

| Metric | Value |
|---|---|
| Total Bedrock calls trong capstone | — |
| Correct predictions (AI eval report) | — |
| Total AI inference cost | — |
| **Cost per correct prediction** | **—** |

*Cross-reference: [`../../ai/docs/04_eval_report.md`](../../ai/docs/04_eval_report.md) §3*

---

## 6. Cost guardrails

- **Budget alert**: CloudWatch Budget alarm tại 70% ($140), 90% ($180), 100% ($200)
- **Per-service quota**: rate limit X req/min/service tại AI engine layer
- **Bedrock daily spend cap**: CloudWatch alarm `bedrock:InvokeModel` cost > $10/day
- **Auto-shutdown sandbox**: EventBridge rule tắt Fargate tasks ngoài giờ build (22h-8h) để tiết kiệm

---

## 7. Cost recommendations cho production

- Reserved capacity (Fargate Compute Savings Plan) sau 3 tháng usage baseline
- Migrate từ Managed Grafana → self-hosted Grafana nếu scale > 50 services (break-even ~$X)
- Timestream magnetic store cho historical data > 90 ngày thay vì S3 + Athena (benchmark cần)

---

## Related documents

- [`02_infra_design.md`](02_infra_design.md) - Infra decisions drive compute/storage cost
- [`07_test_eval_report.md`](07_test_eval_report.md) - Load test validates throughput assumptions
- [`../../ai/docs/03_ai_engine_spec.md`](../../ai/docs/03_ai_engine_spec.md) §7 - AI inference cost per call
