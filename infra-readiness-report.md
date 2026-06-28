# Báo cáo kiểm tra mức độ sẵn sàng Infra

Nhánh kiểm tra: `codex/check-infra-readiness`  
Nhánh gốc: `develop`  
Repo path: `/Users/anons/Documents/capstone-phase2/CDO-07-Capstone-phase2`

## Tóm tắt

Infra hiện **chưa sẵn sàng để chạy lại toàn bộ hệ thống end-to-end**.

Repo đã có một số Terraform module nền tảng, nhưng runtime environment vẫn còn lỗi validate và thiếu nhiều thành phần so với deployment design.

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

## Phần đã đạt

- `infra/bootstrap` Terraform validate pass.
- `infra` root Terraform validate pass sau khi chạy writable init, nhưng lockfile cần được cập nhật provider dependency để init readonly có thể lặp lại ổn định.
- Unit test Lambda window-feeder pass:
  - `7 passed`

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
3. Refresh và commit Terraform lockfiles một cách chủ động.
4. Bổ sung hoặc wire các runtime infrastructure còn thiếu:
   - Timestream/InfluxDB
   - Grafana
   - CodeDeploy
   - Firehose nếu vẫn nằm trong target architecture
5. Thêm source directories cho services hoặc truyền ECR image thật cho ECS services.
6. Thêm build step để tạo `window-feeder.zip` trước khi chạy Terraform plan/apply.
7. Chạy lại Terraform validate và plan cho `sandbox` hoặc `staging`.
