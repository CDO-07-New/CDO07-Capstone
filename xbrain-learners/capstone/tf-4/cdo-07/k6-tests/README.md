# K6 Load Testing Guide

## ⚡ Quick Start (Cost-Effective Testing)

**⚠️ CHÚ Ý**: Full tests chạy 2 giờ = TỐN TIỀN (~$6/run)!

### SHORT Versions (Recommended for DEV/DEMO)

Để tiết kiệm chi phí và thời gian, tôi đã tạo **SHORT versions** (15-20 phút thay vì 2 giờ):

```bash
# SHORT version - Chạy 20 phút thay vì 2 giờ
k6 run -e ALB_DNS=http://<alb-dns> scenario-1-gradual-drift-SHORT.js

Cost: ~$0.50 (thay vì $6)
Time: 20 phút (thay vì 2 giờ)
```

| Test Type | Duration | Cost | Use Case |
|-----------|----------|------|----------|
| **SHORT** | 15-20 min | ~$0.50 | ✅ Dev, Demo, Smoke test |
| **FULL** | 2 hours | ~$6 | ✅ Final evaluation only |

**Khi nào dùng SHORT vs FULL?**

**SHORT (15-20 phút)** - Dùng cho:
- ✅ Daily development testing
- ✅ Infrastructure validation  
- ✅ Telemetry flow verification
- ✅ Quick demos cho stakeholders
- ✅ CI/CD smoke tests
- ⚠️ AI accuracy có thể thấp hơn (ít data)

**FULL (2 giờ)** - CHỈ dùng khi:
- ✅ Production-grade evaluation
- ✅ Accurate AI drift detection
- ✅ Measure lead time (≥15 min requirement)
- ✅ Calculate confusion matrix
- ✅ Final capstone demo
- ⚠️ Expensive! Plan ahead

---

## 📊 Test Scenarios Overview

| Scenario | Duration | Load Pattern | Purpose | Detection Target |
|----------|----------|--------------|---------|------------------|
| **1. Gradual Drift** | 2h | 50→100→150 RPS | Memory leak simulation | Memory utilization upward trend |
| **2. Sudden Spike** | 2h | 100→500→100 RPS | Traffic surge | CPU spike, latency spike |
| **3. Slow Leak** | 2.5h | 100 RPS steady | Connection leak | Active connections trend |
| **4. Noisy Baseline** | 2h | 80-120 RPS random | Normal variation | Baseline establishment |

**Total Test Coverage:** 8.5 hours across all scenarios

---

## 🚀 Running Tests

### **Option 1: GitHub Actions (Recommended for CI/CD)**

#### **Manual Trigger** (Web UI)
1. Go to: `Actions` → `K6 Load Tests` → `Run workflow`
2. Select:
   - **Environment**: `sandbox` or `staging`
   - **Scenario**: Choose one scenario (or `all` with caution)
3. Click `Run workflow`

#### **Scheduled Automatic Runs**
Tests run automatically via cron:
- **Monday 2 AM UTC**: Scenario 1 (Gradual Drift)
- **Tuesday 2 AM UTC**: Scenario 2 (Sudden Spike)
- **Wednesday 2 AM UTC**: Scenario 3 (Slow Leak)
- **Thursday 2 AM UTC**: Scenario 4 (Noisy Baseline)

#### **⚠️ GitHub Actions Limitations**
- **Timeout**: 6 hours max per job
- **Running all scenarios**: May timeout (8.5h total)
- **Solution**: Run scenarios individually or use scheduled runs
- **Cost**: 
  - Public repo: 2000 free minutes/month
  - Private repo: $0.008/minute (~$10/scenario)

---

### **Option 2: Local Execution**

#### **Prerequisites**
```bash
# Install K6
# macOS
brew install k6

# Windows
choco install k6

# Linux
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 \
  --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | \
  sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6
```

#### **Get ALB DNS**
```bash
# Set environment
ENV="sandbox"  # or "staging"

# Get ALB DNS from AWS
aws elbv2 describe-load-balancers \
  --names "cdo-07-${ENV}-alb" \
  --query 'LoadBalancers[0].DNSName' \
  --output text
```

#### **Run Individual Scenario**
```bash
cd k6-tests

# Export ALB DNS
export ALB_DNS="http://your-alb-dns.us-east-1.elb.amazonaws.com"

# Run specific scenario
k6 run -e ALB_DNS=$ALB_DNS scenario-1-gradual-drift.js

# With output to JSON
k6 run -e ALB_DNS=$ALB_DNS \
  --out json=results/scenario-1-local.json \
  scenario-1-gradual-drift.js
```

#### **🔴 Local Execution Limitations**
1. **Bandwidth**: Requires stable upload ≥10 Mbps for 100+ RPS
2. **Duration**: Computer must stay online for 2-2.5h per scenario
3. **IP Blocking**: Residential IP may be blocked by WAF
4. **No Automation**: Manual trigger only, no retry on failure

---

### **Option 3: AWS-Based Load Testing (Production-Grade)**

#### **3A. EC2 Spot Instance (Cost-Effective)**

**Setup:**
```bash
# Launch spot instance (t3.medium, ~$0.01/hour)
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t3.medium \
  --instance-market-options '{"MarketType":"spot"}' \
  --subnet-id subnet-xxx \
  --security-group-ids sg-xxx \
  --user-data file://k6-userdata.sh
```

**User Data Script** (`k6-userdata.sh`):
```bash
#!/bin/bash
# Install K6
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 \
  --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | \
  sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6 awscli -y

# Clone tests
git clone https://github.com/CDO-07/CDO-07-Capstone-phase2.git
cd CDO-07-Capstone-phase2/xbrain-learners/capstone/tf-4/cdo-07/k6-tests

# Get ALB DNS
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names cdo-07-sandbox-alb \
  --region us-east-1 \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

# Run all scenarios
for scenario in scenario-*.js; do
  k6 run -e ALB_DNS="http://$ALB_DNS" \
    --out json="results/${scenario%.js}-$(date +%Y%m%d).json" \
    "$scenario"
done

# Upload results to S3
aws s3 cp results/ s3://cdo-07-test-results/ --recursive

# Terminate self
shutdown -h now
```

**Cost**: ~$0.30 for 8.5h test (t3.medium spot)

---

#### **3B. K6 Cloud (Managed Service)**

**Setup:**
```bash
# Sign up: https://k6.io/cloud
k6 login cloud

# Run with cloud execution
k6 cloud scenario-1-gradual-drift.js
```

**Pros:**
- ✅ Distributed load from multiple regions
- ✅ Real-time dashboards
- ✅ No infrastructure management
- ✅ Can simulate 1000+ RPS easily

**Cons:**
- ❌ **Cost**: ~$49-99/month for sustained tests
- ❌ Overkill for 100 RPS baseline

---

#### **3C. AWS Distributed Load Testing Solution**

AWS provides a free CloudFormation template for distributed load testing:
- **URL**: https://aws.amazon.com/solutions/implementations/distributed-load-testing/
- **Architecture**: Fargate containers running K6/Taurus
- **Cost**: Pay only for Fargate runtime (~$1-2 for full test suite)
- **Setup Time**: ~30 minutes

---

## 📈 Comparison Matrix

| Method | Cost | Complexity | Reliability | Scalability | Recommendation |
|--------|------|------------|-------------|-------------|----------------|
| **GitHub Actions** | Free-$40/mo | ⭐ Low | ⭐⭐⭐ Good | ⭐⭐ Limited | ✅ **Start here** |
| **Local Execution** | $0 | ⭐ Low | ⭐⭐ Fair | ⭐ Poor | ⚠️ Dev/debug only |
| **EC2 Spot** | ~$0.30 | ⭐⭐ Medium | ⭐⭐⭐⭐ Excellent | ⭐⭐⭐⭐ High | ✅ **Production** |
| **K6 Cloud** | $49+/mo | ⭐ Low | ⭐⭐⭐⭐⭐ Best | ⭐⭐⭐⭐⭐ Best | 🤷 Overkill for 100 RPS |
| **AWS DLT Solution** | $1-2 | ⭐⭐⭐ High | ⭐⭐⭐⭐⭐ Best | ⭐⭐⭐⭐⭐ Best | ✅ **Enterprise** |

---

## 🎯 Recommended Approach

### **For Capstone Project (Budget-Conscious)**
1. **Development/Initial Testing**: GitHub Actions (free)
2. **Final Evidence Collection**: EC2 Spot Instance ($0.30)
   - Run all 4 scenarios sequentially
   - Capture telemetry data for AI analysis
   - Document in evidence pack

### **For Production (After Capstone)**
- AWS Distributed Load Testing Solution
- Automated nightly runs
- Integration with CloudWatch alarms

---

## 📊 Interpreting Results

### **Key Metrics to Monitor**

**From K6 Output:**
```
✓ http_req_duration..............: avg=245ms  p95=580ms  p99=1.2s
✓ http_req_failed................: 0.23%
✓ http_reqs......................: 720000
✓ iterations.....................: 720000
✓ vus............................: 100
```

**From CloudWatch (AI Engine Telemetry):**
- `memory_usage_percent` trend over time
- `cpu_usage_percent` spikes
- `api_latency_ms` P95/P99
- `active_connections` drift

**Expected AI Detections:**
- **Scenario 1**: Memory drift alert ~90 min in (before 2h SLO breach)
- **Scenario 2**: CPU spike alert within 5 min of spike start
- **Scenario 3**: Connection leak alert ~120 min in
- **Scenario 4**: Should establish clean baseline, minimal alerts

---

## 🐛 Troubleshooting

### **Problem: GitHub Actions timeout**
**Solution**: Run scenarios individually, not `all`

### **Problem: Connection refused from K6**
**Solution**: Verify ALB security group allows inbound from K6 IP

### **Problem: High error rate (>5%)**
**Solution**: 
1. Check mock service health: `curl http://$ALB_DNS/health`
2. Verify ECS tasks are running
3. Check CloudWatch logs for errors

### **Problem: No telemetry in Kinesis**
**Solution**:
1. Check mock service logs for Kinesis errors
2. Verify IAM role has `kinesis:PutRecord` permission
3. Check `KINESIS_STREAM_NAME` environment variable

---

## 📝 Evidence Pack Integration

After running tests, collect:
1. **K6 JSON results**: `k6-tests/results/*.json`
2. **CloudWatch dashboards**: Screenshot of metrics during test
3. **AI recommendations**: From audit log during test window
4. **Cost analysis**: CloudWatch billing data for test period

Document in: `docs/evidence/scenario-X-evidence.md`
