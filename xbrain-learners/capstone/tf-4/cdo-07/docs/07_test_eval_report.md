# Test & Eval Report - Task Force 4 · CDO-07

<!-- Doc owner: CDO-07
     Status: NEW - chỉ fill trong W12 T4 Pack #2
     Word target: 1000-1800 từ
     Last updated: 2026-06-22 (skeleton) -->

> **Lưu ý**: Doc này viết trong W12 sau khi build xong. W11 chỉ cần tạo file skeleton này.
> Điền từng section sau mỗi test run - đừng viết một phát cuối T4 W12.

---

## 1. Test coverage

| Test type | Tool | Coverage / Scope | Status |
|---|---|---|---|
| Unit test (infra modules) | Checkov / pytest | Terraform policy compliance | W12 |
| Integration test | Postman / pytest | Tenant provision flow + AI endpoint integration | W12 |
| E2E test (happy path) | k6 / Locust | 3 tier-1 services drift → alert → Grafana annotation | W12 |
| Load test | k6 | 100 RPS sustained 10 min, 3 concurrent services | W12 |
| Chaos test | Manual (curveball) | 3 curveball scenarios inject | W12 |
| Multi-tenant isolation | Custom script | Cross-service data leak attempt | W12 |
| Security scan | Trivy + Checkov | Container + IaC CVE | W12 |

---

## 2. SLO evidence

<!-- Điền sau khi run test suite W12 -->

| SLO | Target | Measured | Window | Pass/Fail |
|---|---|---|---|---|
| Platform availability | ≥ 99.5% | — | 2-week build period | — |
| AI API P99 latency | < 1000ms | — | Last 24h | — |
| Error rate | < 0.5% | — | Last 24h | — |
| Prediction lead time | ≥ 15 phút trước SLO breach | — | ≥ 2h test window | — |
| Service onboarding | < 30 min | — | 3 test services | — |
| FP rate (drift detection) | ≤ 12% | — | Test scenario set | — |
| Catch rate (drift) | ≥ 80% | — | Test scenario set | — |

### 2.1 SLO breach analysis

<!-- Nếu có miss SLO, ghi root cause và fix -->

`< TODO W12: điền nếu có SLO miss >`

---

## 3. Load test results

### 3.1 Test setup

- **Load profile**: ramp-up 0 → 100 RPS over 5 min, sustained 100 RPS for 10 min
- **Services simulated**: 3 concurrent (payment-gateway, kyc-service, reporting-service)
- **Synthetic workload**: k6 script generate metric events với pattern: gradual drift + sudden spike
- **Tool**: k6 (script tại `tests/load/k6_load_test.js`)

### 3.2 Results

<!-- Điền sau khi chạy load test W12 T3 -->

| Metric | Target | Achieved | Notes |
|---|---|---|---|
| RPS sustained | 100 | — | — |
| P99 latency at peak | < 1500ms | — | — |
| Error rate at peak | < 1% | — | — |
| Auto-scale triggered | scale to ≥ 3 tasks | — | — |
| TSDB write throughput | 50k events/sec | — | — |

### 3.3 Bottleneck identified

`< TODO W12: DB connection pool? AI engine throttle? Ingest layer? >`

---

## 4. TF4-specific: Prediction test scenarios

<!-- TF4 đặc thù - phải test 4 drift scenarios trên ≥2h window -->

| Scenario | Description | Lead time measured | Caught? |
|---|---|---|---|
| Gradual drift | CPU bò từ 40% → 95% trong 2h | — | — |
| Sudden spike | Traffic 3× trong 10 phút | — | — |
| Slow memory leak | Memory tăng 5MB/min | — | — |
| Noisy baseline | Random fluctuation, KHÔNG phải drift | FP check | — |

**Test window**: ≥ 2 giờ (per TF4 hard requirement)
**Lead time target**: ≥ 15 phút trên ít nhất 1 scenario

---

## 5. Security test

### 5.1 Penetration touch points

- [ ] API auth bypass attempt → should return 401
- [ ] Cross-service data leak: Service A token → request Service B prediction history → should 403
- [ ] Inject invalid metric schema → should reject with 400
- [ ] IAM privilege escalation attempt từ `tf4-cdo07-readonly-role`
- [ ] Secret exposure via CloudWatch Logs search

### 5.2 Vulnerability scan

- **Container scan tool**: Trivy
- **IaC scan tool**: Checkov
- **CRITICAL findings**: 0 (must be 0 by Pack #2)
- **HIGH findings**: ≤ 3 với documented mitigation
- **Scan report**: `security/trivy-report.json`, `security/checkov-report.txt`

---

## 6. Multi-tenant isolation test

| Test | Method | Expected | Result |
|---|---|---|---|
| Service A reads Service B metric history | Use service-A token → GET /predict history service-B | 403 Forbidden | — |
| Cross-service metric contamination | Ingest metric with wrong service_id | Reject or quarantine | — |
| TSDB row-level isolation | Query TSDB without service_id filter | Empty result / error | — |
| IAM cross-service S3 access | Assume service-A role → read service-B audit prefix | AccessDenied | — |

> **All isolation tests must pass** - any data leak = SEV1, cap T3 per playbook §10.4.

---

## 7. Curveball responses (fill sau mỗi curveball)

### Curveball #1 (W11 T5 - nhẹ, 15 phút)

- **Inject**: `< TODO: điền sau khi nhận curveball T5 W11 >`
- **CDO-07 response**: `< TODO >`
- **Impact on infra**: `< TODO >`
- **Resolution**: `< TODO >`

### Curveball #2 (W12 T2 - medium, 30 phút)

- **Inject**: `< TODO: điền sau khi nhận curveball T2 W12 >`
- **CDO-07 response**: `< TODO >`
- **Impact on infra**: `< TODO >`
- **Resolution**: `< TODO >`

### Curveball #3 (W12 T4 - chaos, 60 phút)

- **Inject**: `< TODO: điền sau khi nhận curveball T4 W12 >`
- **CDO-07 response**: `< TODO >`
- **Impact on infra**: `< TODO >`
- **Resolution**: `< TODO >`

---

## 8. Failure analysis

### 8.1 Failures encountered during build

<!-- Append khi gặp failure, đừng xóa - git history evidence -->

| # | Failure | Root cause | Fix applied | Time to fix |
|---|---|---|---|---|
| (empty - sẽ điền trong W12) | | | | |

### 8.2 Test gaps acknowledged

`< TODO W12: ghi honest những gì chưa test đủ - reviewer thích honesty >`

---

## Related documents

- [`02_infra_design.md`](02_infra_design.md) - SLO targets validated trong §2 doc này
- [`03_security_design.md`](03_security_design.md) - Security controls verified trong §5 doc này
- [`05_cost_analysis.md`](05_cost_analysis.md) - Load test validates cost assumptions
- [`../../ai/docs/04_eval_report.md`](../../ai/docs/04_eval_report.md) - AI precision/recall + CDO integration joint view
