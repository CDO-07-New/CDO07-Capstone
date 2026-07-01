# Hướng Dẫn Check và Apply Terraform

## 🔍 Vấn Đề Hiện Tại:

**Target groups không có targets vì:**
- ✅ Code terraform **ĐÃ ĐÚNG** (có `load_balancer` config)
- ✅ Code **ĐÃ ĐƯỢC PUSH** lên Git
- ❌ **TERRAFORM CHƯA ĐƯỢC APPLY** lên AWS

## 📋 Checklist Trước Khi Apply:

### 1. Kiểm Tra AWS Credentials
```powershell
# Check AWS credentials
aws sts get-caller-identity

# Expected output:
# {
#   "UserId": "...",
#   "Account": "201023212626",
#   "Arn": "arn:aws:iam::201023212626:user/..."
# }
```

### 2. Kiểm Tra Region
```powershell
aws configure get region
# Expected: us-east-1
```

### 3. Kiểm Tra ECS Services Hiện Tại
```powershell
aws ecs describe-services `
  --cluster staging-mock-services `
  --services payment-gw ledger-svc fraud-detection `
  --region us-east-1 `
  --query 'services[*].[serviceName,status,runningCount,desiredCount,loadBalancers]' `
  --output json
```

**Expected hiện tại:** `loadBalancers` sẽ là array RỖNG `[]`

---

## 🚀 Apply Terraform

### Bước 1: Navigate to Staging Directory
```powershell
cd d:\Test\CDO-07-Capstone-phase2\xbrain-learners\capstone\tf-4\cdo-07\infra\environments\staging
```

### Bước 2: Initialize Terraform (nếu chưa)
```powershell
terraform init
```

**Expected output:**
```
Terraform has been successfully initialized!
```

### Bước 3: Plan để xem changes
```powershell
terraform plan -out=tfplan
```

**Expected output sẽ show:**
```hcl
# module.mock_services.module.payment_gw will be updated in-place
~ resource "aws_ecs_service" "this" {
    ~ load_balancer {
      + target_group_arn = "arn:aws:elasticloadbalancing:..."
      + container_name   = "payment-gw"
      + container_port   = 3000
    }
  }

# (Tương tự cho ledger-svc và fraud-detection)
```

### Bước 4: Review Changes
Đọc kỹ output của `terraform plan`:
- ✅ Chỉ update ECS services (không xóa/tạo mới)
- ✅ Thêm `load_balancer` block
- ⚠️ Nếu có destroy resources → STOP và review lại!

### Bước 5: Apply Changes
```powershell
# Option 1: Apply với confirm
terraform apply tfplan

# Option 2: Apply trực tiếp
terraform apply -auto-approve
```

**Thời gian:**
- Planning: ~10-30 giây
- Applying: ~2-3 phút
- ECS service update: ~1-2 phút
- Health checks pass: ~1-2 phút
- **Total: ~5-7 phút**

---

## ✅ Verify Sau Khi Apply

### 1. Kiểm Tra ECS Services Đã Update
```powershell
aws ecs describe-services `
  --cluster staging-mock-services `
  --services payment-gw ledger-svc fraud-detection `
  --region us-east-1 `
  --query 'services[*].[serviceName,loadBalancers]' `
  --output json
```

**Expected:** Mỗi service sẽ có `loadBalancers` array với 1 entry:
```json
{
  "targetGroupArn": "arn:aws:elasticloadbalancing:us-east-1:201023212626:targetgroup/staging-payment-tg/...",
  "containerName": "payment-gw",
  "containerPort": 3000
}
```

### 2. Kiểm Tra Target Groups
```powershell
# Payment
aws elbv2 describe-target-health `
  --target-group-arn arn:aws:elasticloadbalancing:us-east-1:201023212626:targetgroup/staging-payment-tg/9f7a927fea089ea3 `
  --region us-east-1

# Ledger
aws elbv2 describe-target-health `
  --target-group-arn arn:aws:elasticloadbalancing:us-east-1:201023212626:targetgroup/staging-ledger-tg/9f7a927fea089ea3 `
  --region us-east-1

# Fraud
aws elbv2 describe-target-health `
  --target-group-arn arn:aws:elasticloadbalancing:us-east-1:201023212626:targetgroup/staging-fraud-tg/... `
  --region us-east-1
```

**Expected:**
```json
{
  "TargetHealthDescriptions": [
    {
      "Target": {
        "Id": "10.1.x.x",
        "Port": 3000
      },
      "HealthCheckPort": "3000",
      "TargetHealth": {
        "State": "healthy"
      }
    }
  ]
}
```

### 3. Test ALB Endpoints
```powershell
# Get ALB DNS
$ALB_DNS = aws elbv2 describe-load-balancers `
  --names cdo-07-staging-vpc-alb `
  --query 'LoadBalancers[0].DNSName' `
  --output text `
  --region us-east-1

# Test health endpoints
curl "http://$ALB_DNS/health"
```

**Expected:** HTTP 200 với JSON response từ một trong 3 services

### 4. Test Specific Service Endpoints
```powershell
# Payment Gateway
curl -X POST "http://$ALB_DNS/payment/authorize" `
  -H "Content-Type: application/json" `
  -d '{\"amount\":100,\"currency\":\"USD\",\"customer_id\":\"test123\",\"payment_method\":\"card\"}'

# Ledger Service
curl -X POST "http://$ALB_DNS/ledger/entry" `
  -H "Content-Type: application/json" `
  -d '{\"account_id\":\"acc_123\",\"amount\":50.5,\"type\":\"debit\",\"description\":\"Test\"}'

# Fraud Detection
curl -X POST "http://$ALB_DNS/fraud/check" `
  -H "Content-Type: application/json" `
  -d '{\"transaction_id\":\"txn_123\",\"amount\":500,\"location\":\"US\",\"device_fingerprint\":\"abc123\"}'
```

**Expected:** Tất cả đều trả về HTTP 200 với JSON responses

---

## 🐛 Troubleshooting

### Lỗi: "Error acquiring the state lock"
**Nguyên nhân:** Có người khác đang chạy terraform hoặc lock bị stuck

**Giải pháp:**
```powershell
# Xem lock info
terraform force-unlock <LOCK_ID>
```

### Lỗi: "Error: Insufficient permissions"
**Nguyên nhân:** AWS credentials không đủ quyền

**Giải pháp:**
- Check IAM role/user có quyền ECS, ALB, CloudWatch
- Hoặc dùng admin credentials tạm thời

### Targets vẫn "Initial" sau 5 phút
**Nguyên nhân:** Health checks fail

**Debug:**
```powershell
# Xem ECS task logs
aws logs tail /ecs/payment-gw --follow --region us-east-1
aws logs tail /ecs/ledger-svc --follow --region us-east-1
aws logs tail /ecs/fraud-detection --follow --region us-east-1
```

**Tìm lỗi:**
- `ECONNREFUSED` (Kinesis connection issue)
- `Cannot find module` (Docker image issue)
- Port binding errors

---

## 📊 Expected Timeline

```
T+0:00  - Start terraform apply
T+0:10  - Terraform planning complete
T+0:30  - Terraform applying (updating ECS services)
T+2:00  - ECS services updated
T+2:30  - New tasks registered to target groups
T+3:00  - Health checks starting
T+4:30  - First health check pass (after 3 consecutive successes)
T+5:00  - All targets healthy ✅
```

---

## 🎯 Sau Khi Apply Thành Công

1. **Refresh AWS Console** → Target Groups → Sẽ thấy targets healthy
2. **Chạy K6 test lại** → Error rate < 5% ✅
3. **Update documentation** → Mark "Load Balancer Integration" as complete

---

**Last Updated:** 2026-07-01  
**Version:** 1.0  
**Author:** CDO-07 Team
