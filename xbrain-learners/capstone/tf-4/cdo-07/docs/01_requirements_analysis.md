# Requirements Analysis - Task Force 4 · CDO-07

## 1. Đề tài context

Hệ thống giám sát và dự báo chủ động **Foresight Lens** được thiết kế để giải quyết bài toán vận hành thực tế cho một khách hàng Fintech quy mô tầm trung. Hiện tại, doanh nghiệp đang phục vụ khoảng 3.5 triệu người dùng hoạt động (active users), với mức tải ngày thường đạt 2.8k Requests Per Second (RPS) và đạt đỉnh (peak traffic) lên tới 9k RPS trong các sự kiện lớn như Black Friday. Toàn bộ hệ thống core-banking và tài chính phụ trợ đang vận hành thông qua cụm hạ tầng gồm hơn 120 microservices production triển khai trên nền tảng AWS ECS Fargate, kết hợp với các CSDL RDS Aurora MySQL, DynamoDB và hệ thống hàng đợi SQS.

### Vấn đề cốt lõi của khách hàng
Trong vòng 3 tháng vừa qua, đội ngũ SRE (Site Reliability Engineering) của doanh nghiệp đã làm giảm uy tín thương hiệu khi vi phạm chỉ số SLO cam kết về độ sẵn sàng của hệ thống (Monthly Availability Target 99.9%) trong 7 lần liên tiếp. Đáng chú ý, nguyên nhân không xuất phát từ các sự cố sập nguồn thảm họa (catastrophic incidents), mà lại đến từ các lỗi cạn kiệt tài nguyên âm thầm (capacity exhaustion silent) diễn ra từ từ theo thời gian:
* CPU của các cụm cơ sở dữ liệu RDS Aurora MySQL tăng dần đều và neo giữ ở mức 100% suốt 90 phút trước khi làm nghẽn hoàn toàn kết nối (connection pool exhaustion).
* Lượng tin nhắn tồn đọng (backlog) trong hệ thống hàng đợi SQS tích tụ âm thầm lên gấp 6 lần khiến các ứng dụng tiêu thụ dữ liệu (consumers) rơi vào trạng thái timeout.
* Giới hạn kết nối (connection limit) trên Application Load Balancer (ALB) chạm ngưỡng trần mỗi khi có traffic spike vào cuối tuần.

Tất cả các sự cố trên đều bị phát hiện muộn sau khi có từ 18 đến 25 khiếu nại (support tickets) từ phía người dùng cuối phản hồi về bộ phận CS, thay vì được phát hiện chủ động từ hệ thống giám sát nội bộ. Khách hàng đã có sẵn các dashboard CloudWatch và DataDog, nhưng họ thiếu một giải pháp tự động hóa có khả năng học baseline động thay vì dựa vào các ngưỡng cấu hình tĩnh (static thresholds) dễ gây nhiễu alert (alert fatigue) hoặc bỏ sót các biến động chậm (slow drift).

### Mục tiêu của Foresight Lens
Xây dựng một hệ thống phân tích và dự báo chuỗi thời gian (time-series metrics) hoạt động liên tục 24/7 để:
1. Tự động thu thập và phân tích các chỉ số tài nguyên từ 3 dịch vụ Tier-1 cốt lõi.
2. Học tập hành vi bình thường (per-service baseline) theo chu kỳ tuần để nhận diện tính chất mùa vụ của ngành tài chính.
3. Chủ động phát tín hiệu cảnh báo (proactive ping) trước ít nhất 15 phút khi hệ thống có dấu hiệu drift hoặc sắp cạn kiệt tài nguyên (capacity exhaustion).
4. Đưa ra các khuyến nghị hành động cụ thể (Actionable Capacity Recommendation) có cấu trúc tường minh để kỹ sư SRE phê duyệt bằng tay (manual approval gate).

---

## 2. Infra non-functional requirements

Để hệ thống Foresight Lens hoạt động ổn định và đáp ứng các tiêu chuẩn khắt khe của một hệ thống tài chính, hạ tầng do nhóm CDO triển khai phải cam kết đạt được các chỉ số phi chức năng sau đây:

| Chỉ số NFR | Ngưỡng Mục tiêu (Target) | Khung Lý do & Ràng buộc Kỹ thuật (Justification) |
| :--- | :--- | :--- |
| **Multi-tenant scale** | ≥ 50 tenants | Hệ thống được thiết kế để đóng gói thành sản phẩm thương mại hóa (SaaS), cho phép quản lý và cô lập dữ liệu metric từ tối thiểu 50 tenant khách hàng khác nhau. |
| **SLO p99 latency** | < 1000ms | Áp dụng nghiêm ngặt cho điểm cuối API `/v1/predict`. Thời gian xử lý từ lúc nhận payload time-series window đến khi trả về kết quả dự báo không được quá 1 giây để bảo toàn thời gian xử lý sự cố. |
| **Availability** | ≥ 99.5% | Cam kết độ sẵn sàng ổn định cho toàn bộ pipeline ingestion và hệ thống lưu trữ dữ liệu giám sát cốt lõi, đảm bảo không làm đứt gãy luồng metric truyền về. |
| **Error rate** | < 0.5% | Tỷ lệ lỗi sinh ra trên đường truyền dẫn dữ liệu (drop metric, network error) phải được kiểm soát dưới 0.5% để tránh làm sai lệch tập dữ liệu đầu vào của mô hình AI. |
| **Cost per tenant/month** | ~$1.90 / tenant | Dựa trên mục tiêu phân bổ ngân sách tối ưu của dự án, tổng chi phí hạ tầng AWS duy trì ở mức ~$95/tháng. Với quy mô tối thiểu 50 tenants, chi phí trên mỗi tenant cực kỳ cạnh tranh. |
| **Onboarding SLA** | < 30 phút | Thời gian từ lúc một microservice mới được đăng ký vào hệ thống Foresight Lens cho đến khi hạ tầng lưu trữ và phân tách dữ liệu sẵn sàng tiếp nhận metric. |
| **Security baseline** | IAM least-privilege + audit 90 ngày | Toàn bộ các dịch vụ AWS cấu hình chặt chẽ qua IAM Roles, mã hóa dữ liệu tại chỗ (Encryption at rest) và lưu vết toàn bộ hoạt động truy cập thông qua CloudTrail để đáp ứng chuẩn SOC2. |

---

## 3. Differentiation Angle (KEY)

Sau khi nghiên cứu sâu sắc về bản chất bài toán và các rủi ro kỹ thuật liên quan đến độ trễ dữ liệu và chi phí, nhóm quyết định lựa chọn hướng kiến trúc làm điểm nhấn cạnh tranh độc quyền:

* **Angle lựa chọn:** **TSDB-Centric Hybrid Streaming (Kinesis Data Stream + Amazon Timestream)**.
* **Why this angle (Trục chiến thắng - Win Axis):** Khách hàng yêu cầu một hệ thống có khả năng đưa ra dự báo với **Lead time ≥ 15 phút** trước khi xảy ra vi phạm SLO. Để làm được điều này, dữ liệu đầu vào của AI Engine phải là dữ liệu "tươi nhất" (Real-time granularity) và giữ nguyên độ phân giải mịn trong suốt **90 ngày lưu trữ lịch sử**. 
  
  Nếu chọn hướng thiết kế Lakehouse (Option B), hệ thống sẽ bị dính độ trễ lớn do cơ chế gom lô (batching) của Kinesis Firehose và tiến trình lên lịch (schedule) của AWS Glue Job, dẫn đến nguy cơ cao bị trễ cửa sổ vàng 15 phút để cứu hệ thống. Nếu chọn hướng Managed-lite (Option C) sử dụng CloudWatch Custom Metrics, hệ thống sẽ rơi vào rủi ro tự động nén dữ liệu (down-sampling) sau 15 ngày, làm mất đi các chi tiết dịch chuyển chậm (slow drift) mà AI cần học. 
  
  Do đó, việc đưa **Amazon Timestream** làm hạt nhân lưu trữ kết hợp tầng đệm **Kinesis Data Stream** là lựa chọn tối ưu nhất. Kiến trúc này giúp ghi nhận dữ liệu thông suốt ở quy mô peak 50k events/sec, thực hiện truy vấn chuỗi thời gian (time-series query) tốc độ cao với độ trễ mili-giây, cung cấp dữ liệu thô toàn vẹn cho mô hình AI đưa ra kết quả dự báo chính xác nhất (đáp ứng tiêu chí bắt bắt được ≥ 80% drift của khách hàng).
* **Trade-off chấp nhận:** Để đổi lấy độ phân giải dữ liệu hoàn hảo và tốc độ truy vấn tức thời, nhóm chấp nhận độ phức tạp cao hơn trong việc quản lý và tối ưu hóa chi phí truy vấn (Query Scan Cost) trên Amazon Timestream nhằm giữ vững mục tiêu tổng chi phí không vượt quá mức circuit breaker $200/tháng.

---
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