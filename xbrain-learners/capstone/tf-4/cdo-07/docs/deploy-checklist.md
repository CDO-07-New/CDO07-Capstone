# Deploy Checklist — CDO-07 · Task Force 4 · Foresight Lens

> **Account**: AWS TF4 shared · **Region**: `us-east-1` · **Terraform**: `>= 1.10`
> **State bucket**: `tf4-cdo07-tf-state-201023212626-use1`
> **Thứ tự deploy**: Bootstrap → Sandbox → Staging → (Prod khi demo)
> **Legend**: ⬜ chưa làm · ✅ xong · ❌ blocked

---

## PHASE 0 — Pre-flight (làm một lần trước tất cả)

### 0.1 Tooling local

| # | Việc cần làm | Command kiểm tra | Ghi chú |
|---|---|---|---|
| ⬜ | Terraform `>= 1.10, < 2.0` | `terraform version` | Khớp với `versions.tf` |
| ⬜ | AWS CLI v2 | `aws --version` | |
| ⬜ | Docker Desktop running | `docker info` | Build ECR images |
| ⬜ | Python 3.12 | `python --version` | Build Lambda ZIP |
| ⬜ | `jq` | `jq --version` | Dùng trong deploy scripts |

### 0.2 AWS credentials

| # | Việc cần làm | Ghi chú |
|---|---|---|
| ⬜ | Xác nhận đang dùng đúng AWS Account TF4 | `aws sts get-caller-identity` |
| ⬜ | IAM user/role có quyền chạy bootstrap (S3, KMS, IAM, ECR) | |
| ⬜ | Ghi lại Account ID vào đây: `____________________` | Dùng cho state bucket name |


### 0.3 GitHub repository setup

| # | Việc cần làm | Ghi chú |
|---|---|---|
| ⬜ | Branch protection bật trên `develop` và `main` | Require PR + 1 approval |
| ⬜ | GitHub Environments tạo: `staging`, `prod` | Settings → Environments |
| ⬜ | `prod` environment có required reviewer (Tech Lead) | |
| ⬜ | Secrets/Variables sẽ điền SAU khi bootstrap xong (xem Phase 1) | |

### 0.4 Slack webhook

| # | Việc cần làm | Ghi chú |
|---|---|---|
| ✅ | Tạo Incoming Webhook URL cho channel alerts | URLs đã có cho cả 3 environments |
| ⬜ | Test webhook sandbox: `curl -X POST -H 'Content-type: application/json' -d '{"text":"test sandbox"}' <SLACK_WEBHOOK_SANDBOX>` | Lấy URL từ SSM `/tf4-cdo07/sandbox/slack-webhook-url` |
| ⬜ | Test webhook staging: `curl -X POST -H 'Content-type: application/json' -d '{"text":"test staging"}' <SLACK_WEBHOOK_STAGING>` | Lấy URL từ SSM `/tf4-cdo07/staging/slack-webhook-url` |
| ⬜ | Test webhook prod: `curl -X POST -H 'Content-type: application/json' -d '{"text":"test prod"}' <SLACK_WEBHOOK_PROD>` | Lấy URL từ SSM `/tf4-cdo07/prod/slack-webhook-url` |
| ⬜ | **Tất cả 3 envs**: upload URL lên SSM (chạy `scripts/upload-slack-webhooks.ps1`) | Xem script bên dưới hoặc trong `infra/scripts/` |

---

## PHASE 1 — Bootstrap (chạy một lần, manual từ local)

> Tạo: S3 state bucket · KMS key · GitHub OIDC provider · IAM plan/deploy roles · ECR repos

### 1.1 Tạo file tfvars

```bash
cd xbrain-learners/capstone/tf-4/cdo-07/infra/bootstrap
cp terraform.tfvars.example terraform.tfvars
```


Điền các giá trị trong `terraform.tfvars`:

| Biến | Giá trị cần điền | Ví dụ |
|---|---|---|
| `state_bucket_name` | `tf4-cdo07-tf-state-<account-id>-use1` | `tf4-cdo07-tf-state-201023212626-use1` |
| `github_repository` | `<org>/<repo>` | `CDO-07/CDO-07-Capstone-phase2` |
| `github_allowed_branches` | `["develop", "main"]` | giữ nguyên |
| `github_allowed_environments` | `["staging", "prod"]` | giữ nguyên |

### 1.2 Apply bootstrap

| # | Command | Kết quả mong đợi |
|---|---|---|
| ⬜ | `terraform init` | Init OK, no backend (local state) |
| ⬜ | `terraform plan -out=bootstrap.tfplan` | ~20 resources to create |
| ⬜ | Review plan: S3 bucket, KMS key, OIDC provider, 2 IAM roles, 3 ECR repos | |
| ⬜ | `terraform apply bootstrap.tfplan` | Apply complete |

### 1.3 Ghi lại outputs (BẮT BUỘC)

Chạy `terraform output` và ghi lại:

| Output | Giá trị | Dùng ở đâu |
|---|---|---|
| `terraform_state_bucket` | `____________________` | Điền vào `versions.tf` các env |
| `terraform_state_kms_key_arn` | `____________________` | Ghi nhớ |
| `github_plan_role_arn` | `____________________` | → GitHub var `AWS_PLAN_ROLE_ARN` |
| `github_deploy_role_arn` | `____________________` | → GitHub var `AWS_DEPLOY_ROLE_ARN` |
| `ecr_repository_urls.payment-gw` | `____________________` | Mock service Payment Gateway |
| `ecr_repository_urls.ledger-svc` | `____________________` | Mock service Ledger |
| `ecr_repository_urls.fraud-detection` | `____________________` | Mock service Fraud Detection |


### 1.4 Cấu hình GitHub Actions

Vào repo → Settings → Secrets and Variables → Actions:

**Repository Variables** (không secret):

| Variable | Giá trị |
|---|---|
| `AWS_PLAN_ROLE_ARN` | ARN từ output `github_plan_role_arn` |

**Environment Variables** — điền cho cả `staging` VÀ `prod`:

| Variable | Staging | Prod |
|---|---|---|
| `AWS_DEPLOY_ROLE_ARN` | ARN từ `github_deploy_role_arn` | (same) |
| `STAGING_BASE_URL` | `http://<alb-dns>` (điền sau apply staging) | N/A |
| `STAGING_AI_IMAGE_URI` | ECR URI@sha256 của AI engine | N/A |
| `PROD_BASE_URL` | N/A | `http://<alb-dns>` |

### 1.5 Verify bootstrap

| # | Kiểm tra | Command |
|---|---|---|
| ⬜ | S3 bucket tồn tại, versioning ON, block public access ON | `aws s3api get-bucket-versioning --bucket tf4-cdo07-tf-state-<account-id>-use1` |
| ⬜ | KMS key alias tồn tại | `aws kms describe-key --key-id alias/tf4-cdo07-bootstrap` |
| ⬜ | OIDC provider tồn tại | `aws iam list-open-id-connect-providers` |
| ⬜ | 3 ECR repos tồn tại: `ingest-service`, `ingest-worker`, `ai-serving` | `aws ecr describe-repositories --query 'repositories[].repositoryName'` |
| ⬜ | IAM roles tồn tại: `tf4-cdo07-github-plan-role`, `tf4-cdo07-github-deploy-role` | `aws iam list-roles --query 'Roles[?contains(RoleName,\`tf4-cdo07\`)].RoleName'` |

---

## PHASE 1.5 — Build Mock Service Docker Images

> **⚠️ BẮT BUỘC: Phải build và push images VÀO ECR TRƯỚC KHI terraform apply**

### 1.5.1 Create ECR Repositories

```bash
# Create 3 ECR repositories for mock services
aws ecr create-repository --repository-name cdo-07-payment-gw --region us-east-1
aws ecr create-repository --repository-name cdo-07-ledger-svc --region us-east-1
aws ecr create-repository --repository-name cdo-07-fraud-detection --region us-east-1
```

| # | Repository | Status |
|---|---|---|
| ⬜ | `cdo-07-payment-gw` | Created |
| ⬜ | `cdo-07-ledger-svc` | Created |
| ⬜ | `cdo-07-fraud-detection` | Created |

### 1.5.2 Build and Push Docker Images

```bash
# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"

# Login to ECR
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# Navigate to mock services directory
cd xbrain-learners/capstone/tf-4/cdo-07/mock-services

# Build Payment Gateway
cd payment-gw
docker build -t cdo-07-payment-gw:latest .
docker tag cdo-07-payment-gw:latest ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/cdo-07-payment-gw:latest
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/cdo-07-payment-gw:latest

# Build Ledger Service
cd ../ledger-svc
docker build -t cdo-07-ledger-svc:latest .
docker tag cdo-07-ledger-svc:latest ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/cdo-07-ledger-svc:latest
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/cdo-07-ledger-svc:latest

# Build Fraud Detection
cd ../fraud-detection
docker build -t cdo-07-fraud-detection:latest .
docker tag cdo-07-fraud-detection:latest ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/cdo-07-fraud-detection:latest
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/cdo-07-fraud-detection:latest

cd ../..
```

| # | Image | Verify | Status |
|---|---|---|---|
| ⬜ | payment-gw | `aws ecr describe-images --repository-name cdo-07-payment-gw \| jq '.imageDetails[0].imageTags'` | |
| ⬜ | ledger-svc | `aws ecr describe-images --repository-name cdo-07-ledger-svc \| jq '.imageDetails[0].imageTags'` | |
| ⬜ | fraud-detection | `aws ecr describe-images --repository-name cdo-07-fraud-detection \| jq '.imageDetails[0].imageTags'` | |

### 1.5.3 Verify Image Contents

```bash
# Pull and inspect one image to verify it works
docker pull ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/cdo-07-payment-gw:latest
docker run --rm ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/cdo-07-payment-gw:latest node --version
```

| # | Check | Expected | Status |
|---|---|---|---|
| ⬜ | Image contains Node.js | Node version printed | |
| ⬜ | Image has app.js | `docker run --rm <image> ls -la` shows app.js | |
| ⬜ | Image has dependencies | node_modules exists | |

---

## PHASE 2 — Lambda Artifacts Build (local, trước khi terraform apply env)

> Lambda Transformer và Window Feeder cần ZIP artifact trước khi `terraform apply`.

### 2.1 Lambda Transformer

Transformer tự đóng gói trong Terraform qua `archive_file` — không cần build thủ công.
Chỉ cần đảm bảo file tồn tại:

| # | Kiểm tra | |
|---|---|---|
| ⬜ | `infra/modules/lambda/transformer/lambda/transformer_handler.py` tồn tại | ✅ đã có |
| ⬜ | **[QUAN TRỌNG]** Uncomment boto3 Timestream write trong `transformer_handler.py` | Hiện là stub — chưa ghi thực vào Timestream |


### 2.2 Window Feeder ZIP — BẮT BUỘC (file này chưa tồn tại)

`lambda-scheduled-function` module đọc `package_path = ".../lambda/window-feeder/build/window-feeder.zip"`.
File này **chưa có** trong repo — phải build thủ công trước khi `terraform apply`.

```bash
# Chạy từ repo root (Windows — dùng Git Bash hoặc WSL)
cd xbrain-learners/capstone/tf-4/cdo-07/infra/lambda/window-feeder

# Tạo thư mục build
mkdir -p build/package

# Cài dependencies vào package dir
pip install -r ../requirements.txt -t build/package/

# Copy source vào package
cp app.py build/package/

# Tạo ZIP
cd build/package
zip -r ../window-feeder.zip .
cd ../..
```

Kết quả: `infra/lambda/window-feeder/build/window-feeder.zip`

| # | Kiểm tra | |
|---|---|---|
| ⬜ | `infra/lambda/window-feeder/build/window-feeder.zip` tồn tại | |
| ⬜ | ZIP chứa `app.py` + `boto3/`, `requests/` | `unzip -l build/window-feeder.zip \| head -20` |
| ⬜ | Thêm `infra/lambda/window-feeder/build/` vào `.gitignore` nếu chưa có | |

### 2.3 Fail-Open Fallback

Fallback handler tự đóng gói trong Terraform qua `archive_file` — không cần build thủ công.

| # | Kiểm tra | |
|---|---|---|
| ⬜ | `infra/modules/lambda/fail-open-fallback/lambda/fallback_handler.py` tồn tại | ✅ đã có |

### 2.4 Cost Circuit Breaker

| # | Kiểm tra | |
|---|---|---|
| ⬜ | `infra/modules/cost-circuit-breaker/lambda/cost_circuit_breaker.py` tồn tại | Verify file này có |

---

## PHASE 3 — Timestream InfluxDB (managed by Terraform — không cần CLI thủ công)

> **ĐÃ FIX**: Codebase đã migration từ Timestream for LiveAnalytics (bị blocked: `AccessDeniedException: Only existing Timestream for LiveAnalytics customers can access the service`) sang **Amazon Timestream for InfluxDB**.
>
> **Timestream for InfluxDB** được provisioned hoàn toàn bởi Terraform trong `modules/data/main.tf` thông qua resource `aws_timestreaminfluxdb_db_instance`.
>
> **KHÔNG cần chạy `aws timestream-write create-database` hay `aws timestream-write create-table` nữa.**

### 3.1 Những gì Terraform tự tạo

| Resource | Tên | Ghi chú |
|---|---|---|
| `aws_timestreaminfluxdb_db_instance` | `tf4-cdo07-<env>-influxdb` | Single-AZ, `db.influx.medium`, VPC-private |
| `aws_ssm_parameter` | `/<project>/<env>/influxdb-endpoint` | Full HTTPS URL cho Lambda |
| `aws_ssm_parameter` | `/<project>/<env>/influxdb-secret-arn` | ARN của Secrets Manager entry chứa operator token |
| `aws_ssm_parameter` | `/<project>/<env>/influxdb-bucket` | `service-metrics` |
| `aws_ssm_parameter` | `/<project>/<env>/influxdb-org` | `cdo-07` |

### 3.2 Auth flow

AWS tự động tạo Secrets Manager entry khi tạo InfluxDB instance, chứa JSON:
```json
{ "operator_token": "<token>", "password": "<admin-password>" }
```
Lambda Transformer và Lambda Window Feeder đọc `operator_token` từ đó tại cold start.

### 3.3 Verify sau `terraform apply`

```bash
# Kiểm tra instance tồn tại
aws timestream-influxdb list-db-instances --region us-east-1

# Kiểm tra SSM parameter endpoint
aws ssm get-parameter --name /tf4-cdo07/sandbox/influxdb-endpoint

# Kiểm tra Secrets Manager entry tồn tại (không đọc giá trị)
aws ssm get-parameter --name /tf4-cdo07/sandbox/influxdb-secret-arn
```

| # | Kiểm tra | |
|---|---|---|
| ⬜ | InfluxDB instance status = `AVAILABLE` | `aws timestream-influxdb list-db-instances` |
| ⬜ | SSM parameter `/tf4-cdo07/sandbox/influxdb-endpoint` tồn tại | |
| ⬜ | SSM parameter `/tf4-cdo07/sandbox/influxdb-secret-arn` tồn tại | |
| ⬜ | Lambda Transformer env vars chứa `INFLUXDB_URL`, `INFLUXDB_BUCKET`, `INFLUXDB_ORG`, `INFLUXDB_SECRET_ARN` | `aws lambda get-function-configuration --function-name tf4-cdo07-sandbox-transformer` |
| ⬜ | Lambda Window Feeder env vars chứa `INFLUXDB_URL` (không còn `TIMESTREAM_*`) | `aws lambda get-function-configuration --function-name tf4-cdo07-sandbox-window-feeder` |

### 3.4 Smoke test InfluxDB write/read

```bash
# Lấy endpoint và token
INFLUX_ENDPOINT=$(aws ssm get-parameter --name /tf4-cdo07/sandbox/influxdb-endpoint --query Parameter.Value --output text)
SECRET_ARN=$(aws ssm get-parameter --name /tf4-cdo07/sandbox/influxdb-secret-arn --query Parameter.Value --output text)
INFLUX_TOKEN=$(aws secretsmanager get-secret-value --secret-id $SECRET_ARN --query SecretString --output text | python -c "import sys,json; print(json.load(sys.stdin)['operator_token'])")

# Test write (Line Protocol)
curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${INFLUX_ENDPOINT}/api/v2/write?org=cdo-07&bucket=service-metrics&precision=ns" \
  -H "Authorization: Token ${INFLUX_TOKEN}" \
  -H "Content-Type: text/plain" \
  --data-raw 'cpu_usage_percent,service_id=payment-gateway,tenant_id=tnt-test value=45.2 '"$(date +%s%N)"
# Mong đợi: HTTP 204

# Test query (Flux)
curl -s \
  -X POST "${INFLUX_ENDPOINT}/api/v2/query?org=cdo-07" \
  -H "Authorization: Token ${INFLUX_TOKEN}" \
  -H "Content-Type: application/vnd.flux" \
  -H "Accept: application/csv" \
  --data-raw 'from(bucket:"service-metrics") |> range(start: -5m) |> limit(n:5)'
# Mong đợi: CSV rows với data
```


---

## PHASE 4 — Sandbox Deploy (môi trường test đầu tiên)

### 4.0 Pre-deployment Configuration Updates

**⚠️ QUAN TRỌNG: Cập nhật các config sau TRƯỚC KHI `terraform plan`**

#### 4.0.1 Update Public Subnet Variables

Edit `infra/environments/sandbox/main.tf`:

```hcl
module "networking" {
  source = "../../modules/networking"

  vpc_name              = "cdo-07-sandbox-vpc"
  vpc_cidr              = "10.0.0.0/16"
  private_subnet_cidr_a = "10.0.1.0/24"
  private_subnet_cidr_b = "10.0.2.0/24"
  public_subnet_cidr_a  = "10.0.101.0/24"  # ← THÊM DÒNG NÀY
  public_subnet_cidr_b  = "10.0.102.0/24"  # ← THÊM DÒNG NÀY
  enable_vpc_endpoints  = true

  tags = local.common_tags
}
```

| # | Kiểm tra | |
|---|---|---|
| ⬜ | Added `public_subnet_cidr_a = "10.0.101.0/24"` | |
| ⬜ | Added `public_subnet_cidr_b = "10.0.102.0/24"` | |

#### 4.0.2 Update ECR Image URIs

Edit `infra/environments/sandbox/locals.tf`:

```hcl
# Verify these URIs match your ECR repositories
ecr_image_uri_payment = "${local.ecr_account_id}.dkr.ecr.${local.ecr_region}.amazonaws.com/cdo-07-payment-gw:latest"
ecr_image_uri_ledger  = "${local.ecr_account_id}.dkr.ecr.${local.ecr_region}.amazonaws.com/cdo-07-ledger-svc:latest"
ecr_image_uri_fraud   = "${local.ecr_account_id}.dkr.ecr.${local.ecr_region}.amazonaws.com/cdo-07-fraud-detection:latest"
```

| # | Kiểm tra | Command |
|---|---|---|
| ⬜ | ECR URIs correct | `aws ecr describe-repositories --query 'repositories[].repositoryName'` |
| ⬜ | Images exist in ECR | `aws ecr describe-images --repository-name cdo-07-payment-gw` |

#### 4.0.3 Update KMS Key ARN

Edit `infra/environments/sandbox/locals.tf`:

```hcl
kms_key_arn = "arn:aws:kms:us-east-1:${data.aws_caller_identity.current.account_id}:key/<YOUR_KEY_ID>"
```

| # | Kiểm tra | Command |
|---|---|---|
| ⬜ | KMS key exists | `aws kms describe-key --key-id alias/tf4-cdo07-bootstrap` |
| ⬜ | Key ARN updated in locals.tf | Copy ARN from bootstrap output |

### 4.1 Terraform validate

```bash
cd xbrain-learners/capstone/tf-4/cdo-07/infra/environments/sandbox
terraform init
terraform validate
terraform fmt -check -recursive ../../
```

| # | Kiểm tra | |
|---|---|---|
| ⬜ | `terraform init` — backend S3 kết nối được | |
| ⬜ | `terraform validate` — không có lỗi | |
| ⬜ | `terraform fmt -check` — không có diff | |

### 4.2 Terraform plan sandbox

```bash
terraform plan -out=sandbox.tfplan
```

| # | Kiểm tra plan | |
|---|---|---|
| ⬜ | Không có `destroy` ngoài ý muốn | |
| ⬜ | KMS key alias `tf4-cdo07-bootstrap` resolve được (data source) | |
| ⬜ | Module `networking` — VPC `10.0.0.0/16`, **2 private + 2 public subnets**, VPC endpoints | ✅ |
| ⬜ | ALB — **internet-facing** (internal=false) trong **public subnets** | ✅ |
| ⬜ | Security Groups — Lambda → ALB rule exists | ✅ |
| ⬜ | Module `streaming` — 1 Kinesis stream, KMS encrypted | |
| ⬜ | Module `cost_circuit_breaker` — SSM param `/tf4-cdo07/sandbox/inference_enabled` = `true` | |
| ⬜ | Module `transformer` — Lambda function + event source mapping | |
| ⬜ | Module `window_feeder` — Lambda + EventBridge rule `rate(5 minutes)` | |
| ⬜ | Module `fail_open_fallback` — Lambda + SNS subscription | |
| ⬜ | Module `ai_engine` — ECS task definition/service | |
| ⬜ | Module `mock_services` — 3 ECS services (payment-gw, ledger-svc, fraud-detection) | ✅ |
| ⬜ | InfluxDB instance — db.influx.medium, 20GB storage | |
| ⬜ | Không có resource nào reference file ZIP chưa tồn tại | |

### 4.3 Apply sandbox

```bash
terraform apply sandbox.tfplan
```

| # | Kiểm tra sau apply | Command |
|---|---|---|
| ⬜ | Apply hoàn thành không có error | |
| ⬜ | VPC tồn tại | `aws ec2 describe-vpcs --filters "Name=tag:Environment,Values=sandbox"` |
| ⬜ | Kinesis stream ACTIVE | `aws kinesis describe-stream-summary --stream-name tf4-cdo07-sandbox-ingest-stream` |
| ⬜ | SSM parameter tồn tại, value = `true` | `aws ssm get-parameter --name /tf4-cdo07/sandbox/inference_enabled --with-decryption` |
| ⬜ | Lambda Transformer tồn tại | `aws lambda get-function --function-name tf4-cdo07-sandbox-transformer` |
| ⬜ | Lambda Window Feeder tồn tại | `aws lambda get-function --function-name tf4-cdo07-sandbox-window-feeder` |
| ⬜ | EventBridge rule ENABLED | `aws events describe-rule --name tf4-cdo07-sandbox-window-feeder-schedule` |
| ⬜ | Lambda Fail-Open Fallback tồn tại | `aws lambda get-function --function-name tf4-cdo07-sandbox-fail-open-fallback` |
| ⬜ | Budget alarm tạo được | `aws budgets describe-budgets --account-id <account-id>` |


### 4.4 Smoke test sandbox — end-to-end data flow

| # | Test | Cách test | Kết quả mong đợi |
|---|---|---|---|
| ⬜ | Gửi metric giả vào Kinesis | `aws kinesis put-record --stream-name tf4-cdo07-sandbox-ingest-stream --partition-key payment-gateway --data '{"service_id":"payment-gateway","metric_name":"cpu_usage","value":45.2,"timestamp":"2026-06-29T00:00:00Z"}'` | `ShardId` returned |
| ⬜ | Lambda Transformer invoke | Chờ 60s rồi xem CloudWatch Logs `/aws/lambda/tf4-cdo07-sandbox-transformer` | Log `Processed X records` |
| ⬜ | Query InfluxDB | Lấy endpoint + token từ SSM/Secrets Manager (xem Phase 3.4), chạy Flux query | Row data returned |
| ⬜ | Invoke Window Feeder thủ công | `aws lambda invoke --function-name tf4-cdo07-sandbox-window-feeder --payload '{"source":"manual"}' /tmp/out.json` | `statusCode: 200` |
| ⬜ | Audit log xuất hiện trong S3 | `aws s3 ls s3://<audit-bucket>/window-feeder/ --recursive` | `.json` file |
| ⬜ | Invoke Fail-Open Fallback thủ công | `aws lambda invoke --function-name tf4-cdo07-sandbox-fail-open-fallback --payload '{}' /tmp/out.json` | `statusCode: 200` |
| ⬜ | Mock services ECS tasks running | `aws ecs list-tasks --cluster cdo-07-sandbox-ecs` | 4 tasks (3 mock + 1 AI engine) |
| ⬜ | Mock services health checks | `curl http://<alb-dns>/payment/health`, `/ledger/health`, `/fraud/health` | All return HTTP 200 |
| ⬜ | AI Engine ALB health check | `curl http://<alb-dns>/v1/health` | HTTP 200 |
| ⬜ | AI Engine predict endpoint | `curl -X POST http://<alb-dns>/v1/predict -d '{"rows":[]}'` | JSON response |

### 4.5 Verify ALB Configuration

**⚠️ QUAN TRỌNG: Kiểm tra ALB name và accessibility**

```bash
# ALB name should be: cdo-07-sandbox-vpc-alb (NOT cdo-07-sandbox-alb)
aws elbv2 describe-load-balancers \
  --names cdo-07-sandbox-vpc-alb \
  --query 'LoadBalancers[0].{Scheme:Scheme,DNS:DNSName}' \
  --output table
```

| # | Kiểm tra | Expected | Status |
|---|---|---|---|
| ⬜ | ALB name | `cdo-07-sandbox-vpc-alb` | ✅ |
| ⬜ | ALB scheme | `internet-facing` | ✅ |
| ⬜ | ALB subnets | 2 public subnets | ✅ |
| ⬜ | ALB security group | Allows 0.0.0.0/0:80 | ✅ |
| ⬜ | Test from Internet | `curl http://<alb-dns>/payment/health` from local machine | Should work |

### 4.6 K6 Load Test Verification

**Test K6 can connect to ALB from GitHub Actions**

```bash
# Verify K6 workflow uses correct ALB name
cat .github/workflows/k6-load-tests.yml | grep "cdo-07-.*-vpc-alb"
```

| # | Kiểm tra | Expected | Status |
|---|---|---|---|
| ⬜ | K6 workflow ALB name | `cdo-07-${ENV}-vpc-alb` | ✅ Fixed |
| ⬜ | Manual K6 test from local | `cd k6-tests && k6 run -e ALB_DNS=http://<alb-dns> scenario-1-gradual-drift.js` | Connects successfully |

---

## PHASE 4.7 — Post-Deployment Health Checks

### Mock Services Telemetry Flow

```bash
# Test full telemetry pipeline
ALB_DNS=$(cd infra/environments/sandbox && terraform output -raw alb_dns_name)

# 1. Send request to mock service
curl -X POST http://$ALB_DNS/payment/authorize \
  -H "Content-Type: application/json" \
  -d '{"amount": 100, "currency": "USD", "customer_id": "test-123"}'

# 2. Wait 30-60 seconds, then check Transformer logs
aws logs tail /aws/lambda/tf4-cdo07-sandbox-transformer --since 2m

# 3. Check InfluxDB has data
# (Use script from Phase 3.4 to query InfluxDB)

# 4. Wait 5 minutes, check Window Feeder logs
aws logs tail /aws/lambda/tf4-cdo07-sandbox-window-feeder --since 10m
```

| # | Check | Expected | Status |
|---|---|---|---|
| ⬜ | Mock service responds | HTTP 200 with transaction_id | |
| ⬜ | Kinesis receives records | Check Kinesis metrics | |
| ⬜ | Transformer processes | Log: "Processed X records" | |
| ⬜ | InfluxDB has data | Query returns rows | |
| ⬜ | Window Feeder runs | Log: "Querying InfluxDB" | |
| ⬜ | AI Engine called | Log: "Calling AI Engine" | |
| ⬜ | Audit log created | S3 bucket has new file | |

---

## PHASE 5 — Staging Deploy (via GitHub Actions)

> Staging deploy chạy tự động khi merge vào `develop`. Có thể trigger manual.

### 5.1 Pre-deploy checks

| # | Kiểm tra | |
|---|---|---|
| ⬜ | GitHub variable `AWS_PLAN_ROLE_ARN` đã set | Settings → Variables |
| ⬜ | GitHub environment `staging` có variable `AWS_DEPLOY_ROLE_ARN` | |
| ⬜ | `STAGING_AI_IMAGE_URI` set (ECR URI@sha256 từ AI team) hoặc để trống để skip AI deploy | |
| ⬜ | Window Feeder ZIP đã build và commit (hoặc build trong CI) | |
| ⬜ | `terraform-plan.yml` đã chạy pass trên PR | |
| ⬜ | `security-scan.yml` đã chạy pass (Gitleaks, Trivy, Checkov) | |
| ⬜ | `build-test.yml` đã chạy pass | |

### 5.2 Trigger staging deploy

```
Push to develop → deploy-staging.yml tự chạy
HOẶC: Actions → deploy-staging → Run workflow
```

| # | Bước trong workflow | Kết quả mong đợi |
|---|---|---|
| ⬜ | `Validate deployment prerequisites` | `deploy_ready=true` |
| ⬜ | `Build CDO service images` | Images build & push thành công (nếu Dockerfile tồn tại) |
| ⬜ | `Terraform apply staging` | Apply complete |
| ⬜ | `Deploy ingest-service rolling update` | Không lỗi (hoặc skip nếu chưa có Dockerfile) |
| ⬜ | `Deploy ingest-worker rolling update` | Không lỗi (hoặc skip) |
| ⬜ | `Deploy ai-serving blue/green` | Không lỗi (hoặc skip nếu không có `STAGING_AI_IMAGE_URI`) |
| ⬜ | `Smoke test staging` | Script pass |

### 5.3 Verify staging

| # | Kiểm tra | Command |
|---|---|---|
| ⬜ | Tất cả ECS services RUNNING | `aws ecs list-services --cluster tf4-cdo07-staging` |
| ⬜ | ALB healthy | `aws elbv2 describe-target-health --target-group-arn <arn>` |
| ⬜ | Kinesis stream ACTIVE | `aws kinesis describe-stream-summary --stream-name tf4-cdo07-staging-ingest-stream` |
| ⬜ | Window Feeder EventBridge rule ENABLED | `aws events describe-rule --name tf4-cdo07-staging-window-feeder-schedule` |
| ⬜ | SNS → Slack: gửi test message | Slack channel nhận được |
| ⬜ | Điền `STAGING_BASE_URL` vào GitHub environment variable | `http://<alb-dns-staging>` |


---

## PHASE 6 — Integration Test staging (E2E với AI team)

| # | Test | Kết quả mong đợi |
|---|---|---|
| ⬜ | Mock Services gửi metric liên tục vào Kinesis | Kinesis metrics > 0 records/min |
| ⬜ | Lambda Transformer ghi được vào Timestream | `select count(*) from staging table` > 0 |
| ⬜ | Window Feeder gọi được AI Engine `/v1/predict` | AI trả JSON `{drift_detected, confidence, recommendation}` |
| ⬜ | Kết quả AI ghi audit vào S3 | File xuất hiện trong `s3://<audit-bucket>/window-feeder/` |
| ⬜ | Drift alert gửi lên Slack khi `drift_detected=true` | Slack message xuất hiện |
| ⬜ | **Fail-Open test**: Tắt AI Engine ECS service → Window Feeder timeout → Fallback Lambda kích hoạt | SNS alert + Slack message từ `fail_open_fallback` |
| ⬜ | **Cost Circuit Breaker test**: Set SSM param `inference_enabled=false` → Window Feeder exit sớm | Log: `Inference disabled via SSM parameter` |
| ⬜ | Reset: Set SSM param `inference_enabled=true` | Window Feeder hoạt động trở lại |
| ⬜ | Grafana dashboard hiển thị metric từ Timestream | Dashboard load, không 404 |
| ⬜ | Grafana annotation xuất hiện khi Fallback trigger | Annotation marker trên dashboard |

### 6.1 Load test (k6) — 100 RPS

| # | Test | |
|---|---|---|
| ⬜ | k6 script viết sẵn target mock service ALB | |
| ⬜ | Chạy 100 RPS trong 5 phút | `k6 run --vus 100 --duration 5m load-test.js` |
| ⬜ | Kinesis không bị throttle (GetRecords.IteratorAgeMilliseconds < 5000ms) | CloudWatch metric |
| ⬜ | Lambda Transformer error rate < 1% | CloudWatch Errors / Invocations |
| ⬜ | AI Engine P99 latency < 500ms | ALB target response time |
| ⬜ | Không vượt budget $200 | AWS Budgets dashboard |

---

## PHASE 7 — Production Deploy (manual-dispatch, khi demo)

> Prod deploy yêu cầu manual confirmation `DEPLOY_PROD` + Git SHA đã pass staging.

### 7.1 Pre-prod gate

| # | Kiểm tra | |
|---|---|---|
| ⬜ | Git SHA cần deploy đã có successful `deploy-staging` run | `gh run list --workflow deploy-staging.yml --status success` |
| ⬜ | AI image URI đã có sha256 digest (`repo@sha256:...`) | |
| ⬜ | `prod` environment reviewer đã approve | GitHub Environment protection |
| ⬜ | Prod Slack webhook đã upload lên SSM `/tf4-cdo07/prod/slack-webhook-url` | ✅ URL đã có — chạy `scripts/upload-slack-webhooks.ps1` |
| ⬜ | `PROD_BASE_URL` đã set trong GitHub prod environment | |

### 7.2 Trigger prod deploy

```
Actions → deploy-prod → Run workflow
  git_sha: <full 40-char SHA>
  ai_image_uri: <ECR repo@sha256:digest>
  confirm: DEPLOY_PROD
```

| # | Bước trong workflow | Kết quả mong đợi |
|---|---|---|
| ⬜ | `Validate manual confirmation` | Pass |
| ⬜ | `Verify staging deployment passed for Git SHA` | Staging run found |
| ⬜ | `Terraform apply production` | Apply complete |
| ⬜ | `Deploy ingest-service rolling update` | Rolling update success |
| ⬜ | `Deploy ingest-worker rolling update` | Rolling update success |
| ⬜ | `Deploy ai-serving blue/green` | CodeDeploy blue/green success |
| ⬜ | `Smoke test production` | Pass |

### 7.3 Post-deploy verify prod

| # | Kiểm tra | |
|---|---|---|
| ⬜ | Prod ECS services tất cả RUNNING | |
| ⬜ | ALB target group health: 0 unhealthy | |
| ⬜ | CodeDeploy deployment status: SUCCEEDED | |
| ⬜ | Blue environment đã terminate sau bake period | |
| ⬜ | Window Feeder đang chạy theo schedule 5 phút | |
| ⬜ | Grafana prod dashboard accessible | |


---

## PHASE 8 — Post-deploy Housekeeping

| # | Việc cần làm | |
|---|---|---|
| ⬜ | Gắn `git tag final` sau khi demo pass (deadline 8h T5 02/07) | `git tag final && git push origin final` |
| ⬜ | Scale sandbox desired count = 0 nếu không dùng | Tiết kiệm chi phí |
| ⬜ | Xác nhận Drift Detection workflow bật (`drift-detection.yml`) | Actions → Enable workflow |
| ⬜ | Xác nhận `07_test_eval_report.md` có screenshot kết quả load test | |
| ⬜ | Xác nhận `05_cost_analysis.md` cập nhật actual cost từ AWS Cost Explorer | |

---

## KNOWN GAPS — phải fix trước khi apply

Các vấn đề phát hiện khi đọc code, cần giải quyết trước khi deploy thực tế:

| # | Vấn đề | File | Độ ưu tiên | Cách fix |
|---|---|---|---|---|
| ✅ | Lambda Transformer đã ghi thực vào **Timestream InfluxDB** via Line Protocol | `modules/lambda/transformer/lambda/transformer_handler.py` | ~~🔴 Critical~~ | Đã rewrite — dùng HTTP write API |
| ✅ | **Timestream for InfluxDB** được provisioned trong Terraform | `modules/data/main.tf` | ~~🔴 Critical~~ | Đã thêm `aws_timestreaminfluxdb_db_instance` |
| ✅ | Window Feeder dùng **Flux query API** thay vì `timestream-write` | `lambda/window-feeder/app.py` | ~~🔴 Critical~~ | Đã rewrite — dùng HTTP Flux API |
| ❌ | Window Feeder ZIP **chưa tồn tại** | `lambda/window-feeder/build/window-feeder.zip` | 🔴 Critical | Build theo hướng dẫn Phase 2.2 |
| ⚠️ | `sns_to_slack` module nhận `slack_webhook_url` hardcode `PLACEHOLDER` | `environments/sandbox/main.tf`, `staging/main.tf` | 🟡 High | Thay bằng URL thực hoặc SSM parameter lookup |
| ⚠️ | Prod `sns_to_slack` nhận `slack_webhook_parameter_name` nhưng module có thể chưa support SSM lookup | `environments/prod/main.tf` | 🟡 High | Kiểm tra `modules/sns_to_slack/variables.tf` |
| ⚠️ | Scripts `deploy-ecs-rolling.sh`, `deploy-codedeploy-bluegreen.sh`, `smoke-test.sh` **chưa tồn tại** | `scripts/` | 🟡 High | Tạo scripts hoặc CI sẽ skip (workflow có `if` guard) |
| ℹ️ | Services `ingest-service`, `ingest-worker` **chưa có source code** | `services/` dir không tồn tại | 🟢 Low | CI sẽ tự skip khi không tìm thấy Dockerfile |
| ℹ️ | `deploy role` trong IAM không có `lambda:*` — không thể deploy Lambda qua CI | `bootstrap/iam.tf` | 🟢 Medium | Thêm `lambda:*` vào `AllowApplicationDeployment` statement |
| ℹ️ | IAM deploy role cần thêm `timestream-influxdb:*` và `secretsmanager:GetSecretValue` | `bootstrap/iam.tf` | 🟡 High | Thêm vào IAM policy để Terraform apply có thể tạo InfluxDB instance |

---

## Quick Reference — Thứ tự lệnh deploy sandbox từ local

```bash
# 1. Build Window Feeder ZIP
cd xbrain-learners/capstone/tf-4/cdo-07/infra/lambda/window-feeder
mkdir -p build/package
pip install -r ../requirements.txt -t build/package/
cp app.py build/package/
cd build/package && zip -r ../window-feeder.zip . && cd ../..

# 2. Apply sandbox (Terraform tự tạo InfluxDB instance + SSM params + Secrets Manager)
cd infra/environments/sandbox
terraform init
terraform plan -out=sandbox.tfplan
terraform apply sandbox.tfplan
# InfluxDB instance sẽ mất ~10-15 phút để chuyển sang AVAILABLE

# 3. Verify InfluxDB
aws timestream-influxdb list-db-instances --region us-east-1
aws ssm get-parameter --name /tf4-cdo07/sandbox/influxdb-endpoint

# 4. Smoke test — gửi metric vào Kinesis → Transformer → InfluxDB
aws kinesis put-record --stream-name tf4-cdo07-sandbox-ingest-stream \
  --partition-key payment-gateway \
  --data '{"service_id":"payment-gateway","metric_type":"cpu_usage","value":45.2,"ts":"2026-06-29T00:00:00Z","tenant_id":"tnt-sandbox"}'

# 5. Test Window Feeder
aws lambda invoke --function-name tf4-cdo07-sandbox-window-feeder \
  --payload '{}' /tmp/out.json && type /tmp/out.json
```

---

