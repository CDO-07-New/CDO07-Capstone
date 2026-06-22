# Architecture Decision Records - CDO-07 · Task Force 4

<!-- Doc owner: CDO-07
     Status: Ongoing log W11-W12. Append-only - KHÔNG xóa ADR cũ.
     Last updated: 2026-06-22 -->

> **Khi nào viết ADR**: decision có trade-off thật, reversal cost cao, hoặc buổi chấm sẽ hỏi
> "sao chọn vậy?". Không cần ADR cho chuyện nhỏ (tên resource, naming convention).
>
> **Append-only**: khi 1 ADR bị supersede, đánh dấu `Status: Superseded by ADR-NNN`.
> KHÔNG xóa ADR cũ.
>
> **Target**: ≥ 3 ADR cho Pack #1 (W11 T6) · ≥ 5 ADR cho Pack #2 (W12 T4)

---

## ADR-001 - Differentiation angle: `< TODO: tên angle chọn >`

- **Status**: Proposed → (update thành Accepted sau khi lock T3 W11)
- **Date**: 2026-06-23
- **Context**: TF4 có 3 CDO compete trên cùng đề Foresight Lens. Mỗi CDO phải chọn
  differentiation angle riêng không overlap. TF4 yêu cầu high-volume time-series ingest
  (~50k events/sec), Grafana annotation overlay, và cost budget $200/2 tuần. CDO-07 cần
  angle vừa technically sound vừa khác biệt so với 2 CDO còn lại.
- **Decision**: `< TODO: chọn angle gì sau khi thống nhất nội bộ TF4 T3 W11 >`
- **Consequence**:
  - ✅ `< Pro 1 >`
  - ✅ `< Pro 2 >`
  - ⚠️ `< Trade-off 1 >`
  - ⚠️ `< Trade-off 2 >`
- **Alternatives considered**:
  - Managed Observability (AMP + Managed Grafana): native Grafana, ops-light, nhưng cost cao
    $9/user/month Grafana license
  - Streaming-first (Kinesis + Lambda + Timestream): lowest latency, nhưng complexity cao nhất
  - Lakehouse (S3 + Glue + Athena): cheapest storage, nhưng latency seconds → risk miss lead
    time ≥15 phút
  - `< TODO: điền option đã chọn + rejected options >`

---

## ADR-002 - Time-series storage: `< TODO: Timestream / AMP / S3+Athena >`

- **Status**: Proposed
- **Date**: 2026-06-23
- **Context**: TF4 telemetry contract yêu cầu storage phải support time-series query hiệu quả,
  KHÔNG phải raw S3. Volume ~50k events/sec peak, retention 90 ngày minimum. 3 options khả thi:
  Amazon Timestream (managed TSDB), Amazon Managed Prometheus (AMP, pull-based), S3 + Athena
  (lakehouse, batch query).
- **Decision**: `< TODO >`
- **Consequence**:
  - ✅ `< TODO >`
  - ⚠️ `< TODO >`
- **Alternatives considered**:
  - **Amazon Timestream**: SQL-like query, managed, write $0.50/GB, query $0.01/GB.
    Cons: vendor lock-in, more expensive than S3.
  - **Amazon Managed Prometheus (AMP)**: PromQL, tích hợp Grafana native (pull-based, scrape interval).
    Cons: pull-based model không phù hợp push event từ microservice, cần Prometheus agent sidecar.
  - **S3 + Athena**: cheapest ($0.023/GB storage + $5/TB query). Cons: query latency seconds
    → không phù hợp near-realtime predict.
  - **InfluxDB self-hosted**: free, powerful. Cons: ops overhead, không managed → nằm ngoài
    capstone scope.

---

## ADR-003 - Compute target cho AI engine: `< TODO: Fargate / Lambda >`

- **Status**: Proposed
- **Date**: 2026-06-23
- **Context**: AI engine cần serve `POST /v1/predict` với P99 < 1000ms, throughput moderate
  (predict không phải per-event, chỉ per time-window ~1 req/min/service). Budget $200 total.
  Deployment Contract từ AI team (nhận EOD T4 W11) sẽ confirm compute target.
- **Decision**: `< TODO: chờ Deployment Contract từ AI team T4 W11 >`
- **Consequence**:
  - ✅ `< TODO >`
  - ⚠️ `< TODO >`
- **Alternatives considered**:
  - **Lambda**: $0 idle, $0.0000166667/GB-second. Pros: cost optimal cho low-frequency predict.
    Cons: cold start ~500ms, có thể miss P99 < 1000ms target nếu cold.
  - **ECS Fargate on-demand**: $0.04048/vCPU-hour. Pros: no cold start, consistent latency.
    Cons: ~$30/month idle cost.
  - **ECS Fargate Spot**: 70% cheaper. Pros: cost. Cons: interruption risk, cần fallback.
  - **Lambda + Provisioned Concurrency**: no cold start + pay-per-use. Cons: more complex + cost.

---

## ADR-004 - Audit log storage: S3 Object Lock

- **Status**: Accepted
- **Date**: 2026-06-22
- **Context**: TF4 hard requirement - audit log mỗi prediction call, encrypted at rest,
  retention spec'd. Fintech client có SOC2 Type II concern. Cần tamper-evident storage cho
  mọi AI decision. Options: S3 Object Lock, DynamoDB + hash chain, append-only RDS.
- **Decision**: S3 Object Lock COMPLIANCE mode, 90 ngày minimum retention.
  CMK encryption (`tf4-cdo07-audit-cmk`). Athena trên top để query.
- **Consequence**:
  - ✅ Tamper-evident by design (AWS managed, không cần custom hash chain)
  - ✅ Athena query dễ - SQL trên S3 JSON
  - ✅ Cost thấp ($0.023/GB) so với DynamoDB ($0.25/GB)
  - ⚠️ Object Lock COMPLIANCE: không thể delete trước 90 ngày kể cả admin - test data cũng bị lock
  - ⚠️ Query latency Athena 2-5 giây (không realtime), nhưng audit use case không cần realtime
- **Alternatives considered**:
  - DynamoDB append-only: pros: millisecond query. Cons: $0.25/GB >> S3, không cần realtime
    cho audit use case.
  - CloudWatch Logs với export: pros: native. Cons: không tamper-evident, easy delete.
  - Custom hash chain DB: pros: crypto proof. Cons: implementation complexity high, out of
    scope per TF3 spec (Object Lock đủ).

---

## ADR-005 - IaC tool: Terraform over CDK

- **Status**: Accepted
- **Date**: 2026-06-22
- **Context**: CDO-07 cần IaC cho AWS infra. Options: Terraform (HCL), AWS CDK (TypeScript/Python),
  CloudFormation (YAML). Team CDO-07 có kinh nghiệm từ W6-W10.
- **Decision**: Terraform với HCL. State backend S3 + DynamoDB lock.
- **Consequence**:
  - ✅ Team familiar từ phase trước → ít learning curve, faster build trong 6 ngày W12
  - ✅ Provider AWS well-maintained, module registry phong phú
  - ✅ Plan output rõ ràng, dễ review trong PR
  - ⚠️ Verbose hơn CDK cho complex infra
  - ⚠️ Không có type-safe như CDK TypeScript
- **Alternatives considered**:
  - AWS CDK: pros: type-safe, higher abstraction. Cons: team không familiar, risk rework trong
    W12 build window ngắn.
  - CloudFormation: pros: native, no state management. Cons: verbose YAML, no plan preview,
    rollback phức tạp.

---

## ADR-006 - Fail-open fallback khi AI engine down

- **Status**: Accepted
- **Date**: 2026-06-22
- **Context**: TF4 hard requirement - khi serving endpoint down, phải fail-open fallback to
  static threshold thay vì silent failure. Engineer không được mù hoàn toàn.
- **Decision**: Circuit Breaker pattern. Khi AI engine `/v1/predict` return 503 × 3 lần liên tiếp
  trong 60s → circuit OPEN → fallback send static threshold alert đến Slack với note
  `"[FALLBACK] AI engine unavailable, static threshold triggered"`.
  Circuit reset sau 5 phút (half-open check).
- **Consequence**:
  - ✅ Engineer không bị mù khi AI engine down
  - ✅ False positive rate tăng tạm thời (static threshold kém chính xác hơn AI) - acceptable
  - ⚠️ Cần maintain 2 alert paths (AI path + static threshold path)
  - ⚠️ Static threshold thresholds phải được config explicit per service
- **Alternatives considered**:
  - Silent fail (no alert khi engine down): rejected - vi phạm TF4 hard requirement
  - Always-on static threshold parallel với AI: pros: no gap. Cons: alert noise doubled, defeats
    purpose của AI engine

---

<!-- Append ADR mới ở đây. Mỗi decision mới trong W11-W12 phải có ADR riêng.

Gợi ý topics cần ADR còn lại:
- ADR-007: CI/CD strategy (GitHub Actions vs CodePipeline)
- ADR-008: Observability stack (AMP native Grafana vs CloudWatch + Grafana plugin)
- ADR-009: Metric ingest path (CloudWatch agent vs OTel collector vs direct SDK push)
- ADR-010: Tenant isolation depth (pool vs silo for time-series data)
-->
