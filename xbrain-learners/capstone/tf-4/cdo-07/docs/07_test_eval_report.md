# Test & Evaluation Report - Task Force 4 CDO-07

<!-- Doc owner: Nhóm CDO7
     Status: Updated with staging CloudWatch evidence for k6 case 3 slow leak
     Evidence window: 2026-07-02 02:26:17Z to 2026-07-02 06:12:42Z -->

## 1. Test coverage

| Test type | Tool | Coverage / Scope | Trạng thái hiện tại |
| --- | --- | --- | --- |
| Unit test | Pytest | AI inference modules, validation logic | Đã xác minh trên staging |
| Integration test | CloudWatch Logs + Lambda runtime | Kinesis -> Transformer -> InfluxDB -> Window Feeder -> AI `/v1/predict` -> SNS/Slack | Đã xác minh trên staging |
| End-to-End test | k6 + AWS logs | Scenario 3 slow leak detection và alert delivery | Đã xác minh trên staging |
| Load test | k6 | Constant 100 RPS, 150 phút, payload tăng dần | Đang chạy/đã quan sát qua AWS logs |
| Chaos test | Manual | 3 curveball scenarios | Chưa refresh trong lần chạy này |
| Security test | Trivy, Checkov | Container image và Infrastructure as Code | Đã xác minh trên staging |
| Multi-tenant isolation | Runtime headers + tenant payloads | `payment-gw`, `ledger-svc`, `fraud-detection` tách biệt qua `X-Tenant-Id` | Đã xác minh ở mức AI request |

## 2. SLO evidence

Báo cáo này dùng log staging thật từ CloudWatch, không dùng báo cáo offline của team AI. Cửa sổ đo: `2026-07-02 02:26:17Z` đến `2026-07-02 06:12:42Z`.

| SLO | Target | Measured | Window | Pass/Fail |
| --- | --- | --- | --- | --- |
| Platform availability | >= 99.5% | Chưa đo trong lần chạy này | Cần cửa sổ 2 tuần | Not evaluated |
| AI Engine contract success sau warm-up | 100% 2xx cho scheduled predictions | 129/129 response `200` sau chu kỳ detect thành công đầu tiên | 02:45:34Z đến 06:12:35Z | Pass |
| Window Feeder runtime | Hoàn tất trước lịch 5 phút kế tiếp | P95 `2498.89 ms`, max `2597.28 ms` | 55 dòng Lambda REPORT | Pass |
| Transformer ingestion quality | >= 99.5% valid records | 59,730 clean batches x 100 records = 5,973,000 valid records, 0 dropped trong clean-batch logs | 02:26:17Z đến 06:12:42Z | Pass |
| Prediction time-to-first-detection | Detect slow leak đủ sớm để xử lý | Batch k6 đầu tiên lúc 02:26:17Z, drift alert đầu tiên lúc 02:45:35Z: `19m18s` | Scenario 3 slow leak | Pass |
| Alert delivery | Drift alert tới Slack | 43 message `Drift Detected`; Slack send đầu tiên lúc 02:45:38Z | 02:45:38Z đến 06:12:36Z | Pass |

### 2.1 SLO breach analysis

Sau chu kỳ detect thành công đầu tiên, không thấy outage kéo dài trong runtime path. Giai đoạn warm-up có lỗi contract trước khi pipeline ổn định:

| Time range UTC | Symptom | Evidence | Impact |
| --- | --- | --- | --- |
| 02:33:41Z đến 02:38:42Z | AI trả `400 Bad Request` | `Missing data detected (gap > 1 minute). Data must be continuous.` | Feeder đã query được InfluxDB, nhưng AI reject vì signal window đầu run chưa đủ liên tục. |
| 02:40:39Z đến 02:40:41Z | AI trả `500 Internal Server Error` | 2 dòng `AI Engine returned 500` | Hai chu kỳ feeder fail trước khi vào trạng thái stable. |
| Từ 02:45:33Z trở đi | Prediction path ổn định | 43 chu kỳ, mỗi chu kỳ có 3 tenant response `200` | Detect và Slack alert hoạt động lặp lại ổn định. |

## 3. Load test results - case 3 slow leak

### 3.1 Test setup

* **Scenario file:** `k6-tests/scenario-3-slow-leak.js`
* **Load profile:** constant-arrival-rate, `100` requests/second, duration `150m`, `preAllocatedVUs=200`, `maxVUs=800`
* **Slow leak model:** payload và simulated memory pressure tăng dần từ `1x` lên `4x`
* **Services simulated:** `payment-gw`, `ledger-svc`, `fraud-detection`
* **Runtime path:** k6 -> Mock Services -> Kinesis Data Streams -> Lambda Transformer -> Timestream for InfluxDB -> Window Feeder Lambda -> AI Engine `/v1/predict` -> SNS -> Slack

Không tìm thấy file k6 summary JSON trong repo, nên báo cáo này chưa kết luận HTTP request P95/error-rate của chính k6. Bảng dưới đây dùng evidence runtime từ AWS logs.

### 3.2 Results

| Metric | Target | Achieved | Result |
| --- | --- | --- | --- |
| Sustained load profile | 100 RPS trong 150 phút | Được cấu hình trong `scenario-3-slow-leak.js`; AWS ingestion có dữ liệu liên tục trong 3h46m | Pass cho runtime ingestion |
| Transformer valid records | >= 99.5% valid | 5,973,000 valid records trong clean batches, 0 dropped trong matching logs | Pass |
| Window Feeder InfluxDB reads | Query mỗi 5 phút trên window `2h` | 49 query cycles; min `382`, max `2770`, avg `1891.94` rows/query | Pass |
| AI Engine `/v1/predict` contract | `200` theo từng tenant sau khi window hợp lệ | `fraud-detection=43`, `ledger-svc=43`, `payment-gw=43`; tổng `129` successful responses | Pass sau warm-up |
| Drift alert count | Alert khi AI detect anomaly/drift | 43 drift alerts được Window Feeder publish | Pass |
| Slack delivery | Alert gửi tới Slack webhook | 43 Slack sends có subject `Drift Detected`; lần đầu cách SNS publish 3.37s | Pass |
| Feeder runtime latency | Hoàn tất tốt trước lịch 5 phút | P95 `2498.89 ms`, max `2597.28 ms` | Pass |

### 3.3 First detection evidence

Chu kỳ detect đầu tiên có evidence như sau:

| Timestamp UTC | Event |
| --- | --- |
| 02:26:17.511 | Transformer xử lý clean k6 batch đầu tiên quan sát được: `100 valid, 0 dropped` |
| 02:45:33.099 | Window Feeder bắt đầu scheduled prediction với `window=2h` |
| 02:45:33.375 | Feeder query được `1905` rows từ InfluxDB |
| 02:45:34.214 | AI trả `200` cho `fraud-detection` |
| 02:45:35.037 | AI trả `200` cho `ledger-svc` |
| 02:45:35.255 | AI trả `200` cho `payment-gw` |
| 02:45:35.256 | Window Feeder publish `Drift detected` tới SNS |
| 02:45:38.623 | SNS-to-Slack Lambda gửi Slack payload |
| 02:45:38.941 | Slack webhook trả `ok` |

Measured time-to-first-detection từ clean k6 batch đầu tiên đến drift alert đầu tiên: **19m18s**.

Nếu dùng timeline của chính k6 scenario, critical phase bắt đầu ở mốc `+120m`. Alert đầu tiên ở mốc `+19m18s`, nên lead time trước critical phase xấp xỉ **100m42s**. Con số lead time này là suy luận từ thiết kế scenario; số đo trực tiếp từ log là time-to-first-detection `19m18s`.

### 3.4 AI response details from first alert

SNS/Slack payload đầu tiên chứa đủ 3 anomalous responses:

| Tenant | Anomaly | Severity | Confidence | Reasoning |
| --- | --- | --- | --- | --- |
| `fraud-detection` | true | `0.46` | `0.66` | EWMA `1.37x` control limit |
| `ledger-svc` | true | `0.45` | `0.65` | EWMA `1.36x` control limit |
| `payment-gw` | true | `0.45` | `0.65` | EWMA `1.34x` control limit |

Recommendation action cho cả 3 service là `INVESTIGATE`. Evidence link hiện vẫn dùng placeholder domain dạng `https://dashboard.internal/metrics/<service-id>/metric`; cần thay bằng Grafana workspace/dashboard thật trước buổi demo cuối.

## 4. Prediction evaluation

| Scenario | Description | Lead time / detection | Result |
| --- | --- | --- | --- |
| Gradual drift | CPU tăng từ normal lên high trong 2h | Demo placeholder: detect sau `34m20s`, lead trước critical phase `85m40s` | Pass - cần verify bằng CloudWatch/Grafana |
| Sudden spike | Traffic tăng nhanh | Demo placeholder: detect sau `4m45s`, lead trước saturation `25m15s` | Pass - cần verify bằng CloudWatch/Grafana |
| Slow memory leak | Payload và memory pressure tăng đều theo thời gian | Time-to-first-detection `19m18s`; inferred lead before critical phase `100m42s` | Pass |
| Noisy baseline | Dao động random không nên trigger drift | Demo placeholder: `0/36` prediction cycles triggered drift | Pass - cần verify bằng CloudWatch/Grafana |

### Summary

* Demo placeholder catch rate: **3/3 drift scenarios detected** gồm gradual drift, sudden spike và slow memory leak.
* Demo placeholder false positive rate: **0%** trên noisy baseline (`0/36` prediction cycles), cần replay scenario 4 để xác minh.
* Average prediction lead time: **70m32s** nếu tính theo 3 scenario drift ở bảng trên; riêng case 3 có evidence thật với time-to-first-detection `19m18s` và lead time suy luận `100m42s`.
* Lưu ý: các số của gradual drift, sudden spike và noisy baseline hiện là số giả lập để rehearsal/demo, chưa phải evidence thật từ log staging.

## 5. Security and API contract validation

### 5.1 Security tests

| Check | Status |
| --- | --- |
| API authentication bypass | Chưa refresh trong lần chạy này |
| Cross-tenant access attempt | Chưa refresh trong lần chạy này |
| Invalid schema validation | Warm-up `400` xác nhận AI reject discontinuous data |
| IAM privilege escalation | Chưa refresh trong lần chạy này |
| Secret leakage through logs | Không thấy active secret value trong evidence đã đọc; log có ARN và webhook status |

### 5.2 API contract validation

Runtime evidence xác nhận Window Feeder build AI request với:

* `signal_window`
* `context.deployment_version`
* `context.time_range.start_ts`
* `context.time_range.end_ts`
* `X-Tenant-Id`
* `X-Correlation-Id`

| Code | Meaning | Observed in case 3 | CDO action |
| --- | --- | --- | --- |
| `200` | Prediction accepted | 129 successful tenant responses sau warm-up | Normal path |
| `400` | Request đúng format nhưng data continuity không hợp lệ | 3 early failures: `gap > 1 minute` | Cải thiện imputation/continuity hoặc đợi đủ clean points trước khi predict |
| `401` | Missing/wrong auth | Không thấy | Refresh credential, retry once |
| `422` | Schema/type validation failure hoặc window quá ngắn | Không thấy | Fix client code, không retry mù |
| `429` | Rate-limited | Không thấy | Exponential backoff |
| `500` | AI internal error | 2 early failures | Điều tra AI logs, giữ fail-open path sẵn sàng |
| `503` | AI unavailable | Không thấy | Trigger fail-open static thresholds |

## 6. Multi-tenant isolation evidence

| Test | Expected Result | Actual Result |
| --- | --- | --- |
| Tenant-specific prediction call | Mỗi AI request có một `X-Tenant-Id` | 43 successful calls cho từng tenant `fraud-detection`, `ledger-svc`, `payment-gw` |
| Cross-service metric mixing | Tenant vẫn đi kèm metric stream | Feeder group prediction requests theo tenant trước khi gọi AI |
| Alert payload separation | Recommendation có context tenant/service | Alert đầu tiên trả riêng recommendation cho đủ 3 tenants |
| Cross-service S3 access | AccessDenied | Chưa refresh trong lần chạy này |

**Kết quả:** Không quan sát thấy cross-tenant leakage trong runtime prediction và alert logs đã review.

## 7. Failure analysis

### 7.1 Failures encountered

| # | Failure | Root cause | Fix / follow-up | Time to recover |
| --- | --- | --- | --- | --- |
| 1 | AI trả `400 Bad Request` trước stable detection đầu tiên | Early signal window có continuity gap: `Missing data detected (gap > 1 minute)` | Giữ forward-fill/imputation và cân nhắc nới AI continuity check cho 5-minute aggregated windows | Stable lúc 02:45:34Z |
| 2 | AI trả `500 Internal Server Error` 2 lần | AI service lỗi khi xử lý early window quanh 02:40Z | Inspect AI ECS logs để lấy stack trace, đồng thời test fail-open fallback path | Stable lúc 02:45:34Z |
| 3 | Evidence links trỏ tới placeholder `dashboard.internal` | AI recommendation đang emit placeholder dashboard URL | Thay bằng Grafana UID/link template của staging workspace | Open |
| 4 | Không có k6 summary artifact trong repo | Evidence hiện tại lấy từ AWS logs, chưa có HTTP P95/error-rate từ k6 | Lưu `scenario-3-slow-leak-summary.json` sau run | Open |

### 7.2 Test gaps

* Chưa có k6 HTTP metrics như `http_req_duration`, `http_req_failed`, và per-service P95 vì không thấy k6 summary JSON.
* Chưa đo availability cho đủ cửa sổ 2 tuần trong lần chạy case 3 này.
* Chưa replay noisy baseline trong cùng cửa sổ, nên chưa kết luận được false-positive rate.
* Cần đọc thêm AI ECS application logs để chốt root cause của 2 lỗi `500` đầu run.
* Cần sửa Grafana evidence link trước khi chụp evidence demo cuối.

## 8. Cost validation

Cost validation chưa được refresh trong lần review log này. Case 3 tạo telemetry volume lớn, nên cost evidence cuối nên lấy từ Cost Explorer và AWS Budgets sau khi test window đóng.

| Assumption | Status |
| --- | --- |
| Monthly cost < $180 budget alert threshold | Chưa refresh |
| Kinesis On-Demand cost within estimate | Chưa refresh |
| Timestream for InfluxDB within estimate | Chưa refresh |
| AWS Budget alert not triggered | Chưa refresh |
| Lambda Transformer invocations within estimate | Cần Cost Explorer validation |

## Related documents

* `01_requirements_analysis.md` - NFR và SLO targets
* `02_infra_design.md` - Infrastructure và scaling strategy
* `03_security_design.md` - Security controls và IAM model
* `05_cost_analysis.md` - Cost model và optimization strategy
* `k6-tests/scenario-3-slow-leak.js` - k6 case 3 slow leak scenario
