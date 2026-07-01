# Hướng Dẫn Test K6 Trên GitHub Actions

## 📋 Mục Lục
- [Checklist Trước Khi Test](#checklist-trước-khi-test)
- [Cách Chạy Test](#cách-chạy-test)
- [Phân Tích Kết Quả](#phân-tích-kết-quả)
- [Troubleshooting](#troubleshooting)
- [Chi Phí và Timeline](#chi-phí-và-timeline)

---

## ✅ Checklist Trước Khi Test

### 1. Infrastructure Phải Đã Deploy
```bash
# Kiểm tra ECS cluster đang chạy
aws ecs describe-clusters --clusters staging-mock-services --region us-east-1

# Kiểm tra 3 services đang running
aws ecs list-services --cluster staging-mock-services --region us-east-1

# Expected output: payment-gw, ledger-svc, fraud-detection
```

### 2. Mock Services Phải Đã Build & Deploy
```bash
# Kiểm tra ECR repositories
aws ecr describe-repositories --region us-east-1 --repository-names payment-gw ledger-svc fraud-detection

# Kiểm tra images đã được push
aws ecr describe-images --repository-name payment-gw --region us-east-1
aws ecr describe-images --repository-name ledger-svc --region us-east-1
aws ecr describe-images --repository-name fraud-detection --region us-east-1
```

### 3. ALB Đã Được Tạo và Public
```bash
# Lấy ALB DNS name
aws elbv2 describe-load-balancers \
  --names cdo-07-staging-vpc-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text \
  --region us-east-1

# Expected output: cdo-07-staging-vpc-alb-xxxxxxxxx.us-east-1.elb.amazonaws.com
```

### 4. Health Checks Phải Pass
```bash
# Test health endpoints (thay <ALB_DNS> bằng DNS thực tế)
curl -v http://<ALB_DNS>/health

# Expected: HTTP 200 với response từ 1 trong 3 services
```

### 5. GitHub Secrets Đã Cấu Hình
Vào **Settings → Secrets and variables → Actions** kiểm tra:
- ✅ `AWS_DEPLOY_ROLE_ARN` (format: `arn:aws:iam::201023212626:role/github-actions-role`)
- ✅ `SLACK_WEBHOOK_URL` (optional, cho notifications)

---

## 🚀 Cách Chạy Test

### Option 1: Test Nhanh (SHORT - Khuyến Nghị Cho Dev/Demo)
**Duration:** 20 phút  
**Cost:** ~$0.50  
**Use Case:** Development, smoke test, demo nhanh

#### Bước 1: Vào GitHub Actions
1. Truy cập: https://github.com/CDO-07/CDO-07-Capstone-phase2/actions
2. Click workflow **"K6 Load Tests"** ở sidebar trái
3. Click button **"Run workflow"** (góc phải)

#### Bước 2: Chọn Parameters
```yaml
Branch: feat/dev (hoặc main)
Environment to test: staging
Test scenario: scenario-1-gradual-drift-SHORT
Use SHORT versions: ✅ CHECKED (khuyến nghị)
```

#### Bước 3: Run và Monitor
1. Click **"Run workflow"** màu xanh
2. Chờ ~5s, workflow sẽ xuất hiện
3. Click vào workflow run để xem logs real-time
4. Thời gian chạy: ~22-25 phút (20 min test + 2-5 min setup)

---

### Option 2: Test Đầy Đủ (FULL - Chỉ Dùng Cho Production Evaluation)
**Duration:** 2 giờ  
**Cost:** ~$6  
**Use Case:** Production evaluation, chính thức submit evidence

#### Chọn Parameters
```yaml
Branch: main (khuyến nghị cho production test)
Environment to test: staging (hoặc sandbox)
Test scenario: scenario-1-gradual-drift (KHÔNG có -SHORT)
Use SHORT versions: ❌ UNCHECKED (để chạy full 2h)
```

⚠️ **LƯU Ý:** Full test tốn:
- 2+ giờ thời gian chạy
- ~$6 chi phí AWS
- Chỉ chạy khi cần evidence chính thức hoặc đánh giá AI Engine

---

## 📊 Các Scenario Có Sẵn

| Scenario | Description | Duration SHORT | Duration FULL | Cost SHORT | Cost FULL |
|----------|-------------|----------------|---------------|------------|-----------|
| **scenario-1-gradual-drift-SHORT** | Gradual performance degradation | 20 min | - | $0.50 | - |
| **scenario-1-gradual-drift** | Full 2h gradual drift test | - | 2h | - | $6 |
| **scenario-2-sudden-spike** | Sudden traffic spike | - | 2.5h | - | $7.5 |
| **scenario-3-slow-leak** | Memory/resource leak | - | 2h | - | $6 |
| **scenario-4-noisy-baseline** | Baseline with random noise | - | 2h | - | $6 |
| **all** | Chạy tất cả scenarios | - | 8.5h | - | $25+ |

### Khuyến Nghị Strategy
```
📍 DEVELOPMENT PHASE:
  → Dùng SHORT versions (~20 min, $0.50)
  → Test infrastructure, debug issues
  → Iterate quickly

📍 PRE-PRODUCTION:
  → Dùng scenario-1 hoặc scenario-2 FULL (2h, $6)
  → Verify AI detection works
  → Get preliminary evidence

📍 PRODUCTION SUBMISSION:
  → Chạy ALL scenarios FULL (8.5h, $25)
  → Hoặc chạy từng scenario riêng biệt
  → Collect complete evidence pack
```

---

## 🔍 Phân Tích Kết Quả

### 1. Xem Summary Trên GitHub
Sau khi test xong, scroll xuống phần **"Summary"**:

```markdown
## K6 Load Test Results

**Environment:** staging
**Scenario:** scenario-1-gradual-drift-SHORT
**Run ID:** 1234567890
**Duration:** ~20 minutes (SHORT version)
**Estimated Cost:** ~$0.50

✅ Using SHORT versions to save cost and time

💡 Tip: Uncheck 'use_short_versions' for FULL 2-hour tests
```

### 2. Download Artifacts
1. Scroll xuống cuối workflow run
2. Section **"Artifacts"**: `k6-results-<run-id>`
3. Click download → unzip
4. Mở file JSON để xem chi tiết metrics

### 3. Kiểm Tra Metrics Key
Trong file JSON, tìm:

```json
{
  "scenario": "gradual-drift-SHORT",
  "duration_minutes": 20,
  "total_requests": 120000,
  "error_rate": 0.001,
  "p95_latency": 245.5,
  "p99_latency": 456.8
}
```

#### Thresholds Cần Pass
- ✅ **P95 latency** < 500ms
- ✅ **P99 latency** < 1000ms
- ✅ **Error rate** < 5% (0.05)
- ✅ **Total requests** > 0 (có traffic)

### 4. Verify Telemetry Flow
```bash
# Kiểm tra CloudWatch Logs của mock services
aws logs tail /ecs/payment-gw --follow --region us-east-1
aws logs tail /ecs/ledger-svc --follow --region us-east-1
aws logs tail /ecs/fraud-detection --follow --region us-east-1

# Expected: Thấy logs "Sent telemetry to Kinesis"
```

### 5. Kiểm Tra Kinesis Stream
```bash
# Xem metrics của Kinesis stream
aws kinesis describe-stream-summary \
  --stream-name cdo-07-staging-telemetry \
  --region us-east-1

# Expected: IncomingRecords > 0, IncomingBytes > 0
```

### 6. Kiểm Tra InfluxDB (Nếu Đã Setup)
```bash
# Query InfluxDB để xem metrics đã được ghi
# (Cần credentials từ terraform outputs)
influx query 'from(bucket:"foresight-metrics") |> range(start: -1h) |> filter(fn: (r) => r["_measurement"] == "service_metrics")'
```

---

## 🐛 Troubleshooting

### Lỗi: "Error from server (Forbidden): User is not authorized"
**Nguyên nhân:** GitHub Actions không có quyền truy cập AWS

**Cách sửa:**
1. Kiểm tra secret `AWS_DEPLOY_ROLE_ARN` đã set chưa
2. Verify IAM role trust relationship:
```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::201023212626:oidc-provider/token.actions.githubusercontent.com"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:CDO-07/CDO-07-Capstone-phase2:*"
    }
  }
}
```

---

### Lỗi: "The repository with name 'xxx' does not exist"
**Nguyên nhân:** ECR repositories chưa được tạo

**Cách sửa:**
```bash
# Tạo repositories thủ công
aws ecr create-repository --repository-name payment-gw --region us-east-1
aws ecr create-repository --repository-name ledger-svc --region us-east-1
aws ecr create-repository --repository-name fraud-detection --region us-east-1
```

Hoặc chạy workflow **"Build & Push Mock Services"** trước.

---

### Lỗi: "Could not resolve host: <ALB_DNS>"
**Nguyên nhân:** ALB chưa được tạo hoặc DNS chưa propagate

**Cách sửa:**
```bash
# 1. Kiểm tra ALB có tồn tại không
aws elbv2 describe-load-balancers --region us-east-1

# 2. Nếu không có, chạy terraform apply
cd xbrain-learners/capstone/tf-4/cdo-07/infra/environments/staging
terraform init
terraform apply

# 3. Đợi 2-5 phút cho DNS propagate
nslookup <ALB_DNS>
```

---

### Lỗi: "Connection refused" hoặc "502 Bad Gateway"
**Nguyên nhân:** ECS services chưa healthy

**Cách sửa:**
```bash
# 1. Kiểm tra ECS service status
aws ecs describe-services \
  --cluster staging-mock-services \
  --services payment-gw ledger-svc fraud-detection \
  --region us-east-1

# 2. Kiểm tra task health
aws ecs list-tasks --cluster staging-mock-services --region us-east-1

# 3. Xem logs
aws logs tail /ecs/payment-gw --follow --region us-east-1

# 4. Nếu tasks không start, force new deployment
aws ecs update-service \
  --cluster staging-mock-services \
  --service payment-gw \
  --force-new-deployment \
  --region us-east-1
```

---

### Lỗi: K6 test fails với error rate > 5%
**Nguyên nhân:** Mock services quá tải hoặc có bug

**Cách debug:**
```bash
# 1. Kiểm tra CloudWatch metrics
# ECS → Clusters → staging-mock-services → Metrics tab

# 2. Scale up tasks nếu CPU/Memory cao
aws ecs update-service \
  --cluster staging-mock-services \
  --service payment-gw \
  --desired-count 3 \
  --region us-east-1

# 3. Kiểm tra application logs
aws logs tail /ecs/payment-gw --follow --region us-east-1 | grep ERROR
```

---

### Lỗi: Workflow timeout sau 6 giờ
**Nguyên nhân:** Chọn "all" scenarios (8.5h) nhưng timeout limit là 6h

**Cách sửa:**
1. **Option A:** Chạy từng scenario riêng biệt
2. **Option B:** Tăng timeout trong workflow file:
```yaml
jobs:
  k6-test:
    timeout-minutes: 600  # Tăng lên 10 giờ
```

---

## 💰 Chi Phí và Timeline

### Cost Breakdown (Per Test Run)

| Component | SHORT (20 min) | FULL (2h) | Note |
|-----------|----------------|-----------|------|
| ECS Tasks (3 services) | $0.20 | $2.40 | 0.25 vCPU × 512MB × 3 |
| ALB | $0.05 | $0.60 | $0.0225/hour + LCU |
| Kinesis | $0.10 | $1.20 | Data Streams charges |
| Lambda (telemetry) | $0.05 | $0.60 | Window Feeder invocations |
| CloudWatch Logs | $0.05 | $0.60 | Ingestion + storage |
| InfluxDB (optional) | $0.05 | $0.60 | EC2 t3.small running |
| **TOTAL** | **~$0.50** | **~$6.00** | Estimate ± 20% |

### Monthly Budget Tracking

```
📊 BUDGET: $200/month

Scenario Plan:
- Development (10× SHORT tests): 10 × $0.50 = $5
- Pre-production (5× FULL tests): 5 × $6 = $30
- Production Evidence (4× FULL): 4 × $6 = $24
- Infrastructure (24/7): ~$100/month
  ├─ ECS tasks (staging): $30
  ├─ RDS/InfluxDB: $25
  ├─ ALB: $20
  ├─ Kinesis: $15
  └─ Lambda + CloudWatch: $10

TOTAL: ~$159/month (within budget ✅)
```

### Timeline Ước Tính

```
Week 1 (Development):
├─ Day 1-2: Infrastructure setup + SHORT tests
│   └─ 5× SHORT runs = 100 min total, $2.50
├─ Day 3-4: Mock services tuning + SHORT tests
│   └─ 5× SHORT runs = 100 min total, $2.50
└─ Day 5: Integration test + 1× FULL
    └─ 1× FULL run = 2h, $6

Week 2 (Pre-production):
├─ Day 6-8: AI Engine testing + 3× FULL
│   └─ 3× FULL runs = 6h total, $18
└─ Day 9-10: Bug fixes + 2× SHORT
    └─ 2× SHORT runs = 40 min, $1

Week 3 (Production):
└─ Day 11-12: Final evidence collection
    └─ 4× FULL runs (all scenarios) = 8.5h, $24

TOTAL: ~$54 for testing phase
```

---

## 📝 Evidence Collection Checklist

Để submit evidence cho Capstone, cần collect:

### 1. K6 Test Results
- [ ] Download artifacts từ GitHub Actions
- [ ] Screenshot workflow summary
- [ ] JSON files với metrics (P95, P99, error rate)

### 2. Infrastructure Proof
- [ ] Screenshot ECS cluster với 3 services running
- [ ] ALB target group health checks (all healthy)
- [ ] CloudWatch metrics showing traffic patterns

### 3. Telemetry Flow
- [ ] CloudWatch Logs: Mock services sending to Kinesis
- [ ] CloudWatch Logs: Window Feeder processing metrics
- [ ] InfluxDB query results (time-series data)

### 4. AI Engine Detection (Nếu Có)
- [ ] CloudWatch Logs: AI Engine predictions
- [ ] S3 Audit logs: Window Feeder → AI Engine calls
- [ ] Slack notifications (drift detected)

### 5. Documentation
- [ ] README với architecture diagram
- [ ] Deployment checklist (completed steps)
- [ ] Cost analysis report
- [ ] Lessons learned document

---

## 🎯 Quick Reference Commands

### Chạy Test Từ GitHub UI
```
1. https://github.com/CDO-07/CDO-07-Capstone-phase2/actions
2. Click "K6 Load Tests"
3. Click "Run workflow"
4. Select: staging, scenario-1-gradual-drift-SHORT, ✅ use_short
5. Click "Run workflow"
```

### Kiểm Tra Health
```bash
# ALB health
curl http://<ALB_DNS>/health

# ECS services
aws ecs describe-services --cluster staging-mock-services --services payment-gw --region us-east-1
```

### Xem Logs Real-time
```bash
aws logs tail /ecs/payment-gw --follow --region us-east-1
aws logs tail /aws/lambda/cdo07-staging-window-feeder --follow --region us-east-1
```

### Get ALB DNS
```bash
aws elbv2 describe-load-balancers \
  --names cdo-07-staging-vpc-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text \
  --region us-east-1
```

---

## 📞 Support và Resources

### GitHub Repository
- Main: https://github.com/CDO-07/CDO-07-Capstone-phase2
- Workflows: `.github/workflows/k6-load-tests.yml`
- K6 Tests: `xbrain-learners/capstone/tf-4/cdo-07/k6-tests/`

### Documentation
- Deploy Checklist: `docs/deploy-checklist.md`
- Architecture: `docs/ARCHITECTURE.md`
- Cost Analysis: `docs/COST_ANALYSIS.md`

### Monitoring
- CloudWatch: https://console.aws.amazon.com/cloudwatch
- ECS: https://console.aws.amazon.com/ecs
- ECR: https://console.aws.amazon.com/ecr

---

**Last Updated:** 2026-07-01  
**Version:** 1.0  
**Author:** CDO-07 Team
