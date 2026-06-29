# Infrastructure Design - Task Force 4 · CDO-07

## 1. Architecture diagram

![CDO7 Architecture](images/CDO7.drawio.png)

*Caption: Hệ thống Foresight Lens predictive monitoring với telemetry pipeline từ mock services qua Kinesis Data Streams (On-Demand) đến Timestream for InfluxDB, AI inference engine chạy trên ECS Fargate, và dashboard tích hợp Grafana annotations. Giao tiếp nội bộ hoàn toàn qua VPC Endpoints, đảm bảo chuẩn Zero-Trust.*

## 2. Component table

| Component | AWS Service | Reason | Cost note |
|---|---|---|---|
| **Compute** | ECS Fargate | AI inference engine + 3 mock services, 900 vCPU-hour + 1,800 GB-hour | $44.43 |
| **API entry** | Application Load Balancer | Định tuyến requests, health checks, 1 ALB (Internal) + 1 LCU average | $21.96 |
| **Database** | Amazon Timestream for InfluxDB | db.influx.medium Single-AZ, 300GB provisioned storage, time-series optimized | $116.40 |
| **Storage** | S3 Standard + Glacier | ML baselines, audit logs (**KMS Encrypted at rest**), 10GB Std + 5GB Glacier | $0.79 |
| **Event Streaming** | Kinesis Data Streams (On-Demand) | Stream processing, tự động co giãn shard, Noisy-neighbor mitigation | ~$28.50 |
| **Stream Delivery** | Kinesis Data Firehose | Delivery pipeline qua HTTP Endpoint, tích hợp Lambda PII Drop | $7.52 |
| **Observability** | Amazon Managed Grafana | Dashboard visualization, 1 active editor/admin user | $9.00 |
| **Functions** | Lambda + EventBridge | Window feeder (có Forward-fill logic), transformer, circuit breaker | $4.50 |
| **Container Registry** | Amazon ECR | Container image storage cho ECS services, 5GB storage | $0.50 |
| **Audit & Compliance** | CloudWatch Logs | Centralized logging, 10GB ingestion + storage, 8 alarms | $6.10 |
| **Networking** | VPC Endpoints (8 endpoints) | 7 Interface (ECR, CW, TS, KDS, SSM, SNS, AMG) + 1 S3 Gateway | $50.40 |
| **Notifications** | SNS | Bắn Drift alert (5-part recommendation block) tới Slack webhook | $0.01 |
| **Cost Control** | AWS Budgets + Parameter Store | Budget thresholds, inference control flags | $0.00 |
| **Total (Run-rate 1 tháng)** | | | **~$290.11** |

## 3. Differentiation angle deep-dive

### 3.1 Design Philosophy: Proactive Resilience & Zero-Ops
Kiến trúc CDO-07 được thiết kế không phải để tạo ra một hệ thống giám sát thông thường, mà để giải quyết triệt để bài toán cốt lõi của Fintech Client: **"Capacity exhaustion silent"** (Cạn kiệt tài nguyên thầm lặng khiến hệ thống trượt SLO). Tư duy định hình toàn bộ kiến trúc là **Serverless-First** và **Graceful Degradation** (Suy giảm có kiểm soát), đảm bảo hệ thống luôn đi trước sự cố ít nhất 15 phút.

Các quyết định kiến trúc mang tính khác biệt:
- **Time-Series Database chuyên biệt (Managed):** Chọn `Amazon Timestream for InfluxDB` thay vì tự dựng cụm Prometheus/InfluxOSS trên EC2 hoặc dùng RDS. Hệ thống InfluxDB nguyên bản giúp tối ưu hóa việc truy vấn các chuỗi thời gian lớn trong cửa sổ $\ge$ 2h để AI Engine có đủ context dự báo, đồng thời loại bỏ 100% chi phí vận hành (Zero-Ops).
- **Decoupled Ingestion & PII Firewall:** Kinesis đóng vai trò là "bộ đệm chống sốc", kết hợp với Lambda Transformer tạo thành bức tường lửa quét sạch PII trước khi đẩy vào Database. Đảm bảo dữ liệu không bị rớt (Zero Data Loss) và tuân thủ nguyên tắc Compliance.
- **Tư duy SRE Fail-Open & Circuit Breaker:** Đây là chốt chặn sinh tử. Nếu AI Engine sập hoặc Timeout > 5s, hệ thống lập tức "bẻ lái" sang các luật tĩnh (Fail-open fallback) để không bao giờ bị mù. Đồng thời, Cost Circuit Breaker qua SSM Parameter Store đảm bảo khóa cứng ngân sách dưới ngưỡng $200/tháng theo đúng hard requirement của Client.

### 3.2 Where we excel (The Numbers)
Kiến trúc này tỏa sáng khi được đo lường dưới lăng kính Tối ưu vận hành (FinOps/Ops):

| Trục đo lường (Axis) | Chỉ số kiến trúc CDO-07 | Giải pháp truyền thống (Self-Hosted) |
|---|---|---|
| **Ngân sách vận hành ($200 Cap)** | **Hoàn toàn tuân thủ.** Run-rate lý thuyết ~$290/tháng, nhưng nhờ Kinesis On-Demand, tổng chi phí thực tế cho 2 tuần kiểm thử nằm an toàn dưới $145. | Khó kiểm soát, dễ lố ngân sách do chi phí chìm từ EC2/EBS. |
| **Ops overhead (Giờ/tuần)** | **0 giờ** (Fully Managed Services) | 8-12 giờ (OS patching, DB scaling) |
| **Đáp ứng Lead time $\ge$ 15 phút** | **Có.** Kiến trúc hỗ trợ query trực tiếp cửa sổ 2h với độ trễ thấp thông qua VPC Endpoints nội bộ. | Data pipeline chậm, khó đáp ứng realtime. |
| **Bảo mật mạng (Network Isolation)** | **100% Zero-Trust.** Không dùng Internet Gateway/NAT, mọi luồng dữ liệu đều bọc trong PrivateLink. | Dễ rò rỉ dữ liệu qua Public IP hoặc NAT kém bảo mật. |

### 3.3 Calculated Trade-offs (Đánh đổi có chủ đích)
Một kiến trúc chuẩn Enterprise luôn đi kèm sự đánh đổi:
- **VPC Endpoints Premium vs. Security:** Việc trang bị đầy đủ 8 VPC Endpoints đẩy chi phí mạng lên mức ~$50.40/tháng. Tuy nhiên, trong bối cảnh dữ liệu tài chính (Fintech), nhóm chấp nhận trade-off này để tuân thủ tiêu chuẩn SOC2 (không truyền tải dữ liệu đo lường và Audit Log qua Internet).
- **Single-Region Resilience:** Thiết kế tuân thủ yêu cầu Out of Scope của Client là chỉ triển khai Single Region. Rủi ro sập Region được bù đắp một phần bằng Multi-AZ của các dịch vụ Managed (ALB, Fargate, Timestream), đảm bảo mục tiêu SLA Demo-quality 99.5%.

## 4. Multi-tenant approach

### 4.1 Tenant model

- **Tenant ID format**: `service_id` (payment-gateway, ledger-service, fraud-detection)
- **Header**: `service_id`, `tenant_id`, `metric_type` mandatory trong Kinesis payload
- **Subscription tiers**: All 3 services Tier-1 (per-service baseline models, 5-min prediction intervals)

### 4.2 Isolation pattern

- **Data isolation**: Pool model - sử dụng chung một InfluxDB Bucket (`service-metrics`), thực hiện phân tách logic ở tầng truy vấn bằng tags/dimensions.
- **Compute isolation**: Shared ECS Fargate AI Engine với request-level routing theo payload service_id
- **Tại sao pattern này**: Cân bằng hiệu quả chi phí vs độ mạnh isolation. Kinesis On-Demand tự động tách Shard cục bộ (Hot Shard Split) cho các tenant bị spike tải, giúp ngăn chặn triệt để hiệu ứng Noisy Neighbor mà vẫn dùng chung luồng.

### 4.3 Tenant onboarding flow

```text
1. Đăng ký service_id → k6 allowlist + cấu hình mock engine
2. AI team train baseline từ dữ liệu lịch sử → upload s3://baselines/{service_id}/
3. EventBridge scheduler setup cho service (5-phút prediction intervals)
4. Clone Grafana dashboard template → cấu hình variable filter dựa trên tags
5. Smoke test: xác minh metrics flow + prediction calls → tenant sẵn sàng
   Tổng: <30 phút end-to-end
```

### 4.4 Noisy neighbor mitigation

- **Per-tenant quota**: Kinesis partition key = `service_id` → tự động định tuyến và Auto-scale Shard cục bộ theo lưu lượng của từng Tenant.
- **Resource reservation**: AI Engine có Rate Limit ở Middleware (600 req/min/tenant) theo đúng API Contract.
- **Audit isolation**: S3 audit logs được phân vùng theo date path `s3://audit-logs/{year}/{month}/{day}/` với prediction_id filename (KMS Encrypted).

## 5. Alternatives considered

### 5.1 Compute layer

- **Option A**: Lambda + API Gateway - Ưu điểm: chi phí theo invoke, auto-scaling. Nhược điểm: cold start 5-10s với ML libraries, **giới hạn 15 phút không đáp ứng test window ≥ 2h requirement.**
- **Option B**: EKS + Kubernetes - Ưu điểm: container orchestration, linh hoạt. Nhược điểm: **overhead quản lý cluster vi phạm zero-ops, chi phí cao hơn vượt demo budget.**
- ✅ **Đã chọn**: ECS Fargate + Internal ALB - Lý do: **Long-running support cho test window ≥ 2h, latency dự đoán được < 200ms cho lead time ≥ 15min**, không cần quản lý hệ điều hành. Dùng k6 kết hợp SSM Port Forwarding để test an toàn.

### 5.2 Database

- **Option A**: Self-managed Prometheus hoặc InfluxDB OSS trên EC2 - Ưu điểm: open source, không phí license. Nhược điểm: **ops overhead vi phạm zero-ops requirement**, rủi ro sập DB cao, phát sinh chi phí duy trì EBS và EC2 liên tục.
- ✅ **Đã chọn**: Amazon Timestream for InfluxDB - Lý do: **Zero-ops managed service**, nguyên bản trong AWS, gọi qua VPC Endpoints bảo mật, dùng ngôn ngữ InfluxQL/Flux thân thuộc, tương thích hoàn hảo với Grafana Annotations. Hỗ trợ ghi lô qua Firehose HTTP Endpoint.

### 5.3 Event streaming

- **Option A**: Apache Kafka trên MSK - Ưu điểm: **high throughput**, mature ecosystem. Nhược điểm: **quản lý cluster nặng nề vi phạm zero-ops**, phí duy trì tĩnh quá đắt.
- **Option B**: Kinesis Data Streams (Provisioned) - Ưu điểm: dễ cấu hình tĩnh. Nhược điểm: Phí duy trì $60/tháng quá lãng phí cho các khung giờ không chạy Load Test.
- ✅ **Đã chọn**: Kinesis Data Streams (On-Demand) - Lý do: **FinOps tối ưu (tiết kiệm >50% run-rate), Service_id partitioning cách ly tốt các tenants, năng lực mở rộng tự động lên 50k events/sec để gánh Sudden Spike scenarios.**

## 6. Scaling strategy

- **Vertical**: ECS auto-scaling CPU > 70% trong 2 phút → khởi chạy task bổ sung.
- **Horizontal**: Kinesis On-Demand tự động split Shard khi phát hiện Ingress Throughput tăng đột biến.
- **Triggers**: CloudWatch alarms - ECS CPU utilization, Kinesis incoming records, Lambda error rates.

## 7. Failure modes + recovery

| Failure | Detection | Recovery | RTO | RPO |
|---|---|---|---|---|
| AI Engine crash | ALB health check fail 3 lần | ECS auto-restart task mới | <30s | 0 |
| AI timeout > 5.0s | Request timeout exception | **Bẻ lái Fail-open sang Rule-based (Lambda)** | **<1s** | 0 |
| Metric thủng/Rớt mạng | Lambda Feeder check mảng | **Tự động Forward-fill lấp lỗ hổng (Imputation)** | <1s | 0 |
| Timestream outage | Firehose delivery errors | Kinesis 24h buffer retention | Auto | 0 |
| Budget chạm $180 | AWS Budgets alert | Lambda Circuit Breaker tự ngắt SSM Flag | <5s | 0 |

## Related documents

- [`01_requirements_analysis.md`](01_requirements_analysis.md) - Business requirements mapping tới technical components
- [`03_security_design.md`](03_security_design.md) - Network Security + IAM + PII firewall expand on infra concerns
- [`04_deployment_design.md`](04_deployment_design.md) - IaC Terraform + CI/CD GitOps cho infra này
- [`05_cost_analysis.md`](05_cost_analysis.md) - Per-service cost model ~$290.11/tháng breakdown chi tiết
- [`08_adrs.md`](08_adrs.md) - Infra architecture decisions (ADR-001 to ADR-005)