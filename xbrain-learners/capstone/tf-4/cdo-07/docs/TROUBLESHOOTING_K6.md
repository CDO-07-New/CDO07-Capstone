# Troubleshooting K6 Tests - HTML Response Error

## ❌ Lỗi: "invalid character '<' looking for beginning of value"

### Nguyên nhân:
ALB đang trả về **HTML** thay vì **JSON** từ mock services. Có thể:
1. Mock services chưa được deploy vào ECS
2. ALB target groups chưa healthy
3. ALB listener rules chưa được cấu hình
4. Mock services có bug, crash khi start

---

## 🔍 Bước 1: Kiểm Tra ECS Services

### 1.1. Kiểm tra services có đang chạy không
```bash
aws ecs describe-services \
  --cluster staging-mock-services \
  --services payment-gw ledger-svc fraud-detection \
  --region us-east-1 \
  --query 'services[*].[serviceName,status,runningCount,desiredCount]' \
  --output table
```

**Expected:**
```
serviceName      status    runningCount  desiredCount
payment-gw       ACTIVE    1             1
ledger-svc       ACTIVE    1             1
fraud-detection  ACTIVE    1             1
```

**Nếu runningCount = 0:** Services chưa start được

---

### 1.2. Kiểm tra tasks có healthy không
```bash
aws ecs list-tasks \
  --cluster staging-mock-services \
  --service-name payment-gw \
  --region us-east-1

# Lấy task ARN rồi describe
aws ecs describe-tasks \
  --cluster staging-mock-services \
  --tasks <TASK_ARN> \
  --region us-east-1
```

**Xem field:** `lastStatus`, `healthStatus`, `containers[].lastStatus`

---

### 1.3. Xem logs của tasks
```bash
# Payment Gateway
aws logs tail /ecs/payment-gw --follow --region us-east-1

# Ledger Service
aws logs tail /ecs/ledger-svc --follow --region us-east-1

# Fraud Detection
aws logs tail /ecs/fraud-detection --follow --region us-east-1
```

**Tìm lỗi:**
- `Error: Cannot find module`
- `ECONNREFUSED` (Kinesis connection issue)
- `Port already in use`
- JavaScript syntax errors

---

## 🔍 Bước 2: Kiểm Tra ALB Target Groups

### 2.1. List target groups
```bash
aws elbv2 describe-target-groups \
  --load-balancer-arn <ALB_ARN> \
  --region us-east-1 \
  --query 'TargetGroups[*].[TargetGroupName,HealthCheckPath,Port]' \
  --output table
```

### 2.2. Kiểm tra target health
```bash
aws elbv2 describe-target-health \
  --target-group-arn <TG_ARN> \
  --region us-east-1
```

**Expected:** `State: healthy` cho tất cả targets

**Nếu unhealthy:**
- `initial`: Đang warm up (đợi 2-3 phút)
- `unhealthy`: Health check fail → Xem logs ECS tasks
- `draining`: Task đang shutdown

---

### 2.3. Test health check trực tiếp
```bash
# Get ALB DNS
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names cdo-07-staging-vpc-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text \
  --region us-east-1)

# Test health endpoint
curl -v http://$ALB_DNS/health

# Expected: HTTP 200 với JSON response
```

**Nếu trả về HTML 503/502:** Target groups chưa healthy

---

## 🔍 Bước 3: Kiểm Tra ALB Listener Rules

### 3.1. List listeners
```bash
aws elbv2 describe-listeners \
  --load-balancer-arn <ALB_ARN> \
  --region us-east-1
```

### 3.2. List rules cho listener
```bash
aws elbv2 describe-rules \
  --listener-arn <LISTENER_ARN> \
  --region us-east-1
```

**Expected:** Rules forward traffic tới target groups

---

## 🔍 Bước 4: Kiểm Tra Mock Services Code

### 4.1. Kiểm tra ECR images
```bash
aws ecr describe-images \
  --repository-name payment-gw \
  --region us-east-1 \
  --query 'sort_by(imageDetails,& imagePushedAt)[-1]' \
  --output json
```

**Xem:** `imagePushedAt` (phải là gần đây)

### 4.2. Test local (optional)
```bash
cd xbrain-learners/capstone/tf-4/cdo-07/mock-services/payment-gw

# Build image
docker build -t payment-gw:test .

# Run container
docker run -p 3000:3000 \
  -e AWS_REGION=us-east-1 \
  -e KINESIS_STREAM_NAME=test-stream \
  payment-gw:test

# Test endpoint
curl -X POST http://localhost:3000/payment/authorize \
  -H "Content-Type: application/json" \
  -d '{"amount":100,"currency":"USD","customer_id":"test123","payment_method":"card"}'
```

**Expected:** JSON response với `transaction_id`

---

## ✅ Giải Pháp Thông Dụng

### Solution 1: Build và Deploy lại Mock Services

```bash
# Trigger build workflow trên GitHub Actions
# https://github.com/CDO-07/CDO-07-Capstone-phase2/actions
# Chọn "Build & Push Mock Services" → Run workflow
```

Hoặc manual:

```bash
cd d:\Test\CDO-07-Capstone-phase2

# Build và push images
./scripts/build-and-push-images.sh staging
```

### Solution 2: Force New Deployment

```bash
# Force ECS tasks restart với image mới
aws ecs update-service \
  --cluster staging-mock-services \
  --service payment-gw \
  --force-new-deployment \
  --region us-east-1

aws ecs update-service \
  --cluster staging-mock-services \
  --service ledger-svc \
  --force-new-deployment \
  --region us-east-1

aws ecs update-service \
  --cluster staging-mock-services \
  --service fraud-detection \
  --force-new-deployment \
  --region us-east-1
```

### Solution 3: Kiểm Tra Security Groups

```bash
# Kiểm tra ALB security group cho phép traffic từ Internet
aws ec2 describe-security-groups \
  --group-ids <ALB_SG_ID> \
  --region us-east-1

# Kiểm tra ECS tasks security group cho phép traffic từ ALB
aws ec2 describe-security-groups \
  --group-ids <ECS_SG_ID> \
  --region us-east-1
```

**Expected:**
- ALB SG: Inbound rule cho port 80 từ 0.0.0.0/0
- ECS SG: Inbound rule cho port 3000 từ ALB SG

### Solution 4: Kiểm Tra Terraform State

```bash
cd xbrain-learners/capstone/tf-4/cdo-07/infra/environments/staging

# Kiểm tra ALB outputs
terraform output

# Expected:
# alb_dns_name = "cdo-07-staging-vpc-alb-xxxxx.us-east-1.elb.amazonaws.com"
```

Nếu output trống → Terraform chưa apply:
```bash
terraform init
terraform plan
terraform apply
```

---

## 📊 Quick Debug Checklist

| Step | Command | Expected Output | Action if Failed |
|------|---------|----------------|------------------|
| 1. ECS services running | `aws ecs describe-services` | runningCount > 0 | Trigger build workflow |
| 2. Tasks healthy | `aws ecs describe-tasks` | lastStatus = RUNNING | Check logs |
| 3. Target groups healthy | `aws elbv2 describe-target-health` | State = healthy | Wait 2-3 min or check health path |
| 4. ALB responds | `curl http://<ALB_DNS>/health` | HTTP 200 JSON | Check listener rules |
| 5. Mock service responds | `curl -X POST http://<ALB_DNS>/payment/authorize` | HTTP 200 JSON | Check ECS logs |

---

## 🚨 Emergency Fixes

### Quick Fix 1: Restart Everything
```bash
# Force new deployment cho cả 3 services
for service in payment-gw ledger-svc fraud-detection; do
  aws ecs update-service \
    --cluster staging-mock-services \
    --service $service \
    --force-new-deployment \
    --region us-east-1
done

# Đợi 3-5 phút cho tasks restart
sleep 180

# Kiểm tra health
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names cdo-07-staging-vpc-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text \
  --region us-east-1)

curl http://$ALB_DNS/health
```

### Quick Fix 2: Scale Up Tasks
```bash
# Tăng số tasks lên 2 để tránh downtime
for service in payment-gw ledger-svc fraud-detection; do
  aws ecs update-service \
    --cluster staging-mock-services \
    --service $service \
    --desired-count 2 \
    --region us-east-1
done
```

---

## 📞 Still Not Working?

Nếu sau tất cả troubleshooting trên vẫn lỗi:

1. **Xem CloudWatch Logs chi tiết:**
   ```bash
   aws logs get-log-events \
     --log-group-name /ecs/payment-gw \
     --log-stream-name <STREAM_NAME> \
     --limit 100 \
     --region us-east-1
   ```

2. **SSH vào EC2 instance (nếu dùng EC2 launch type):**
   ```bash
   aws ecs execute-command \
     --cluster staging-mock-services \
     --task <TASK_ID> \
     --container payment-gw \
     --interactive \
     --command "/bin/sh"
   ```

3. **Check AWS Service Health:**
   https://health.aws.amazon.com/health/status

4. **Review Security Group Rules:**
   Confirm ALB → ECS communication không bị block

---

**Last Updated:** 2026-07-01  
**Version:** 1.0
