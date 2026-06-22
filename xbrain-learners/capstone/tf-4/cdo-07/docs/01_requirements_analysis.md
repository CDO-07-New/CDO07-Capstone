# Requirements Analysis - Task Force 4 · CDO-07

<!-- Doc owner: CDO-07 Lead
     Status: Draft (W11 T2-T3) → Final (W11 T6 Pack #1) → Refined (W12 T4 Pack #2)
     Word target: 800-1500 từ
     Last updated: 2026-06-22 -->

## 1. Đề tài context

<!-- Refer Nhóm AI's 01_requirements.md - restate ngắn gọn (1 paragraph) -->
<!-- TODO: Cập nhật sau khi đọc docs của nhóm AI -->

TF4 - **Foresight Lens**: Client là Head of SRE tại một fintech mid-size (~3.5M user active,
~120 microservice trên ECS Fargate + RDS Aurora + DynamoDB + SQS). Client miss SLO **7 lần
liên tiếp** trong 3 tháng không phải do incident catastrophic, mà do **capacity exhaustion
silent** - RDS CPU bò lên 100% trước khi alert fire, queue backlog âm thầm tăng 6×, ALB
connection limit chạm trần lúc Friday spike. Mỗi lần đều phát hiện sau khi user complain
qua support ticket (18-25 ticket trước khi internal alert fire).

Mục tiêu: xây **Foresight Lens** - system predict drift + capacity exhaustion **≥15 phút
trước** khi SLO breach xảy ra, kèm capacity recommendation actionable. Không auto-remediate
- predict + recommend + manual approval gate.

## 2. Infra non-functional requirements

| NFR | Target | Justification |
|---|---|---|
| Multi-tenant scale | ≥ 3 service (tier-1) demo, designed for 120 | Capstone scope per TF4 spec |
| SLO p99 latency (AI API) | < 1000ms | From AI API contract |
| Availability platform | ≥ 99.5% | Subscription SLA demo |
| Error rate | < 0.5% | Customer trust |
| Lead time prediction | ≥ 15 phút trước SLO breach | Hard requirement TF4 |
| Cost capstone | ≤ $200 / 2 tuần | Client budget constraint |
| Onboarding SLA (new service) | < 30 min từ register → baseline ready | Sales requirement |
| Metric ingest throughput | ~50k events/sec peak | TF4 high-volume time-series |
| Metric retention | ≥ 90 ngày | Baseline training + audit |
| Security baseline | IAM least-privilege + audit encrypted 90d | Compliance SOC2 |

## 3. Differentiation angle (KEY)

<!-- TODO: Lock angle sau khi thống nhất với 2 CDO còn lại trong TF4 - deadline T3 W11 -->
<!-- Chọn 1 trong các option dưới đây, xóa các option không chọn, điền lý do cụ thể -->

- **Angle chọn**: `< TODO: serverless-first / lakehouse / managed-observability / streaming-first >`
- **Why this angle**: `< TODO: fill sau khi thống nhất nội bộ TF4 >`
- **Trade-off chấp nhận**: `< TODO >`
- **Locked T3 W11**: 2026-06-23

> **Gợi ý angle cho CDO-07** (xóa section này sau khi chốt):
> - **Managed Observability** (Amazon Managed Prometheus + Managed Grafana): native time-series
>   query, Grafana annotation embed sẵn, alert integration. Win axis: integration speed + ops
>   simplicity. Trade-off: vendor lock-in AWS managed services, cost cao hơn self-hosted.
> - **Streaming-first** (Kinesis Data Streams + Lambda + Timestream): near-realtime ingest,
>   low-latency detection. Win axis: lead time ngắn nhất. Trade-off: complexity cao, Lambda cold start.
> - **Lakehouse** (S3 + Glue + Athena + QuickSight): durable, cheap long-term. Win axis: cost
>   + historical depth 90 ngày. Trade-off: latency cao hơn (batch), không realtime.

## 4. Comparison với 2 nhóm cùng task force

<!-- TODO: Điền sau khi biết angle của 2 CDO còn lại (T3 W11) -->

| Aspect | CDO-07 (my angle) | CDO-XX (angle B) | CDO-YY (angle C) |
|---|---|---|---|
| Compute pattern | `< TODO >` | TBD | TBD |
| Time-series storage | `< TODO >` | TBD | TBD |
| Ingest path | `< TODO >` | TBD | TBD |
| Cost profile | `< TODO >` | TBD | TBD |
| Ops complexity | `< TODO >` | TBD | TBD |
| Latency profile | `< TODO >` | TBD | TBD |
| **Win axis** | `< TODO >` | TBD | TBD |

## 5. Constraints

- **AWS only** (no multi-cloud)
- **Region**: us-east-1 (default TF4, confirm với Client)
- **Budget**: ≤ $200 / 2 tuần build
- **Code freeze**: T4 W12 18h (01/07/2026 18:00)
- **Production traffic**: KHÔNG - synthetic workload + k6/Locust load test only
- **Auto-remediation**: KHÔNG - predict + recommend only
- **LLM-based prediction**: KHÔNG (cost prohibitive) - statistical/ML model only

## 6. Open questions

<!-- Cập nhật sau Client interview chiều T2 22/06 -->

- [ ] Q1: Trong 120 service, tier-1 cụ thể nào cần baseline trước? Tiêu chí chọn là gì?
- [ ] Q2: Metric granularity hiện có (1-min / 5-min), retention bao lâu?
- [ ] Q3: Historical data có sẵn export được không (CloudWatch, Datadog)?
- [ ] Q4: Seasonality pattern rõ không - có calendar data (Black Friday, payroll cycle)?
- [ ] Q5: Alert routing khi predict drift: Slack channel nào, escalation path?
- [ ] Q6: Failure mode khi engine down - fallback static threshold hay skip alert?
- [ ] Q7: Region confirm: us-east-1 hay ap-southeast-1?
- [ ] Q8: CloudWatch GetMetricData rate limit - có hit không ở 50k events/sec?

---

## Related documents

- [`02_infra_design.md`](02_infra_design.md) - Architecture design cho platform này
- [`08_adrs.md`](08_adrs.md) - ADR cho differentiation angle + key decisions
- [`../../ai/docs/01_requirements.md`](../../ai/docs/01_requirements.md) - AI team requirements (source of truth cho AI scope)
