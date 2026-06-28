# Báo cáo kiểm tra mức độ sẵn sàng Infra

Nhánh kiểm tra: `codex/check-infra-readiness`  
Nhánh gốc: `develop`  
Repo path: `/Users/anons/Documents/capstone-phase2/CDO-07-Capstone-phase2`

## Tóm tắt

Infra hiện **chưa sẵn sàng để chạy lại toàn bộ hệ thống end-to-end**.

Repo đã có một số Terraform module nền tảng, nhưng runtime environment vẫn còn lỗi validate và thiếu nhiều thành phần so với deployment design.

Kết quả kiểm tra lại mới nhất vẫn giữ nguyên kết luận: infra hiện mới ở mức **partial foundation**, chưa khớp đầy đủ với kiến trúc runtime trong tài liệu.

## Các bước đã kiểm tra

- Tạo nhánh `codex/check-infra-readiness` từ `develop`.
- Kiểm tra Terraform bằng version `1.10.5`, đúng version CI đang dùng.
- Chạy Terraform validation cho:
  - `infra/bootstrap`
  - `infra`
  - `infra/environments/sandbox`
  - `infra/environments/staging`
  - `infra/environments/prod`
- Chạy Terraform format check:
  - `terraform -chdir=xbrain-learners/capstone/tf-4/cdo-07/infra fmt -check -recursive`
- Chạy unit test cho Lambda window-feeder:
  - `python3 -m pytest -q xbrain-learners/capstone/tf-4/cdo-07/infra/lambda/window-feeder/test_app.py`
- Chạy lại kiểm tra bằng bản copy tạm ở `/tmp/codex-infra-rerun` để tránh làm bẩn lockfile hoặc `.terraform` trong repo thật.
- Đối chiếu Terraform resources hiện có với:
  - `docs/02_infra_design.md`
  - `docs/04_deployment_design.md`

## Phần đã đạt

- `infra/bootstrap` Terraform validate pass.
- `infra` root Terraform validate pass khi chạy trong bản copy tạm.
- Unit test Lambda window-feeder pass:
  - `7 passed`
- Repo thật không bị làm bẩn trong lần kiểm tra lại; chỉ còn file staged có sẵn từ trước:
  - `scripts/pre-push-ci.sh`

## Đối chiếu với kiến trúc

Kiến trúc trong `02_infra_design.md` và `04_deployment_design.md` mô tả runtime flow chính:

```text
Kinesis Data Streams
→ ECS Fargate Ingestor
→ Timestream for InfluxDB
→ ECS Predictor/Orchestrator
→ AI Engine
→ Grafana/alerts/audit
```

Trạng thái hiện tại:

| Thành phần kiến trúc | Trạng thái trong Terraform hiện tại | Ghi chú |
|---|---|---|
| VPC, subnet, security groups | Có một phần | Có module `networking`, ALB, VPC endpoints, SG cho Lambda/VPC endpoint |
| Application Load Balancer | Có | Có ALB module và listener rules cho AI/mock services |
| Kinesis Data Streams | Có | Có `aws_kinesis_stream` trong module `streaming` |
| Kinesis Firehose | Thiếu | Tài liệu có nhắc Stream Delivery nhưng không thấy resource Firehose |
| Timestream for InfluxDB | Thiếu | `modules/data` hiện chỉ tạo S3 audit bucket, chưa tạo DB/table |
| S3 baseline/audit | Có | Có `s3_baseline` và audit bucket trong `modules/data` |
| ECS AI Engine | Có một phần | Có ECS service module, nhưng image default vẫn là placeholder nginx |
| ECS mock services | Có một phần | Có payment/ledger/fraud services, nhưng image default vẫn là placeholder nginx |
| ECS Ingestor | Thiếu/chưa rõ | Deployment design có `ingestor`, nhưng không thấy module/source tương ứng |
| ECS Predictor/Orchestrator | Thiếu/chưa đúng design | Hiện có Lambda window-feeder; chưa thấy scheduled ECS task/orchestrator theo design |
| Lambda transformer | Có một phần | Có Lambda đọc Kinesis và IAM Timestream, nhưng Timestream chưa được provision |
| Window feeder | Có một phần | Code và test có, nhưng deployment zip chưa tồn tại |
| Fail-open fallback | Có | Có module Lambda fallback và alarm |
| Cost circuit breaker | Có | Có Budget, SNS, Lambda, SSM inference flag |
| Managed Grafana | Thiếu | Chỉ có biến/API annotation trong fallback, chưa có workspace Terraform |
| CodeDeploy blue/green | Thiếu | Script deploy gọi CodeDeploy, nhưng chưa có app/deployment group Terraform |
| ECR repositories | Có trong bootstrap | Bootstrap tạo ECR repo cho service images |
| Service source/Dockerfile | Thiếu | Không có thư mục `services/` |

## Các blocker chính

### 1. Terraform validate fail ở tất cả runtime environments

Các environment bị ảnh hưởng:

- `sandbox`
- `staging`
- `prod`

Lỗi:

```text
Error: Unsupported argument

An argument named "tags" is not expected here.
```

Nguyên nhân:

Các environment đang truyền `tags = local.common_tags` vào `module "sns_to_slack"`, nhưng module `infra/modules/sns_to_slack/variables.tf` chưa khai báo input variable `tags`.

Các file liên quan:

- `xbrain-learners/capstone/tf-4/cdo-07/infra/environments/sandbox/main.tf`
- `xbrain-learners/capstone/tf-4/cdo-07/infra/environments/staging/main.tf`
- `xbrain-learners/capstone/tf-4/cdo-07/infra/environments/prod/main.tf`
- `xbrain-learners/capstone/tf-4/cdo-07/infra/modules/sns_to_slack/variables.tf`

### 2. Terraform format check chưa pass

Lệnh `terraform fmt -check -recursive` báo các file chưa đúng format:

```text
environments/prod/main.tf
environments/sandbox/main.tf
environments/staging/main.tf
modules/ecs/ai-engine/autoscaling.tf
modules/ecs/ai-engine/iam.tf
modules/ecs/ai-engine/service.tf
modules/lambda/fail-open-fallback/main.tf
modules/networking/alb.tf
```

### 3. Runtime infra chưa đủ so với deployment design

Deployment design có nhắc tới các thành phần runtime như:

- Timestream for InfluxDB
- Managed Grafana
- CodeDeploy app và deployment group
- Firehose delivery stream
- ECS ingestor/orchestrator runtime components

Kết quả kiểm tra hiện tại:

- `modules/data` hiện chỉ provision S3 audit bucket, chưa provision Timestream/InfluxDB database.
- Chưa thấy Terraform resource cho Timestream/InfluxDB, Managed Grafana, CodeDeploy deployment group hoặc Firehose.
- Một số Lambda có reference tới Timestream name và IAM permission, nhưng database/table chưa được tạo bằng Terraform.
- Deployment script `deploy-codedeploy-bluegreen.sh` có gọi CodeDeploy, nhưng Terraform chưa tạo CodeDeploy app/deployment group tương ứng.

### 4. Thiếu source code service để deploy

CI/CD workflow đang kỳ vọng có service directories và Dockerfile cho:

- `ingest-service`
- `ingest-worker`
- `ai-serving`

Kết quả kiểm tra hiện tại:

- Thư mục `xbrain-learners/capstone/tf-4/cdo-07/services` không tồn tại.
- Deploy workflow có thể skip build image hoặc tạo image manifest rỗng, nên chưa thể deploy application container thật.

Chi tiết service còn thiếu:

| Service | Vai trò kỳ vọng | Trạng thái hiện tại |
|---|---|---|
| `ingest-service` | Service nhận/đẩy telemetry vào pipeline ingestion | Chưa có source directory, chưa có Dockerfile |
| `ingest-worker` | Worker xử lý dữ liệu ingestion/stream processing | Chưa có source directory, chưa có Dockerfile |
| `ai-serving` | AI inference service phục vụ endpoint dự đoán | Chưa có source directory, chưa có Dockerfile |

Ngoài ra, Terraform ECS modules hiện vẫn dùng image placeholder như `public.ecr.aws/nginx/nginx:alpine` nếu không truyền image URI thật. Vì vậy dù apply được infra, service chạy lên cũng chưa phải application thật.

### 5. Thiếu package zip cho Window Feeder Lambda

Terraform config đang trỏ tới:

```text
xbrain-learners/capstone/tf-4/cdo-07/infra/lambda/window-feeder/build/window-feeder.zip
```

Kết quả kiểm tra hiện tại:

- File zip này chưa tồn tại.
- `terraform plan` hoặc `terraform apply` có thể fail khi evaluate `filebase64sha256(var.package_path)` nếu chưa build package trước khi chạy Terraform.

### 6. Terraform lockfiles cần được review

Terraform init phát hiện provider dependency selection cần cập nhật ở một số root.

Ví dụ:

- Provider `archive` được dùng bởi các Lambda packaging modules.
- Các environment root có warning khi init với `-lockfile=readonly`.

Phần này nên được xử lý chủ động trong một commit riêng, không nên để thành thay đổi generated ngoài ý muốn.

## Kết luận

Infra hiện mới ở mức **partial**. Repo có một số module nền tảng hữu ích, nhưng chưa đủ để chạy lại hệ thống hoàn chỉnh.

Thứ tự xử lý đề xuất:

1. Fix mismatch interface của module `sns_to_slack`.
2. Chạy `terraform fmt -recursive`.
3. Chạy lại `terraform init -backend=false` và `terraform validate` cho `sandbox`, `staging`, `prod`.
4. Refresh và commit Terraform lockfiles một cách chủ động nếu provider dependency thay đổi.
5. Bổ sung hoặc wire các runtime infrastructure còn thiếu:
   - Timestream/InfluxDB
   - Grafana
   - CodeDeploy
   - Firehose nếu vẫn nằm trong target architecture
   - ECS ingestor/orchestrator nếu vẫn là kiến trúc đích
6. Thêm source directories cho services hoặc truyền ECR image thật cho ECS services.
7. Thêm build step để tạo `window-feeder.zip` trước khi chạy Terraform plan/apply.
8. Chạy lại Terraform plan cho `sandbox` hoặc `staging`.
