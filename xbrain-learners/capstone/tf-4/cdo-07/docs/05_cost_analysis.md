# Cost Analysis - Task force 4 · CDO 07

## 1. Cost model per tenant (forecast)

Dựa trên thiết kế kiến trúc hiện tại (Event-Driven + Kinesis + Timestream for InfluxDB trên ECS Fargate), hệ thống phục vụ chính xác 3 tenants (`payment-gateway`, `ledger-service`, `fraud-detection`).

| Component | Unit cost (Total) | Tenant avg usage | $/tenant/month (N=3) |
| --- | --- | --- | --- |
| **Compute** (ECS Fargate - AI Engine + 3 mock services) | $44.43/tháng | Shared compute pool: AI Engine (flat-rate ~$36.00/tháng cho 2 tasks 24/7) + 3 mock services (workload-dependent) | $14.81 |
| **Database** (Amazon Timestream for InfluxDB) | $116.40/tháng | Instance `db.influx.medium` Single-AZ, 300GB magnetic store, 10M metrics | $38.80 |
| **Storage** (S3 Standard + Glacier - baseline + audit) | $0.79/tháng | Phân vùng theo `{service_id}` cho ML baselines, 10GB + 5GB archive | $0.26 |
| **Event Ingestion & Streaming** (Kinesis Data Streams + Firehose) | $36.02/tháng | Kinesis Data Streams On-Demand (~$28.50) + Firehose Delivery pipeline (~$7.52) | $12.01 |
| **Data transfer** | $0.00/tháng | Toàn bộ traffic nội bộ đi qua VPC Endpoints thay vì NAT Gateway | $0.00 |
| **AI inference** | $0.00/tháng | Chạy engine thống kê `tf4-ewma-stl-v1` locally trên Fargate, token cost = $0 | $0.00 |
| **Observability** (Managed Grafana + CloudWatch Logs) | $15.10/tháng | Grafana Dashboard ($9.00) + CloudWatch Log Ingestion/Storage ($6.10) | $5.03 |
| **Shared Core Infra** (ALB, EventBridge+Lambda, VPC Endpoints x8, ECR, SNS, Budgets) | $77.37/tháng | ALB ($21.96) + 8 VPC Endpoints ($50.40) + Lambda/EventBridge ($4.50) + ECR ($0.50) + SNS/Budgets ($0.01) | $25.79 |
| **Total / tenant / month** | **$290.11** | | **$96.70** |

### 1.1 Architecture Insights: Phân tích Cost Model

Mức chi phí **$96.70/tenant/tháng** (tương đương run-rate **$290.11/tháng** cho toàn hệ thống) được định hình bởi các quyết định kiến trúc cốt lõi nhằm đáp ứng yêu cầu khắt khe của Fintech Client về độ trễ, tính cách ly và bảo mật:

*   **Amazon Timestream for InfluxDB ($116.40/tháng - chiếm ~40%)**: Đây là chi phí cố định (fixed cost) lớn nhất cho instance `db.influx.medium` Single-AZ. Mặc dù chi phí cao, InfluxDB cung cấp năng lực lưu trữ time-series tối ưu và hỗ trợ ngôn ngữ Flux/InfluxQL để Window Feeder Lambda thực hiện các phép tính trượt thời gian $\ge 2$ giờ và forward-fill lấp lỗ hổng dữ liệu gần như realtime, tránh ops overhead tự vận hành.
*   **VPC Endpoints ($50.40/tháng - chiếm ~17%)**: Việc triển khai 8 VPC Endpoints (Interface Endpoints cho KDS, InfluxDB, CW, SSM, SNS, ECR, AMG và S3 Gateway Endpoint) là sự đánh đổi có chủ đích (Calculated Trade-off) để đạt bảo mật tuyệt đối SOC2/Zero-Trust, chặn toàn bộ phí Data Processing đắt đỏ của NAT Gateway.
*   **Compute ($44.43/tháng - chiếm ~15%)**: Bao gồm ECS Fargate chạy AI Engine `tf4-ewma-stl-v1` và 3 mock services. Theo đặc tả AI Engine (`03_ai_engine_spec.md`), AI serving chạy flat-rate 2 tasks 24/7 để tránh cold start của Lambda và duy trì liên tục trạng thái Circuit Breaker, tiêu tốn khoảng ~$36.00/tháng cố định.
*   **Kinesis Data Streams On-Demand ($28.50) & Firehose ($7.52)**: Đảm bảo khả năng hấp thụ và xử lý streaming lưu lượng dữ liệu đột biến (Sudden Spike) mà không bị mất dữ liệu, đồng thời tự động co giãn theo dung lượng thực.

< TODO W12: Thu thập actual usage (Kinesis records, InfluxDB write/query volume, ECS task scaling thực tế) từ 3 tenant trong quá trình test để tính toán marginal cost phát sinh khi có tenant thứ 4. >

## 2. Cost at scale (Economies of Scale)

Bảng dưới đây minh họa sự tối ưu hóa chi phí khi hệ thống scale từ 3 lên 200 tenants. Do phần lớn các chi phí cố định nền tảng (Timestream InfluxDB instance, VPC Endpoints, ALB, AI Engine base tasks) được khấu hao (amortize), chi phí trung bình trên mỗi tenant giảm mạnh khi quy mô tăng.

*   **Fixed Base Cost (Cố định)**: ~$241.16/tháng (InfluxDB DB, VPC Endpoints, ALB, AI serving tasks, Grafana workspace).
*   **Variable Cost per Tenant (Biến phí/Tenant)**: ~$15.08/tháng (Mock services compute, Kinesis ingestion, Firehose processing, S3 logs).

| Tenant count | Monthly total cost | Avg per-tenant | Ghi chú kiến trúc |
| --- | --- | --- | --- |
| **3 (Current)** | **$290.11** | **$96.70** | Bị chi phối mạnh bởi fixed base infra (InfluxDB instance, ALB, VPC Endpoints). |
| 10 | ~$392.00 | $39.20 | Chi phí cố định bắt đầu được khấu hao; Kinesis & Firehose tăng nhẹ. |
| 50 | ~$995.00 | $19.90 | Đạt điểm hiệu quả chi phí cao; Mock services auto-scale và Kinesis tự phân shard. |
| 200 | ~$3,257.00 | $16.29 | Tiệm cận target NFR ban đầu; cần giám sát giới hạn dung lượng và hiệu năng truy vấn của InfluxDB. |

< TODO W12: Nếu biến phí Kinesis throughput / InfluxDB storage tăng đáng kể khi N tăng qua các bài stress test, cần cập nhật lại forecast cho N=50 và N=200 >

## 3. Cost optimization applied

☑ **S3 lifecycle tiering:** Standard → Glacier cho ML baselines + Audit Logs ($0.79/tháng).
☑ **VPC Endpoints thay thế NAT Gateway:** Chặn đứng hoàn toàn chi phí xử lý dữ liệu qua NAT (NAT Data Processing), chấp nhận base fee cố định $50.40/tháng để bảo mật tuyệt đối.
☑ **Kinesis Data Streams On-Demand:** Tối ưu hóa chi phí hơn 50% so với mode Provisioned tĩnh trong môi trường test/demo.
☑ **In-house Statistical AI Engine ($0 Token Cost):** Nhóm AI lựa chọn thuật toán thống kê EWMA & STL (NumPy-based) chạy offline cục bộ trên Fargate, loại bỏ hoàn toàn chi phí token khổng lồ của LLM API.
☑ **Log retention tiering:** CloudWatch Logs giới hạn dung lượng lưu trữ cho audit và application logs.

## 4. Measured actual (Pack #2 only - fill in W12)

### 4.1 2-week capstone spend

*Dự báo chi phí chạy thử nghiệm 2 tuần của capstone là **$145.06** (bằng 50% run-rate tháng).*

| Service | Forecast | Actual | Delta |
| --- | --- | --- | --- |
| Compute (ECS Fargate - AI Engine + Mock services) | $22.22 | $X | ±X% |
| Database (Amazon Timestream for InfluxDB) | $58.20 | $X | ±X% |
| Storage (S3) | $0.40 | $X | ±X% |
| Networking (ALB + VPC Endpoints) | $36.18 | $X | ±X% |
| Observability (Managed Grafana + CW Logs) | $7.55 | $X | ±X% |
| Streaming & Functions (KDS + Firehose + Lambda + ECR + SNS) | $20.51 | $X | ±X% |
| **Total** | **$145.06** | **$X** | **±X%** |

### 4.2 Per-tenant actual

| Tenant test | Service mix | $/day | Extrapolate $/month |
| --- | --- | --- | --- |
| **Tenant-1** | `payment-gateway` | $X | $X |
| **Tenant-2** | `ledger-service` | $X | $X |
| **Tenant-3** | `fraud-detection` | $X | $X |

### 4.3 Cost-per-correct-decision (joint with AI eval)

| Metric | Value |
| --- | --- |
| Total AI calls in capstone | N |
| Correct decisions | M |
| Total AI inference cost (ECS Fargate AI Engine fraction) | $36.00 (Flat-rate 2 tasks 24/7) |
| **Cost per correct decision** | **$36.00 / M** |

## 5. Cost guardrails (Risk Warning)

*   **Nguy cơ cấu trúc (Architectural Risk)**: Hệ thống đang đặt AWS Budgets alert ở mức **$180** cho kỳ capstone 2 tuần. Với chi phí dự phóng thực tế là **$145.06** (80.6% budget utilization), buffer an toàn còn lại là **$34.94** (~24.1%).
*   **Hành động phòng thủ**: Cost circuit breaker qua SSM Parameter Store (công tắc `InferenceEnabled`) sẽ tự động chuyển sang chế độ `False` qua Lambda trigger khi chi phí chạm ngưỡng $180, chuyển hướng luồng dữ liệu sang Fail-open static thresholds để ngăn chặn bill spike.
*   **Per-tenant quota enforced via**: API Gateway usage plans / rate-limit middleware giới hạn 600 req/min/tenant; EventBridge rule throttling; và Kinesis shard partition key theo `service_id`.

## 6. Cost recommendations for production

*   **Fargate Compute Savings Plan**: Đăng ký gói Cam kết 1-3 năm sẽ giúp giảm tới 20-50% chi phí chạy AI Engine tasks và mock services.
*   **Timestream for InfluxDB Reserved Instances**: Lựa chọn Single-AZ hoặc sizing nhỏ hơn khi go-live, mua RI để giảm chi phí instance cố định ($116.40/tháng).
*   **VPC Endpoints (Gateway vs Interface)**: Chuyển đổi VPC Endpoint cho S3 sang dạng Gateway (miễn phí) thay vì Interface để tiết kiệm chi phí theo giờ.
*   **ADOT / Metric Collection optimization**: Hạn chế high-cardinality labels trong time-series data để tránh phình dung lượng InfluxDB.

## Related documents

*   [`02_infra_design.md`](02_infra_design.md) - Chi tiết hạ tầng Kinesis + Timestream for InfluxDB với run-rate $290.11/tháng.
*   [`08_adrs.md`](08_adrs.md) - Hồ sơ lưu trữ ADR-000 đến ADR-005 mô tả lý do chuyển dịch kiến trúc.
*   [`../../ai/docs/03_ai_engine_spec.md`](../../ai/docs/03_ai_engine_spec.md) - Đặc tả mô hình AI `tf4-ewma-stl-v1` và chi phí compute AI ($36/tháng).
*   [`07_test_eval_report.md`](07_test_eval_report.md) - Kết quả load test kiểm chứng hiệu năng và lượng dữ liệu ghi nhận thực tế.