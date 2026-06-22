# Deployment & CI/CD Design - Task Force 4 · CDO-07

<!-- Doc owner: CDO-07
     Status: Draft (W11 T4) → Final (W11 T6 Pack #1) → Working (W12 T4 Pack #2)
     Word target: 1200-2000 từ
     Last updated: 2026-06-22 -->

## 1. IaC strategy

### 1.1 Tool choice

- **IaC tool**: Terraform (HCL)
- **Justify**: team familiar, provider AWS well-maintained, module reuse tốt, state locking native
- **State backend**: S3 bucket `tf4-cdo07-tf-state` + DynamoDB table `tf4-cdo07-tf-lock`
- **Terraform version**: `>= 1.8.0` (pin trong `.terraform-version`)

### 1.2 Module structure

```
infra/
├── modules/
│   ├── networking/          # VPC, subnets, SG, VPC endpoints
│   ├── compute/             # ECS cluster, Fargate task def, Lambda (nếu có)
│   ├── storage/             # Timestream / S3 audit / DynamoDB
│   ├── observability/       # CloudWatch dashboards, alarms, Grafana
│   ├── secrets/             # Secrets Manager resources
│   └── tenant-provision/    # Per-service onboarding (gọi khi add tier-1 service)
├── environments/
│   ├── sandbox/             # main.tf + variables.tfvars
│   └── prod/                # (design-only, capstone dùng sandbox)
├── scripts/
│   ├── bootstrap.sh         # Tạo S3 state bucket + DynamoDB lock lần đầu
│   └── tenant-onboard.sh    # Trigger tenant-provision module
└── README.md
```

### 1.3 State management

- Remote state per environment (sandbox / prod)
- `terraform plan` chạy trên PR, output comment vào PR
- `terraform apply` chạy sau merge to `main` (manual approval gate)
- State lock via DynamoDB conditional write - prevent concurrent apply

---

## 2. CI/CD pipeline

### 2.1 Pipeline flow

```
PR opened
    │
    ├─► [Lint] terraform fmt -check + tflint
    │
    ├─► [Scan] Gitleaks (secret detection) + Trivy (container scan)
    │
    ├─► [Test] Unit test infra modules (terratest hoặc checkov)
    │
    ├─► [Plan] terraform plan → comment diff vào PR
    │
    └─► [Review] Manual approve required (lead CDO-07)

PR merged to main
    │
    ├─► [Apply] terraform apply (auto, sandbox only)
    │
    └─► [Smoke] Health check: ALB /health → 200, TSDB write test
```

### 2.2 Pipeline stages table

| Stage | Tool | What | Quality gate |
|---|---|---|---|
| Lint | `terraform fmt`, `tflint` | Format + lint HCL | Zero warnings |
| Secret scan | Gitleaks | Detect hardcoded creds | 0 secrets found → block merge |
| Container scan | Trivy | CVE scan AI engine image | No CRITICAL CVE |
| Unit test | Checkov / pytest (terratest) | Policy compliance test | All pass |
| Plan | `terraform plan` | Preview infra diff | Plan reviewed by lead |
| Apply | `terraform apply` | Deploy sandbox | Apply exit 0 |
| Smoke | curl + Python script | Endpoint health + TSDB write | All endpoints 200 |

### 2.3 Branch strategy

- `main` → production-ready (tương đương sandbox trong capstone)
- `feature/<task-id>-<short-desc>` → feature branches (vd `feature/JIRA-42-add-timestream`)
- PR required để merge vào `main` + approval từ 1 thành viên khác CDO-07

---

## 3. GitOps

### 3.1 Approach (capstone scope)

Capstone dùng **Terraform + GitHub Actions** làm lightweight GitOps thay vì ArgoCD/Flux
(K8s operator overhead không cần thiết nếu không dùng EKS angle).

Nếu CDO-07 chọn **EKS angle** → upgrade lên ArgoCD (xem §3.2).

### 3.2 ArgoCD setup (chỉ nếu dùng EKS)

<!-- Bỏ qua section này nếu không chọn EKS angle -->

| Wave | Components |
|---|---|
| 0 | Namespace, ConfigMaps, Secrets (via External Secrets Operator) |
| 1 | CRDs (KEDA, Cert-Manager nếu có) |
| 2 | Database, cache |
| 3 | AI engine deployment, ingest service |
| 4 | Ingress, HPA |

### 3.3 Drift detection

- `terraform plan` chạy **daily scheduled** (GitHub Actions cron `0 9 * * *`)
- Nếu plan có diff → Slack notification `#tf4-cdo07-infra-drift`
- Manual review + apply required - không auto-apply khi drift detected

---

## 4. Deployment strategy

### 4.1 Strategy: Canary (ECS rolling update)

```
ECS service update:
  minimum healthy percent: 50%
  maximum percent: 200%
  → ECS drain old tasks after new tasks healthy
```

**Canary flow** (manual trigger trong W12):
1. Deploy new task definition → 10% traffic (1/10 tasks)
2. Monitor 5 min: error rate < 1%, P99 < 800ms
3. → 50% traffic
4. Monitor 5 min: same gate
5. → 100% complete rollout

### 4.2 Abort criteria

- Error rate > 1% tại any step → auto-rollback
- P99 latency > 800ms → auto-rollback
- Smoke test fail post-deploy → rollback + alert Slack

### 4.3 Rollback

- **Primary**: `aws ecs update-service --task-definition <previous-revision>` (< 60s)
- **Secondary**: `git revert` + re-apply Terraform nếu infra change
- **Target RTO**: < 60s (task swap), < 5min (full infra rollback)

---

## 5. Environment separation

| Env | Purpose | Account | Auto-deploy | Notes |
|---|---|---|---|---|
| Sandbox | Capstone build + test | `<TF4-account>` | On merge to `main` | Dùng suốt W11-W12 |
| Prod | Design-only | N/A | N/A | Không build trong capstone |

---

## 6. Secrets in pipeline

- **No static AWS keys**: CI dùng GitHub OIDC → assume `tf4-cdo07-platform-deploy-role`
- **Secret scanning**: Gitleaks chạy trên mọi PR commit, block merge nếu detect
- **Env vars trong CI**: chỉ `AWS_REGION`, `TF_VAR_*` non-sensitive. Sensitive values luôn từ Secrets Manager tại runtime

---

## 7. Tenant (service) onboarding deployment

```bash
# Trigger khi thêm tier-1 service mới vào TF4 platform
./scripts/tenant-onboard.sh \
  --service-name "payment-gateway" \
  --metric-schema "cpu_percent,memory_bytes,connection_count" \
  --tier "tier-1"

# Script sẽ:
# 1. terraform apply -target=module.tenant-provision -var service_name=...
# 2. Verify TSDB namespace created
# 3. Verify Grafana datasource created
# 4. Run smoke test
# 5. Print: "Service payment-gateway onboarded. Baseline training ready."
```

**Target total time**: < 30 phút.

---

## 8. Observability stack

| Component | Tool | Notes |
|---|---|---|
| Metrics platform | `< TODO: CloudWatch / AMP >` | Source of truth cho time-series data |
| Application logs | CloudWatch Logs | Structured JSON, retention 14 ngày |
| Distributed traces | AWS X-Ray | Trace AI engine request end-to-end |
| Dashboard | `< TODO: Managed Grafana / CloudWatch Dashboard >` | TF4 yêu cầu Grafana annotation overlay |
| Alerts | CloudWatch Alarms + SNS + Slack webhook | P99 latency, error rate, cost budget |
| Drift alert | GitHub Actions cron + Slack | Daily infra drift check |

---

## 9. Open questions

- [ ] Q1: GitHub repo của TF4 task force đặt ở đâu, ai có quyền merge?
- [ ] Q2: Deployment Contract từ AI team xác nhận compute target - chờ T4 W11
- [ ] Q3: Nếu dùng EKS angle, cần ArgoCD - confirm với team trước T3

---

## Related documents

- [`02_infra_design.md`](02_infra_design.md) - Infra layout được deploy theo pipeline này
- [`03_security_design.md`](03_security_design.md) - OIDC + secret scan details
- [`08_adrs.md`](08_adrs.md) - ADR-006 (IaC tool), ADR-007 (deployment strategy)
