# Deployment & CI/CD Design - Task Force 4 · CDO-07

<!-- Doc owner: CDO-07
     Status: Updated 2026-07-01 - aligned with current Terraform, split AI repo CI/CD, and Kinesis/Timestream InfluxDB runtime
     Word target: 1200-2000 từ -->

Tài liệu này mô tả cách cấp phát và phát hành platform TF4 Foresight Lens trên AWS bằng Terraform và GitHub Actions. Nội dung đã được rà soát lại theo trạng thái hiện tại của dự án:

- CDO repo: `CDO-07/CDO-07-Capstone-phase2`
- AI repo: `CDO-07/TF4-AIO-03-foresight-lens-final`
- AWS region: `us-east-1`
- AWS account hiện dùng: `201023212626`

## 1. Runtime deployment model

Runtime hiện tại không còn theo mô hình ADOT/AMP trong bản tài liệu cũ. Code Terraform hiện tại đang hướng đến flow sau:

```text
k6 / synthetic traffic
  -> Application Load Balancer
  -> ECS Fargate Mock Services
  -> Kinesis Data Streams
  -> Lambda Transformer
  -> Amazon Timestream for InfluxDB
  -> EventBridge scheduled Lambda Window Feeder
  -> ECS Fargate AI Engine /v1/predict
  -> S3 baseline/audit + SNS/Slack + Amazon Managed Grafana
```

AI Engine được build từ repo AI riêng, push image lên ECR, sau đó repo AI gửi `repository_dispatch` sang repo CDO để deploy staging bằng immutable image URI dạng `repo@sha256:<digest>`.

## 2. Terraform strategy

### 2.1 Tooling

- **IaC tool**: Terraform HCL.
- **Terraform version trong CI**: `1.10.5`.
- **State backend**: S3 backend với state key riêng cho từng environment.
- **Authentication**: GitHub Actions assume AWS role qua OIDC, không dùng AWS static access key.
- **Bootstrap ownership**: bootstrap tạo state bucket, KMS key, GitHub OIDC provider, plan/deploy roles và ECR repositories.

Bootstrap hiện tạo các ECR repository:

```text
tf4-cdo07-ingest-service
tf4-cdo07-ingest-worker
tf4-cdo07-ai-serving
```

Repo AI push image vào `tf4-cdo07-ai-serving`. Repo CDO consume image này để deploy ECS service `foresight-lens-engine`.

### 2.2 Module structure hiện tại

```text
infra/
├── bootstrap/                    # S3 state, KMS, GitHub OIDC, IAM roles, ECR
├── modules/
│   ├── networking/               # VPC, ALB, private/public subnets, SG, VPC endpoints
│   ├── streaming/                # Kinesis Data Streams + CloudWatch alarms
│   ├── data/                     # S3 audit bucket + Timestream for InfluxDB
│   ├── s3_baseline/              # S3 baseline bucket
│   ├── ecs/
│   │   ├── ai-engine/            # ECS Fargate AI Engine, ALB target group, autoscaling
│   │   └── mock-services/        # ECS mock services ghi telemetry vào Kinesis
│   ├── lambda/
│   │   ├── transformer/          # Kinesis -> Timestream InfluxDB bridge
│   │   └── fail-open-fallback/   # static threshold fallback
│   ├── lambda-scheduled-function/# EventBridge scheduled Window Feeder
│   ├── cost-circuit-breaker/     # AWS Budgets + SSM inference flag
│   ├── observability/            # Amazon Managed Grafana integration
│   └── sns_to_slack/             # SNS topic + Slack forwarder Lambda
├── environments/
│   ├── sandbox/
│   ├── staging/
│   └── prod/
└── scripts/
    ├── deploy-ecs-rolling.sh
    ├── deploy-codedeploy-bluegreen.sh
    └── smoke-test.sh
```

### 2.3 Deployment waves

Thứ tự apply khuyến nghị:

1. Bootstrap: S3 state, KMS, OIDC roles, ECR.
2. Networking: VPC, subnets, ALB, security groups, VPC endpoints.
3. Storage/data: S3 baseline, S3 audit, Timestream for InfluxDB.
4. Streaming: Kinesis Data Streams.
5. Runtime compute: ECS mock services và ECS AI Engine.
6. Lambda layer: Transformer, Window Feeder, fail-open/cost circuit breaker.
7. Observability và notification: Grafana, CloudWatch alarms, SNS/Slack.

## 3. CI/CD pipeline

### 3.1 Pull request gates trong CDO repo

```text
PR opened/updated
  -> build-test.yml
  -> security-scan.yml
  -> terraform-plan.yml
  -> review + approval
  -> merge
```

`build-test.yml` hiện chỉ build/test các service thuộc CDO repo:

```text
ingest-service
ingest-worker
```

AI source không nằm trong CDO repo, nên CDO không build `ai-serving` từ local source nữa.

### 3.2 AI repo image pipeline

Repo AI có workflow `build-ai-image.yml`:

```text
push / manual dispatch
  -> test engine-skeleton
  -> docker build engine-skeleton
  -> push ECR tf4-cdo07-ai-serving
  -> resolve immutable image URI repo@sha256:<digest>
  -> upload image manifest
  -> optional repository_dispatch to CDO repo
```

Config cần có ở repo AI:

| Name | Type | Purpose |
|---|---|---|
| `AWS_REGION` | variable | Default `us-east-1` |
| `ECR_REPOSITORY` | variable | Default `tf4-cdo07-ai-serving` |
| `AWS_ECR_PUSH_ROLE_ARN` | variable | AWS role dùng để push image lên ECR |
| `CDO_REPOSITORY` | variable | Default `CDO-07/CDO-07-Capstone-phase2` |
| `CDO_REPO_DISPATCH_TOKEN` | secret | PAT dùng để gửi `repository_dispatch` sang CDO repo |

Bootstrap deploy role trust policy hiện allow thêm subject của repo AI:

```text
repo:CDO-07/TF4-AIO-03-foresight-lens-final:ref:refs/heads/chore/cleanup-secrets
```

### 3.3 CDO workflows

| Workflow | Trigger | Trách nhiệm |
|---|---|---|
| `build-test.yml` | PR, push `develop`/`main`, manual | Detect và test/build `ingest-service`, `ingest-worker` nếu source tồn tại |
| `security-scan.yml` | PR, push `develop`/`main`, manual | Gitleaks, Trivy filesystem scan, Checkov Terraform scan |
| `terraform-plan.yml` | PR vào `develop`/`main`, manual | Chọn root bootstrap/staging/prod, build Window Feeder ZIP, fmt/init/validate/plan |
| `deploy-staging.yml` | push `develop`, `repository_dispatch: ai_image_published`, manual | Build Window Feeder ZIP, build CDO service images nếu có, nhận external AI image, Terraform apply staging, deploy ECS, smoke test |
| `deploy-prod.yml` | manual | Yêu cầu full Git SHA, immutable AI image URI và confirm `DEPLOY_PROD` trước khi apply/deploy prod |
| `drift-detection.yml` | daily cron, manual | Chạy Terraform `plan -detailed-exitcode` cho staging/prod/bootstrap |
| `slack-notifications.yml` | push, PR events, manual | Gửi Slack notification nếu webhook được cấu hình |
| `build-mock-services.yml` | mock-service path changes | Workflow cũ/chuyên biệt để build mock-service image và force ECS deployment |
| `terraform-infra.yml` | infra path changes | Workflow cũ/chuyên biệt dùng path/role assumption cũ |
| `k6-load-tests.yml` | manual, scheduled | Chạy k6 load-test scenarios theo environment ALB |

`deploy-staging.yml` có thể nhận AI image bằng 3 cách:

1. `repository_dispatch.client_payload.ai_image_uri` từ repo AI.
2. Manual `workflow_dispatch` input `ai_image_uri`.
3. Repository/environment variable `STAGING_AI_IMAGE_URI`.

Workflow reject mutable tag và yêu cầu AI image dạng digest:

```text
201023212626.dkr.ecr.us-east-1.amazonaws.com/tf4-cdo07-ai-serving@sha256:<digest>
```

## 4. Deployment strategy

### 4.1 AI Engine

AI Engine là một ECS service:

```text
ECS cluster: <environment>-tf-4-aiops-cluster
ECS service: foresight-lens-engine
Terraform container name: foresight-lens-engine
Port: 8080
Health check: GET /health
Prediction API: POST /v1/predict
```

Terraform tạo service baseline và dùng placeholder image cho đến khi CI/CD deploy image thật. ECS service có:

- desired count `2`
- CPU `512`
- memory `1024`
- ALB target group port `8080`
- CodeDeploy deployment controller `CODE_DEPLOY`
- blue/green target group pair
- path rule `/v1/*`
- CloudWatch logs
- ECS deployment circuit breaker
- autoscaling rules
- S3 baseline và audit env vars

Workflow deploy hiện gọi `deploy-codedeploy-bluegreen.sh` cho AI. Terraform module `ecs/ai-engine` tạo CodeDeploy application/deployment group có tên:

```text
tf4-cdo07-<environment>-foresight-lens-engine
```

Workflow staging/prod dùng `CONTAINER_NAME=foresight-lens-engine` để khớp với task definition do Terraform tạo.

### 4.2 CDO ingest services

`ingest-service` và `ingest-worker` vẫn là service thuộc CDO repo. Workflow hiện chỉ build nếu `services/<name>/Dockerfile` tồn tại. Nếu source directory chưa có, workflow ghi notice và skip image build/deploy cho service đó.

### 4.3 Mock services

Mock services chạy trên ECS Fargate và publish telemetry vào Kinesis Data Streams. Các tenant/service đang được model:

```text
payment-gateway
ledger-service / ledger-svc
fraud-detection
```

Workflow k6 dùng các scenario để tạo traffic qua ALB và kiểm tra drift/capacity behavior.

Ở sandbox, mock service image có thể được override sang các repo `cdo-07-payment-gw`, `cdo-07-ledger-svc`, `cdo-07-fraud-detection`. Ở staging/prod, nếu chưa truyền image URI thật vào module, default của module vẫn là `public.ecr.aws/nginx/nginx:alpine`; khi đó service chỉ là placeholder và chưa phát sinh telemetry thật.

### 4.4 Lambda Transformer

Lambda Transformer consume Kinesis records, validate telemetry schema, drop PII fields, và ghi metric sạch vào Timestream for InfluxDB qua InfluxDB v2 HTTP API.

Runtime inputs chính:

- Kinesis stream ARN/name
- InfluxDB URL
- InfluxDB secret ARN
- InfluxDB bucket `service-metrics`
- InfluxDB org `cdo-07`
- private subnets và Lambda security group

### 4.5 Window Feeder

EventBridge invoke Window Feeder mỗi 5 phút. Flow hiện tại:

1. Query metric window từ Timestream for InfluxDB.
2. Fill missing metric points bằng forward-fill settings.
3. Gọi AI Engine `POST /v1/predict`.
4. Ghi prediction/audit output vào S3.
5. Publish drift/capacity alert tới SNS, sau đó forward Slack.
6. Tôn trọng SSM inference flag do cost circuit breaker quản lý.

`terraform-plan.yml` và deploy workflows build `infra/lambda/window-feeder/build/window-feeder.zip` trước Terraform plan/apply để `filebase64sha256(package_path)` resolve được.

## 5. Branch and environment strategy

| Environment | Trigger | Purpose |
|---|---|---|
| `sandbox` | Terraform/manual workflow | Low-risk infra validation |
| `staging` | push vào `develop`, AI repo dispatch, hoặc manual | AI-CDO integration và load-test validation |
| `prod` | manual dispatch only | Demo/production baseline với explicit confirmation |

Lưu ý quan trọng của GitHub: `repository_dispatch` được evaluate trên default branch của repo nhận event. Vì CDO default branch là `main`, file `deploy-staging.yml` phải có mặt trên `main` thì dispatch từ repo AI mới trigger được staging.

## 6. Secrets, variables, and IAM

CDO repo variables:

| Variable | Purpose |
|---|---|
| `AWS_ACCOUNT_ID` | AWS account ID |
| `AWS_PLAN_ROLE_ARN` | Role dùng bởi `terraform-plan.yml` và drift detection |
| `AWS_DEPLOY_ROLE_ARN` | Role dùng bởi staging/prod deploy workflows |
| `STAGING_AI_IMAGE_URI` | Optional fallback AI image digest cho manual staging deploy |
| `STAGING_BASE_URL` | Base URL cho staging smoke test |
| `PROD_BASE_URL` | Base URL cho prod smoke test |

CDO repo secrets:

| Secret | Purpose |
|---|---|
| `SLACK_WEBHOOK_URL` | Push/PR Slack notification workflow |

AI repo secret:

| Secret | Purpose |
|---|---|
| `CDO_REPO_DISPATCH_TOKEN` | Gửi `repository_dispatch` event sang CDO repo |

Application/runtime secrets nên nằm trong AWS SSM Parameter Store hoặc Secrets Manager. Ví dụ:

- `/tf4-cdo07/<environment>/slack-webhook-url`
- Timestream InfluxDB operator token do AWS quản lý và Lambda đọc từ Secrets Manager.

## 7. Observability and smoke tests

| Component | Evidence |
|---|---|
| Kinesis | Incoming records, iterator age alarms |
| Transformer | Lambda logs, error alarms, successful InfluxDB writes |
| Timestream for InfluxDB | Bucket exists, write/query success, Grafana datasource |
| AI Engine | ALB `/health`, ECS service stable, CloudWatch logs |
| Window Feeder | Scheduled invocation logs, prediction calls, S3 audit objects |
| Alerting | SNS publish and Slack delivery |
| Drift detection | GitHub Actions summary from Terraform detailed-exitcode plan |

`smoke-test.sh` hiện chỉ check `GET /health` nếu `BASE_URL` được cấu hình. Smoke test đầy đủ hơn nên kiểm tra thêm:

1. Mock service emit telemetry vào Kinesis.
2. Transformer ghi metric vào InfluxDB.
3. Window Feeder tạo request `/v1/predict`.
4. AI Engine trả prediction hợp lệ.
5. Audit object xuất hiện trong S3.
6. SNS/Slack nhận alert khi trigger drift scenario.

## 8. Current gaps and risks

- `Firehose` có trong architecture/cost docs, nhưng hiện chưa có Terraform module/resource tạo `aws_kinesis_firehose_delivery_stream`.
- CodeDeploy blue/green đã được model trong Terraform, nhưng cần apply thành công trên AWS trước khi workflow AI deploy có thể dùng được.
- Networking module hiện cấu hình ALB `internal = false` để phục vụ k6/GitHub Actions load test từ ngoài VPC. Nếu security design yêu cầu internal-only/zero-trust, cần đổi lại thiết kế hoặc tài liệu security.
- `terraform-infra.yml` và `build-mock-services.yml` vẫn dùng root/path/role assumption cũ, nên cần reconcile hoặc deprecate để tránh hai câu chuyện CI/CD song song.
- `ingest-service` và `ingest-worker` có trong CI/CD, nhưng source directories có thể vẫn chưa tồn tại; workflow sẽ skip nếu thiếu Dockerfile.
- Mock service images ở staging/prod có thể vẫn là nginx placeholder nếu không truyền image URI thật vào module.
- AWS deploy role phải đủ quyền cho first-time staging apply. Lỗi staging gần đây cho thấy `tf4-cdo07-github-deploy-role` còn thiếu quyền IAM/EC2/Lambda/Budgets/Grafana/Kinesis/CloudWatch.
- `STAGING_BASE_URL` và `PROD_BASE_URL` phải được cấu hình, nếu không `smoke-test.sh` sẽ exit dạng skip notice.

## Related documents

- [`02_infra_design.md`](02_infra_design.md) - Runtime architecture and component ownership.
- [`03_security_design.md`](03_security_design.md) - IAM, network, encryption and audit controls.
- [`05_cost_analysis.md`](05_cost_analysis.md) - Cost model.
- [`08_adrs.md`](08_adrs.md) - Architecture decision records.
- [`deploy-checklist.md`](deploy-checklist.md) - Operational deploy checklist.
- [`08_task_r_infra_audit_report.md`](08_task_r_infra_audit_report.md) - Infra gap audit for Task R.
