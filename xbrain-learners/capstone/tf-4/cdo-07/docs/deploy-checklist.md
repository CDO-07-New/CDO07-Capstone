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
| ⬜ | Tạo Incoming Webhook URL cho channel alerts | `https://hooks.slack.com/services/...` |
| ⬜ | Test webhook: `curl -X POST -d '{"text":"test"}' <URL>` | |
| ⬜ | Lưu URL — sẽ điền vào `slack_webhook_url` của sandbox/staging | |
| ⬜ | **Prod**: upload URL lên SSM: `aws ssm put-parameter --name /tf4-cdo07/prod/slack-webhook-url --type SecureString --value "<URL>"` | Prod module đọc từ SSM |

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
| `ecr_repository_urls.ingest-service` | `____________________` | |
| `ecr_repository_urls.ingest-worker` | `____________________` | |
| `ecr_repository_urls.ai-serving` | `____________________` | |


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

## PHASE 3 — Timestream Database/Table (chưa có Terraform module)

> **GAP**: Không có Terraform resource nào tạo Timestream database/table trong codebase.
> Lambda Transformer và Window Feeder đều expect `tf4-cdo07-<env>/service-metrics`.

### 3.1 Tạo thủ công (temporary) — hoặc tạo Terraform resource

**Option A — AWS CLI (nhanh để test):**

```bash
# Tạo database
aws timestream-write create-database \
  --database-name "tf4-cdo07-sandbox" \
  --kms-key-id "alias/tf4-cdo07-bootstrap"

# Tạo table với retention
aws timestream-write create-table \
  --database-name "tf4-cdo07-sandbox" \
  --table-name "service-metrics" \
  --retention-properties "MemoryStoreRetentionPeriodInHours=48,MagneticStoreRetentionPeriodInDays=90"
```

Lặp lại cho `tf4-cdo07-staging` và `tf4-cdo07-prod`.

**Option B — Thêm resource vào Terraform module `data`** (recommended):

| # | Việc cần làm | |
|---|---|---|
| ⬜ | Thêm `aws_timestreamwrite_database` và `aws_timestreamwrite_table` vào `modules/data/main.tf` | |
| ⬜ | Export outputs: `timestream_database_name`, `timestream_table_name` | |
| ⬜ | Update `environments/*/main.tf` nếu cần truyền thêm biến | |


---

## PHASE 4 — Sandbox Deploy (môi trường test đầu tiên)

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
| ⬜ | Module `networking` — VPC `10.0.0.0/16`, 2 private subnets, VPC endpoints | |
| ⬜ | Module `streaming` — 1 Kinesis stream, KMS encrypted | |
| ⬜ | Module `cost_circuit_breaker` — SSM param `/tf4-cdo07/sandbox/inference_enabled` = `true` | |
| ⬜ | Module `transformer` — Lambda function + event source mapping | |
| ⬜ | Module `window_feeder` — Lambda + EventBridge rule `rate(5 minutes)` | |
| ⬜ | Module `fail_open_fallback` — Lambda + SNS subscription | |
| ⬜ | Module `ai_engine` — ECS task definition/service | |
| ⬜ | Module `mock_services` — 3 ECS services (payment-gw, ledger, fraud) | |
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
| ⬜ | Query Timestream | `aws timestream-query query --query-string "SELECT * FROM \"tf4-cdo07-sandbox\".\"service-metrics\" LIMIT 5"` | Row data returned |
| ⬜ | Invoke Window Feeder thủ công | `aws lambda invoke --function-name tf4-cdo07-sandbox-window-feeder --payload '{"source":"manual"}' /tmp/out.json` | `statusCode: 200` |
| ⬜ | Audit log xuất hiện trong S3 | `aws s3 ls s3://<audit-bucket>/window-feeder/ --recursive` | `.json` file |
| ⬜ | Invoke Fail-Open Fallback thủ công | `aws lambda invoke --function-name tf4-cdo07-sandbox-fail-open-fallback --payload '{}' /tmp/out.json` | `statusCode: 200` |
| ⬜ | Mock services ECS tasks running | `aws ecs list-tasks --cluster tf4-cdo07-sandbox` | 3 tasks running |
| ⬜ | AI Engine ALB health check | `curl http://<alb-dns>/health` | HTTP 200 |
| ⬜ | AI Engine predict endpoint | `curl -X POST http://<alb-dns>/v1/predict -d '{"rows":[]}'` | JSON response |

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
| ⬜ | Prod Slack webhook đã upload lên SSM `/tf4-cdo07/prod/slack-webhook-url` | |
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
| ❌ | Lambda Transformer là **stub** — chưa ghi thực vào Timestream | `modules/lambda/transformer/lambda/transformer_handler.py` | 🔴 Critical | Uncomment + implement boto3 `timestream-write` call |
| ❌ | Window Feeder ZIP **chưa tồn tại** | `lambda/window-feeder/build/window-feeder.zip` | 🔴 Critical | Build theo hướng dẫn Phase 2.2 |
| ❌ | Không có Terraform resource tạo **Timestream database/table** | Không có file nào | 🔴 Critical | Tạo thủ công (CLI) hoặc thêm vào `modules/data/` |
| ⚠️ | `sns_to_slack` module nhận `slack_webhook_url` hardcode `PLACEHOLDER` | `environments/sandbox/main.tf`, `staging/main.tf` | 🟡 High | Thay bằng URL thực hoặc SSM parameter lookup |
| ⚠️ | Prod `sns_to_slack` nhận `slack_webhook_parameter_name` nhưng module có thể chưa support SSM lookup | `environments/prod/main.tf` | 🟡 High | Kiểm tra `modules/sns_to_slack/variables.tf` |
| ⚠️ | Scripts `deploy-ecs-rolling.sh`, `deploy-codedeploy-bluegreen.sh`, `smoke-test.sh` **chưa tồn tại** | `scripts/` | 🟡 High | Tạo scripts hoặc CI sẽ skip (workflow có `if` guard) |
| ℹ️ | Services `ingest-service`, `ingest-worker` **chưa có source code** | `services/` dir không tồn tại | 🟢 Low | CI sẽ tự skip khi không tìm thấy Dockerfile |
| ℹ️ | `deploy role` trong IAM không có `lambda:*` — không thể deploy Lambda qua CI | `bootstrap/iam.tf` | 🟢 Medium | Thêm `lambda:*` vào `AllowApplicationDeployment` statement |

---

## Quick Reference — Thứ tự lệnh deploy sandbox từ local

```bash
# 1. Build Window Feeder ZIP
cd xbrain-learners/capstone/tf-4/cdo-07/infra/lambda/window-feeder
mkdir -p build/package
pip install -r ../requirements.txt -t build/package/
cp app.py build/package/
cd build/package && zip -r ../window-feeder.zip . && cd ../..

# 2. Fix transformer stub (implement Timestream write)
# Edit: infra/modules/lambda/transformer/lambda/transformer_handler.py

# 3. Tạo Timestream database + table
aws timestream-write create-database --database-name "tf4-cdo07-sandbox" --kms-key-id "alias/tf4-cdo07-bootstrap"
aws timestream-write create-table --database-name "tf4-cdo07-sandbox" --table-name "service-metrics" --retention-properties "MemoryStoreRetentionPeriodInHours=48,MagneticStoreRetentionPeriodInDays=90"

# 4. Apply sandbox
cd infra/environments/sandbox
terraform init
terraform plan -out=sandbox.tfplan
terraform apply sandbox.tfplan

# 5. Smoke test
aws kinesis put-record --stream-name tf4-cdo07-sandbox-ingest-stream --partition-key payment-gateway --data '{"service_id":"payment-gateway","metric_name":"cpu","value":50,"timestamp":"2026-06-29T00:00:00Z"}'
aws lambda invoke --function-name tf4-cdo07-sandbox-window-feeder --payload '{}' /tmp/out.json && cat /tmp/out.json
```

---

*Checklist tạo bởi Kiro · CDO-07 · 2026-06-29*
*Cập nhật khi có thay đổi infra: append, không xóa dòng đã check.*
