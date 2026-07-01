# Requirements Analysis - Task Force 4 · CDO-07

## 1. Đề tài context

**Foresight Lens** là hệ thống giám sát và dự báo chủ động cho một khách hàng Fintech quy mô tầm trung. Khách hàng vận hành hơn 120 microservices trên AWS ECS Fargate, kết hợp RDS Aurora MySQL, DynamoDB, SQS và Application Load Balancer. Tải ngày thường khoảng 2.8k RPS và có thể tăng lên 9k RPS trong các sự kiện lớn như Black Friday.

### Vấn đề cốt lõi

Trong 3 tháng gần đây, đội SRE vi phạm SLO availability 99.9% nhiều lần do các sự cố capacity exhaustion diễn ra âm thầm: CPU database tăng dần đến 100%, SQS backlog tích tụ, ALB connection chạm ngưỡng trong traffic spike. Các sự cố thường chỉ được phát hiện sau khi người dùng gửi ticket, không phải từ cảnh báo chủ động.

Khách hàng đã có CloudWatch và DataDog dashboard, nhưng thiếu một hệ thống học baseline động để phát hiện slow drift sớm hơn static thresholds. Mục tiêu là giảm alert fatigue, phát hiện rủi ro trước khi tài nguyên cạn kiệt, và tạo khuyến nghị đủ rõ để SRE phê duyệt bằng tay.

### Mục tiêu của Foresight Lens

1. Thu thập và phân tích metric hạ tầng từ tối thiểu 3 dịch vụ Tier-1.
2. Học baseline theo service/tenant để nhận diện xu hướng vận hành bình thường.
3. Phát cảnh báo chủ động trước ít nhất 15 phút khi có drift hoặc capacity exhaustion risk.
4. Trả về Actionable Capacity Recommendation cho SRE/manual approval gate.
5. Mỗi Capacity Recommendation phải có đủ 5 thành phần: **[Action verb] + [Target] + [From → To] + [Confidence Score] + [Evidence Link]**.

Ví dụ recommendation hợp lệ: `Scale ECS service payment-gw from 2 tasks → 4 tasks; confidence=0.87; evidence=s3://.../audit.json hoặc Grafana dashboard URL`.

---

## 2. Infra non-functional requirements

| Chỉ số NFR | Target | Justification |
| :--- | :--- | :--- |
| **Multi-tenant scale** | ≥ 3 tenant | Hệ thống phải phân tách metric theo tenant để có thể đóng gói theo mô hình SaaS. |
| **SLO p99 latency** | < 1000ms | Áp dụng cho API `/v1/predict`, tính từ lúc nhận time-series payload đến khi trả kết quả dự báo. |
| **Availability** | ≥ 99.5% | Pipeline ingestion, storage và inference path phải đủ ổn định để không làm đứt luồng giám sát chính. |
| **Error rate** | < 0.5% | Drop metric, lỗi network hoặc lỗi xử lý phải thấp để tránh làm sai dữ liệu đầu vào của AI Engine. |
| **Cost per tenant/month** | ~$59.97/tenant | Tổng ngân sách mục tiêu khoảng $179 cho 3 tenant, nằm dưới budget cap $200/tháng. |
| **Onboarding SLA** | < 30 phút | Một service mới phải sẵn sàng gửi metric và được phân tách dữ liệu trong vòng 30 phút. |
| **Security baseline** | IAM least-privilege + encryption at rest + audit lifecycle | AWS services dùng IAM Roles tối thiểu quyền; dữ liệu được mã hóa bằng KMS/SSE; CloudWatch Logs có retention theo workload; S3 audit log có lifecycle Standard → IA sau 30 ngày, Deep Archive sau 90 ngày, expire sau 365 ngày. Mỗi lượt prediction/fallback phải sinh audit log encrypted at rest và có tối thiểu 6 fields: `timestamp`, `tenant_id`, `principal_id` hoặc caller identity, `correlation_id`/`request_id`, input reference hoặc payload hash, prediction/fallback result, recommendation/evidence reference. |
| **Fail-open fallback** | Static threshold fallback | Nếu `/v1/predict` timeout/down hoặc Window Feeder thất bại, hệ thống phải kích hoạt static-threshold fallback để vẫn publish alert và ghi audit log. Fallback không thay thế ML prediction, chỉ bảo đảm giám sát không im lặng hoàn toàn. |

---

## 3. Differentiation Angle (KEY)

* **Angle lựa chọn:** **TSDB-Centric Hybrid Streaming (Kinesis Data Streams + Timestream for InfluxDB)**.

Hướng kiến trúc này được chọn vì yêu cầu lead time ≥ 15 phút cần dữ liệu mới, có độ trễ thấp và có thể query theo cửa sổ thời gian ngắn cho AI Engine. Lakehouse trên S3/Glue/Athena phù hợp phân tích lịch sử nhưng có độ trễ batching/partitioning cao hơn. CloudWatch Custom Metrics đơn thuần có rủi ro chi phí/cardinality và không phải lõi dữ liệu tối ưu cho AI.

Thiết kế mục tiêu sử dụng Kinesis Data Streams làm ingestion buffer cho telemetry hạ tầng. Lambda Transformer đọc bản ghi từ Kinesis, kiểm tra schema, loại bỏ payload có PII và ghi telemetry sang **Timestream for InfluxDB** bằng InfluxDB Line Protocol. Window Feeder Lambda truy vấn dữ liệu bằng Flux theo cửa sổ thời gian cấu hình, bổ sung lookback để xử lý điểm thiếu, chuẩn hóa time grid, forward-fill khi phù hợp và gửi payload sang AI Engine `/v1/predict`.

### Cost profile

| Tiêu chí | Option A: TSDB-Centric | Option B: Lakehouse | Option C: Managed Observability |
| :--- | :--- | :--- | :--- |
| **Cơ chế phí chính** | Kinesis on-demand, Lambda processing, Timestream for InfluxDB instance/storage, Window Feeder Flux query. | Firehose/S3/Glue/Athena scan. | CloudWatch custom metrics theo số lượng metric/time-series. |
| **Fixed cost** | InfluxDB instance/storage, ECS/Fargate, ALB, Lambda, CloudWatch Logs. | Glue Job định kỳ và storage/query layer. | Tăng nhanh theo metric cardinality. |
| **Variable risk** | Telemetry throughput, Lambda invocations, query window/lookback quá rộng. | Athena scan phụ thuộc partition. | Chi phí tăng theo số service, tenant và dimension. |
| **Mitigation** | Kinesis on-demand, batch write InfluxDB, Flux query chỉ lấy cột cần thiết, giới hạn query window/lookback, budget circuit breaker $200/tháng cho inference workload. | Không dùng cho luồng dự báo chính vì latency. | Không dùng làm lõi AI vì cost/cardinality. |

### Trade-off chấp nhận

Nhóm chấp nhận tăng độ phức tạp vận hành ở ingestion, Lambda processing và Timestream for InfluxDB để đổi lấy khả năng thu thập metric gần thời gian thực và phục vụ AI Engine theo chu kỳ ngắn.

Thiết kế sử dụng **Timestream for InfluxDB** làm time-series store chính, vì vậy các giả định chi phí và vận hành tập trung vào InfluxDB instance/storage, write throughput và Flux query workload. Chi phí được kiểm soát bằng Kinesis on-demand, batch write sang InfluxDB, giới hạn query window/lookback và budget circuit breaker $200/tháng. Các mục tiêu model như **FP ≤ 12%** và **Catch ≥ 80% drift** là tiêu chí đánh giá ở tầng AI/model, không phải cấu hình hạ tầng hoặc tầng lưu trữ có thể áp đặt trực tiếp.

---

## 4. Constraints

- **AWS only** – Không triển khai multi-cloud.
- **Region** – `us-east-1` cho các môi trường `sandbox`, `staging`, `prod`.
- **Budget cap** – ≤ $200/tháng cho solution capstone.
- **Single-region deployment** – Không triển khai multi-region; DR chỉ ở mức thiết kế.
- **Auto-remediation** – Không nằm trong phạm vi dự án; hệ thống chỉ prediction, recommendation và alert.
- **Recommendation contract** – Mọi Capacity Recommendation phải có đủ 5 thành phần `[Action verb] + [Target] + [From → To] + [Confidence Score] + [Evidence Link]` trước khi gửi cho SRE/manual approval gate.
- **Fail-open behavior** – Khi AI Engine `/v1/predict` hoặc Window Feeder gặp sự cố, hệ thống phải kích hoạt static-threshold fallback để tiếp tục cảnh báo và audit.
- **Auto-retraining pipeline** – Không xây dựng trong capstone; chỉ mô tả trigger logic qua ADR.
- **Infrastructure metrics only** – Chỉ xử lý CPU, Memory, Queue Depth, Connections, Latency; không xử lý business metrics hoặc PII.
- **Synthetic workload only** – Không dùng production traffic; kiểm thử bằng k6/Locust và dữ liệu mô phỏng.
- **LLM-based prediction** – Không dùng do chi phí cao; tập trung statistical/ML-based forecasting.
- **Code freeze** – Đóng băng code vào 08:00 AM ngày 02/07/2026.

---

## 5. Open questions

- [ ] Q1: Tier-1 services nào sẽ được chọn làm baseline services trong capstone?
- [ ] Q2: Lead time 15 phút có áp dụng đồng đều cho tất cả service không?
- [ ] Q3: Baseline refresh chạy theo lịch cố định hay theo drift threshold?
- [ ] Q4: Capacity recommendation có cần approval workflow trước khi gửi SNS notification không?
- [ ] Q5: Service onboarding cần tối thiểu bao nhiêu ngày historical metrics để baseline đạt chất lượng chấp nhận được?
