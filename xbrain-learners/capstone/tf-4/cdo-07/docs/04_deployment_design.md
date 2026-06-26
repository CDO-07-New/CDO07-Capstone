# Deployment & CI/CD Design - Task Force 4 · CDO-07

<!-- Doc owner: CDO-07
     Status: Updated for Kinesis + Timestream for InfluxDB architecture
     Word target: 1200-2000 từ
     Last updated: 2026-06-26 -->

Tài liệu này mô tả cách cấp phát và phát hành platform TF4 Foresight Lens trên AWS bằng Terraform và GitHub Actions.

Runtime architecture là source of truth:

```text
Telemetry Producers
  → Kinesis Data Streams
  → ECS Fargate Ingestor
  → Amazon Timestream for InfluxDB
  → EventBridge Scheduler
  → ECS Fargate Predictor/Orchestrator
  → ECS Fargate AI Engine
  → S3 Audit + Slack/SNS notification
```

CI/CD chỉ triển khai kiến trúc này. Pipeline không được thay đổi data flow runtime, không dùng SQS/Kafka thay cho Kinesis, và không đổi time-series store sang dịch vụ khác nếu chưa có ADR mới.

## 1. IaC strategy

### 1.1 Tool choice

- **IaC tool**: Terraform HCL.
- **AWS region**: `us-east-1`.
- **Terraform version**: `>= 1.10, < 2.0` để dùng S3 native state locking.
- **State backend**: S3 bucket `tf4-cdo07-tf-state`, bật versioning, block public access, SSE-KMS và `use_lockfile = true`.
- **Authentication**: GitHub Actions assume AWS role qua OIDC, không dùng static `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`.

Bootstrap Terraform tạo một lần các tài nguyên dùng chung:

- S3 remote state bucket.
- KMS key cho state/audit encryption.
- GitHub OIDC provider.
- `github-plan-role` cho `terraform plan`.
- `github-deploy-role` cho deployment.
- ECR repositories cho container images.

### 1.2 Module structure

Target structure của runtime infra:

```text
infra/
├── bootstrap/                    # State bucket, KMS key, GitHub OIDC roles, base ECR
├── modules/
│   ├── networking/               # VPC, public/private subnets, SG, VPC endpoints
│   ├── streaming/                # Kinesis Data Streams, DLQ/failure destination
│   ├── data/                     # Timestream for InfluxDB, S3 audit
│   ├── ecs/
│   │   ├── ingestor/             # Fargate service đọc Kinesis, ghi InfluxDB
│   │   ├── orchestrator/         # Scheduled Fargate task, gọi AI Engine
│   │   └── ai-engine/            # Fargate HTTP service behind ALB
│   ├── deployment/               # ECR, CodeDeploy app/deployment group
│   └── observability/            # CloudWatch, EventBridge, Managed Grafana, SNS
├── environments/
│   ├── sandbox/
│   ├── staging/
│   └── prod/
└── scripts/
    ├── deploy-ecs-rolling.sh
    ├── deploy-codedeploy-bluegreen.sh
    └── smoke-test.sh
```

### 1.3 State management và deployment waves

Mỗi environment dùng state key riêng:

```text
tf4-cdo07/sandbox/terraform.tfstate
tf4-cdo07/staging/terraform.tfstate
tf4-cdo07/prod/terraform.tfstate
```

Terraform triển khai theo thứ tự phụ thuộc:

1. Networking và security boundary.
2. Kinesis Data Streams.
3. Timestream for InfluxDB và S3 audit.
4. ECS Fargate Ingestor.
5. Predictor/Orchestrator task definition và EventBridge Scheduler target.
6. AI Engine ECS service, ALB, target groups và CodeDeploy.
7. CloudWatch alarms, Managed Grafana và notification path.

## 2. CI/CD pipeline

### 2.1 Pull request CI

Mọi PR vào `develop` hoặc `main` phải chạy các quality gates:

```text
PR opened/updated
  → build-test.yml
  → security-scan.yml
  → terraform-plan.yml
  → review approval
  → merge
```

`build-test.yml` detect service source và chạy test theo ngôn ngữ:

- Node.js: `npm ci` hoặc `npm install`, sau đó `npm test --if-present`.
- Python: install `requirements.txt` hoặc `pyproject.toml`, chạy `pytest` nếu có `tests/`.
- Go: `go test ./...`.
- Docker: build image nếu service có `Dockerfile`.

Target service keys theo kiến trúc mới:

```text
ingestor
orchestrator
ai-engine
```

Nếu repo tạm thời chưa có source code service, job được skip bằng notice để không chặn phần tài liệu/bootstrap. Khi runtime service đã có, thiếu source hoặc Dockerfile của service bắt buộc nên được đổi thành lỗi CI.

### 2.2 Security scan

`security-scan.yml` chạy trên PR và push vào protected branches:

| Check | Mục tiêu | Gate |
|---|---|---|
| Gitleaks | Secret trong working tree/history checkout | Không có secret |
| Trivy filesystem | Vulnerability HIGH/CRITICAL trong repo/dependency/image context | Không có HIGH/CRITICAL unfixed |
| Checkov Terraform | Misconfiguration trong `infra/**` | Không có lỗi policy ngoài skip list đã giải trình |

Skip list Checkov chỉ dùng cho exception có lý do rõ ràng trong capstone, ví dụ S3 cross-region replication out of scope. Không dùng skip list để che lỗi IAM rộng hoặc public exposure.

### 2.3 Terraform plan

`terraform-plan.yml` chạy:

- PR vào `develop`: plan môi trường `staging`.
- PR vào `main`: plan môi trường `prod`.
- `workflow_dispatch`: chọn `sandbox`, `staging`, `prod` hoặc `bootstrap`.

Các bước:

1. Chọn Terraform root.
2. `terraform fmt -check -recursive`.
3. Assume `AWS_PLAN_ROLE_ARN` qua OIDC.
4. `terraform init`.
5. `terraform validate`.
6. `terraform plan`.
7. Ghi plan summary vào GitHub Actions summary.

Trong giai đoạn bootstrap, workflow có thể skip nếu environment root chưa tồn tại. Khi runtime infra đã vào scope triển khai, thiếu `infra/environments/staging` hoặc `infra/environments/prod` phải được xem là lỗi.

### 2.4 CD workflows

Repo dùng hai workflow CD tách riêng:

| Workflow | Trigger | Mục tiêu |
|---|---|---|
| `deploy-staging.yml` | Push/merge vào `develop`, hoặc manual dispatch | Build/push images, `terraform apply` staging, deploy ECS, smoke test |
| `deploy-prod.yml` | Manual dispatch | Deploy đúng Git SHA đã pass staging, yêu cầu confirm string và GitHub Environment approval |

Không dùng workflow chung tên `deploy.yml`. Tách staging/prod giúp gate production rõ ràng hơn và giảm rủi ro deploy nhầm.

Staging deploy:

```text
merge into develop
  → assume deploy role
  → login ECR
  → build/push immutable images tagged by full Git SHA
  → write image digest manifest
  → terraform apply staging
  → rolling deploy Ingestor
  → update Orchestrator task revision / Scheduler target
  → blue/green deploy AI Engine
  → smoke test
```

Production deploy:

```text
manual workflow_dispatch
  → validate full 40-char Git SHA
  → require confirm = DEPLOY_PROD
  → verify successful staging deployment for that SHA
  → wait for GitHub Environment prod approval
  → resolve immutable ECR image digests
  → terraform apply prod
  → deploy ECS using digest, not mutable tag
  → smoke test
```

## 3. Branching, protection và environments

Branch strategy:

- `feat/<scope>`: nhánh làm việc chính cho feature/docs/infra.
- PR `feat/*` → `develop`: bắt buộc CI pass và ít nhất một approval.
- `develop`: source of truth của staging; merge thành công sẽ trigger staging deploy.
- PR `develop` → `main`: production-ready promotion.
- `main`: default branch và baseline production/demo.

Branch protection cho `develop` và `main`:

- Require pull request before merging.
- Require 1 approving review.
- Dismiss stale reviews khi có commit mới.
- Require branch up to date before merge.
- Required checks:
  - `Build and test ingestor`
  - `Build and test orchestrator`
  - `Build and test ai-engine`
  - `Gitleaks secret scan`
  - `Trivy filesystem scan`
  - `Checkov Terraform scan`
  - `Terraform plan`

GitHub Environments:

- `staging`: dùng cho deploy tự động sau merge vào `develop`.
- `prod`: yêu cầu manual approval trước khi job production chạy.

## 4. Deployment strategy

### 4.1 Ingestor: ECS rolling deployment

Ingestor là long-running ECS service đọc Kinesis và ghi vào Timestream for InfluxDB. Service này không nhận user traffic qua ALB nên dùng ECS rolling update:

- `minimumHealthyPercent = 100`.
- `maximumPercent = 200`.
- ECS deployment circuit breaker enabled.
- Rollback nếu task không đạt steady state.
- CloudWatch alarms theo dõi Kinesis iterator age, ingest error rate và InfluxDB write error.

### 4.2 Orchestrator: scheduled Fargate task

Orchestrator không phải service thường trực. EventBridge Scheduler chạy ECS `RunTask` mỗi 5 phút.

Mỗi cycle:

1. Đọc metric window từ Timestream for InfluxDB.
2. Gọi AI Engine `/v1/predict`.
3. Ghi prediction result vào InfluxDB.
4. Ghi audit event vào S3.
5. Nếu AI Engine timeout hoặc trả `503` nhiều lần liên tiếp, bật static-threshold fallback và gửi alert.

Release workflow đăng ký task definition revision mới, chạy smoke `RunTask`, sau đó cập nhật Scheduler target. Rollback trỏ Scheduler target về revision trước.

### 4.3 AI Engine: CodeDeploy Blue/Green

AI Engine là HTTP service sau ALB nên dùng CodeDeploy Blue/Green:

- ECS deployment controller: `CODE_DEPLOY`.
- Hai target groups: Blue và Green.
- Deployment config: `CodeDeployDefault.ECSCanary10Percent5Minutes`.
- Pre-traffic smoke test: `/health` và prediction fixture.
- CloudWatch alarms: ALB 5xx, error rate, p99 latency, task health.

Rollback nếu:

- Error rate vượt 1%.
- P99 latency vượt 500 ms.
- Pre/post-traffic smoke test fail.
- ECS task health không ổn định.

## 5. Drift detection

`drift-detection.yml` chạy hằng ngày bằng cron và có thể chạy manual:

```text
terraform plan -detailed-exitcode
0 → không có drift
1 → plan lỗi
2 → có drift hoặc infra chưa apply
```

Kết quả được ghi vào GitHub Actions summary. Khi Slack/SNS notification được nối vào workflow này, exit code `1` và `2` phải gửi alert với environment, workflow URL và plan excerpt. Drift không được auto-apply; sửa drift phải đi qua PR hoặc change request rõ ràng.

## 6. Slack notification

`slack-notifications.yml` gửi thông báo qua repository secret `SLACK_WEBHOOK_URL`.

Trigger:

- Push lên bất kỳ branch.
- PR opened/reopened/ready for review.
- PR merged.
- Manual dispatch.

Thông báo cần có:

- Repository.
- Actor.
- Branch source/target.
- PR URL hoặc compare URL.
- Workflow URL.

Workflow dùng `pull_request_target` cho PR event nhưng không checkout hoặc chạy code từ PR, chỉ đọc metadata và gửi payload qua `jq --arg`. Đây là yêu cầu bảo mật để tránh command injection từ PR title/head branch.

## 7. Secrets and variables

Repository variables:

| Variable | Mục đích |
|---|---|
| `AWS_ACCOUNT_ID` | AWS account chạy capstone |
| `AWS_PLAN_ROLE_ARN` | Role cho `terraform plan` |
| `AWS_DEPLOY_ROLE_ARN` | Role cho deploy/apply |
| `STAGING_BASE_URL` | Base URL cho smoke test staging |
| `PROD_BASE_URL` | Base URL cho smoke test production/demo |

Repository secrets:

| Secret | Mục đích |
|---|---|
| `SLACK_WEBHOOK_URL` | Incoming webhook nhận CI/CD notification |

Không lưu AWS static access key trong GitHub Secrets. Application secrets nằm trong AWS Secrets Manager hoặc SSM Parameter Store; pipeline chỉ truyền ARN hoặc parameter name.

## 8. Observability and smoke test

Smoke test sau deploy cần chứng minh đường đi chính:

1. Gửi telemetry fixture vào Kinesis.
2. Ingestor consume được record.
3. Metric được ghi vào Timestream for InfluxDB.
4. Orchestrator đọc được metric window.
5. Orchestrator gọi được AI Engine `/v1/predict`.
6. Prediction được ghi lại vào InfluxDB.
7. Audit object xuất hiện trong S3.
8. Slack/SNS nhận alert nếu fallback hoặc deployment rollback xảy ra.

Observability stack:

| Thành phần | Công cụ | Evidence |
|---|---|---|
| Streaming | Kinesis Data Streams | Throughput, throttling, iterator age |
| Time-series | Timestream for InfluxDB | Metrics và prediction retention |
| Compute | ECS Fargate | Task health, desired/running count, deployment events |
| API | ALB + AI Engine | `/health`, 5xx, latency, target health |
| Scheduling | EventBridge Scheduler | RunTask success/failure |
| Audit | S3 SSE-KMS | Prediction audit events |
| Notification | Slack/SNS | Deploy, merge, drift, rollback alert |

## 9. Current implementation notes

Các workflow đã tồn tại trong repo:

- `.github/workflows/build-test.yml`
- `.github/workflows/security-scan.yml`
- `.github/workflows/terraform-plan.yml`
- `.github/workflows/deploy-staging.yml`
- `.github/workflows/deploy-prod.yml`
- `.github/workflows/drift-detection.yml`
- `.github/workflows/slack-notifications.yml`

Các điểm cần giữ đồng bộ khi runtime infra/service source được thêm:

- Service names trong workflow phải là `ingestor`, `orchestrator`, `ai-engine`.
- ECR repository names nên theo convention `tf4-cdo07-<service>`.
- Terraform environment roots `infra/environments/staging` và `infra/environments/prod` phải tồn tại trước khi CD chạy thật.
- `STAGING_BASE_URL` và `PROD_BASE_URL` phải được cấu hình để smoke test không bị skip.
- Production deploy chỉ dùng immutable digest đã pass staging, không deploy `latest`.

## 10. Open questions

- [ ] AI Deployment Contract đã khóa ECR ownership, container port, `/health`, CPU/memory và task role chưa?
- [ ] Telemetry Contract đã khóa Kinesis schema, partition key và failure destination chưa?
- [ ] Timestream for InfluxDB retention, instance class và backup policy đã được duyệt theo budget chưa?
- [ ] Runtime Terraform roots `staging` và `prod` đã đủ module networking/streaming/data/ecs/deployment/observability chưa?
- [ ] Drift detection có cần gửi Slack ngay trong W11 hay để sau khi runtime infra apply xong?

## Related documents

- [`02_infra_design.md`](02_infra_design.md) - Runtime architecture và component ownership.
- [`03_security_design.md`](03_security_design.md) - IAM, network, encryption và audit controls.
- [`08_adrs.md`](08_adrs.md) - Quyết định Terraform, ECS và deployment strategy.
- [AWS ECS CodeDeploy Blue/Green](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-bluegreen.html)
- [EventBridge Scheduler ECS target](https://docs.aws.amazon.com/scheduler/latest/APIReference/API_Target.html)
- [Timestream for InfluxDB](https://docs.aws.amazon.com/timestream/latest/developerguide/timestream-for-influxdb.html)
- [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)
- [GitHub Actions OIDC với AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)
