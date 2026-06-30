# K6 Load Tests - Foresight Lens TF4

Load testing scenarios để test AI Engine drift detection capabilities.

## 📋 Test Scenarios Overview

| Scenario | Duration | Pattern | Detection Target | Expected Lead Time |
|----------|----------|---------|------------------|-------------------|
| **1. Gradual Drift** | 2h | 50→100→150 RPS gradual | Memory leak, slow degradation | ≥15 min |
| **2. Sudden Spike** | 2h | 100→500 RPS in 2 min | Traffic surge, Black Friday | Immediate |
| **3. Slow Leak** | 2.5h | Constant 100 RPS, growing payload | Resource exhaustion | ≥15 min |
| **4. Noisy Baseline** | 2h | 80-320 RPS random | False positive filtering | N/A |

## 🎯 Requirements Mapping

Test scenarios fulfill hard requirements:
- ✅ Test window ≥2h (all scenarios)
- ✅ Lead time ≥15 min (scenarios 1, 3)
- ✅ Multi-tenant ≥3 services (payment-gw, ledger-svc, fraud-detection)
- ✅ FP rate ≤12% (scenario 4 validates)
- ✅ Catch ≥80% drift (all scenarios)

## 🚀 Prerequisites

### 1. Install k6

```bash
# Windows (Chocolatey)
choco install k6

# macOS (Homebrew)
brew install k6

# Linux
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6
```

### 2. Get ALB DNS Name

```bash
cd ../infra/environments/sandbox
terraform output alb_dns_name
```

Output example: `internal-cdo-07-sandbox-alb-123456789.us-east-1.elb.amazonaws.com`

### 3. Verify Mock Services Running

```bash
# Health check all services
curl http://<ALB_DNS>/health  # Should return 200 from any mock service
```

## 🧪 Running Tests

### Quick Test (5 minutes - smoke test)

```bash
# Test connectivity
k6 run --duration 5m --vus 10 \
  -e ALB_DNS=http://internal-cdo-07-sandbox-alb-xxxxx.us-east-1.elb.amazonaws.com \
  scenario-1-gradual-drift.js
```

### Scenario 1: Gradual Drift (2 hours)

```bash
k6 run \
  -e ALB_DNS=http://internal-cdo-07-sandbox-alb-xxxxx.us-east-1.elb.amazonaws.com \
  --out json=results/scenario-1-gradual-drift.json \
  scenario-1-gradual-drift.js
```

**What to observe:**
- Grafana: Memory utilization trending upward
- Slack: Alert with recommendation "Scale memory 512MB → 1024MB"
- Lead time: AI should alert ≥15 min before breach

### Scenario 2: Sudden Spike (2 hours)

```bash
k6 run \
  -e ALB_DNS=http://internal-cdo-07-sandbox-alb-xxxxx.us-east-1.elb.amazonaws.com \
  --out json=results/scenario-2-sudden-spike.json \
  scenario-2-sudden-spike.js
```

**What to observe:**
- Spike occurs at 30:00 mark
- AI should detect within 2 minutes
- Recommendation: "Enable auto-scaling, max_instances 2 → 8"

### Scenario 3: Slow Leak (2.5 hours)

```bash
k6 run \
  -e ALB_DNS=http://internal-cdo-07-sandbox-alb-xxxxx.us-east-1.elb.amazonaws.com \
  --out json=results/scenario-3-slow-leak.json \
  scenario-3-slow-leak.js
```

**What to observe:**
- Memory grows 1x → 4x over 2.5 hours
- Latency degrades progressively
- Recommendation: "Memory leak detected, restart service"

### Scenario 4: Noisy Baseline (2 hours)

```bash
k6 run \
  -e ALB_DNS=http://internal-cdo-07-sandbox-alb-xxxxx.us-east-1.elb.amazonaws.com \
  --out json=results/scenario-4-noisy-baseline.json \
  scenario-4-noisy-baseline.js
```

**What to observe:**
- Multiple random spikes (normal variance)
- AI should NOT alert on noise
- FP rate must be ≤12%
- Only spike #4 (105 min) might be true anomaly

## 📊 Parallel Test Execution

Run all scenarios in parallel (requires 4 terminals or screen/tmux):

```bash
# Terminal 1
k6 run -e ALB_DNS=http://... --out json=results/s1.json scenario-1-gradual-drift.js &

# Terminal 2
k6 run -e ALB_DNS=http://... --out json=results/s2.json scenario-2-sudden-spike.js &

# Terminal 3
k6 run -e ALB_DNS=http://... --out json=results/s3.json scenario-3-slow-leak.js &

# Terminal 4
k6 run -e ALB_DNS=http://... --out json=results/s4.json scenario-4-noisy-baseline.js &
```

**⚠️ WARNING:** Running all scenarios simultaneously will generate ~400-500 RPS peak, ensure infrastructure can handle it or run sequentially.

## 🔍 Monitoring During Tests

### 1. Grafana Dashboard
```
https://g-<workspace-id>.grafana-workspace.us-east-1.amazonaws.com
```

Watch:
- CPU/Memory utilization per service
- Request latency trends
- AI prediction annotations

### 2. Kinesis Metrics
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/Kinesis \
  --metric-name IncomingRecords \
  --dimensions Name=StreamName,Value=cdo-07-sandbox-ingest-stream \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum
```

### 3. ECS Service Health
```bash
aws ecs describe-services \
  --cluster sandbox-mock-services \
  --services payment-gw ledger-svc fraud-detection \
  --query 'services[*].[serviceName,runningCount,desiredCount]' \
  --output table
```

### 4. Slack Alerts
Check `#cdo-07-alerts` channel for drift warnings with 5-part recommendations:
1. Action verb (e.g., "Scale")
2. Target (e.g., "Memory")
3. From→To (e.g., "512MB → 1024MB")
4. Confidence (e.g., "0.87")
5. Evidence link (e.g., Grafana URL)

## 📈 Results Analysis

### Generate Summary Report

```bash
# After test completes
k6 inspect results/scenario-1-gradual-drift.json
```

### Key Metrics to Capture

| Metric | Threshold | Pass Criteria |
|--------|-----------|---------------|
| **http_req_duration (p95)** | <500ms baseline, <1000ms spike | Service responsive |
| **http_req_failed** | <5% | Low error rate |
| **AI Detection Lead Time** | ≥15 min | Manual verification in Grafana |
| **FP Rate** | ≤12% | Scenario 4 critical |
| **Catch Rate** | ≥80% | Across all scenarios |

### Confusion Matrix Validation

After all tests, calculate:

```
True Positives (TP): AI alerted, drift actually occurred
False Positives (FP): AI alerted, no drift (noise)
False Negatives (FN): No alert, but drift occurred
True Negatives (TN): No alert, no drift

Precision = TP / (TP + FP) → should be ≥88%
Recall = TP / (TP + FN) → should be ≥80%
FP Rate = FP / (FP + TN) → must be ≤12%
```

## 🐛 Troubleshooting

### Connection Refused

```bash
# Check ALB is internal, you must be in VPC
# Use SSM Session Manager to reach internal ALB

# Or use port forwarding
aws ssm start-session \
  --target i-<bastion-instance-id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<ALB_DNS>"],"portNumber":["80"],"localPortNumber":["8080"]}'

# Then test from localhost
k6 run -e ALB_DNS=http://localhost:8080 scenario-1-gradual-drift.js
```

### High Error Rate

```bash
# Check ECS tasks are running
aws ecs list-tasks --cluster sandbox-mock-services

# Check logs
aws logs tail /aws/ecs/sandbox-mock-services --follow
```

### Kinesis Throttling

```bash
# Check if stream needs more shards
aws kinesis describe-stream-summary --stream-name cdo-07-sandbox-ingest-stream

# Increase shard count if needed (impacts cost)
aws kinesis update-shard-count \
  --stream-name cdo-07-sandbox-ingest-stream \
  --target-shard-count 5 \
  --scaling-type UNIFORM_SCALING
```

## 📝 Test Checklist

- [ ] Infrastructure deployed (Terraform applied)
- [ ] Mock services running (3/3 healthy)
- [ ] Kinesis stream active
- [ ] AI Engine deployed and responding
- [ ] Grafana dashboard configured
- [ ] Slack integration working
- [ ] ALB DNS name obtained
- [ ] k6 installed locally
- [ ] VPC access configured (bastion/VPN/SSM)
- [ ] Cost circuit breaker tested ($200 cap)
- [ ] Scenario 1 completed (2h)
- [ ] Scenario 2 completed (2h)
- [ ] Scenario 3 completed (2.5h)
- [ ] Scenario 4 completed (2h)
- [ ] Confusion matrix calculated
- [ ] Lead time ≥15 min verified
- [ ] FP rate ≤12% verified
- [ ] Catch rate ≥80% verified
- [ ] 5-part recommendations validated
- [ ] Audit logs encrypted and retained

## 🎓 Expected Outcomes

| Scenario | AI Should Detect | Recommendation Example |
|----------|------------------|------------------------|
| 1. Gradual Drift | Memory upward trend | "Scale memory: 512MB → 1024MB, confidence 0.89" |
| 2. Sudden Spike | Throughput anomaly | "Enable auto-scaling: max_instances 2 → 8, confidence 0.95" |
| 3. Slow Leak | Memory leak pattern | "Restart service, investigate memory leak, confidence 0.82" |
| 4. Noisy Baseline | Filter noise, low FP | "Widen prediction bands, increase threshold, confidence 0.76" |

## 📚 References

- [k6 Documentation](https://k6.io/docs/)
- [k6 Executors](https://k6.io/docs/using-k6/scenarios/executors/)
- [Foresight Lens Design Doc](../docs/02_infra_design.md)
- [Telemetry Contract](../docs/06_contracts.md)
