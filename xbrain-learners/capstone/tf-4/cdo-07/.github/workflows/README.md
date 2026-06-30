# CI/CD Workflows - CDO-07 Foresight Lens

## 📋 Overview

Dự án sử dụng **separation of concerns** giữa application code và infrastructure code, với CI/CD pipelines riêng biệt để tối ưu build time và deployment flexibility.

```
┌─────────────────────────────────────────────────────────────┐
│                    Repository Structure                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  mock-services/          →  build-mock-services.yml         │
│  ├── payment-gw/            (Build & push Docker images)    │
│  ├── ledger-svc/                                            │
│  └── fraud-detection/                                       │
│                                                              │
│  infra/                  →  terraform-infra.yml             │
│  ├── modules/               (Plan & apply Terraform)        │
│  └── environments/                                          │
│                                                              │
│  k6-tests/               →  k6-load-tests.yml               │
│  └── scenario-*.js          (Load testing on-demand)        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 🚀 Workflows

### 1️⃣ **build-mock-services.yml**

**Trigger:**
- Push to `develop` or `main` branch
- Changes in `mock-services/**`

**What it does:**
1. **Detect changes** - Only build services that changed (smart caching)
2. **Build Docker images** - Multi-platform if needed
3. **Push to ECR** - Tagged with `latest` and `${{ github.sha }}`
4. **Deploy to ECS** - Force new deployment for changed services
5. **Wait for stability** - Ensure services are healthy

**Jobs:**
- `detect-changes` - Path filtering to identify changed services
- `build-payment-gw` - Build & push payment-gw image
- `build-ledger-svc` - Build & push ledger-svc image
- `build-fraud-detection` - Build & push fraud-detection image
- `deploy-to-ecs` - Rolling update to ECS services

**Key Features:**
- ✅ Smart change detection (only build what changed)
- ✅ Docker layer caching (GitHub Actions cache)
- ✅ Parallel builds (faster CI)
- ✅ Automatic ECS deployment
- ✅ Health check validation

**Example Run:**
```
Payment-gw changed → Build payment-gw → Push to ECR → Deploy to ECS
Ledger-svc no change → Skip
Fraud-detection no change → Skip
```

---

### 2️⃣ **terraform-infra.yml**

**Trigger:**
- Push to `develop` or `main` branch
- Changes in `infra/**`

**What it does:**
1. **Format check** - Ensure Terraform code is formatted
2. **Init & Validate** - Initialize and validate Terraform
3. **Plan** - Generate execution plan for all environments
4. **Apply** - Apply changes to appropriate environment(s)

**Jobs:**
- `terraform-plan` - Plan for sandbox/staging/prod (matrix)
- `terraform-apply-sandbox` - Apply to sandbox (develop branch)
- `terraform-apply-staging` - Apply to staging (develop branch)
- `terraform-apply-prod` - Apply to prod (main branch only)

**Environment Strategy:**
```
develop branch → Sandbox + Staging
main branch    → Production only
```

**Key Features:**
- ✅ Matrix strategy (plan all environments in parallel)
- ✅ Environment protection (manual approval for prod)
- ✅ State locking (prevent concurrent runs)
- ✅ Plan artifacts (review before apply)

**Example Run:**
```
PR → Plan all 3 environments → Show diff
Merge to develop → Apply to sandbox + staging
Merge to main → Apply to production (with approval)
```

---

### 3️⃣ **k6-load-tests.yml**

**Trigger:**
- Manual dispatch (on-demand testing)
- Weekly schedule (Sunday 2 AM UTC)

**What it does:**
1. **Get ALB DNS** - Retrieve internal ALB endpoint from AWS
2. **Setup k6** - Install k6 on GitHub runner
3. **Run scenarios** - Execute selected test scenario(s)
4. **Upload results** - Save JSON results as artifacts
5. **Generate summary** - Display results in GitHub UI

**Inputs:**
- `environment` - sandbox or staging
- `scenario` - Which test to run (or all)

**Scenarios:**
- Scenario 1: Gradual Drift (2h)
- Scenario 2: Sudden Spike (2h)
- Scenario 3: Slow Leak (2.5h)
- Scenario 4: Noisy Baseline (2h)
- All: Run all 4 sequentially (8.5h)

**Key Features:**
- ✅ On-demand execution via UI
- ✅ Environment selection
- ✅ Single or all scenarios
- ✅ Results as downloadable artifacts
- ✅ Weekly automated regression

**Example Run:**
```
Manual trigger → Select sandbox + scenario-1 → Run 2h test → Upload results
```

---

## 🔐 Prerequisites

### 1. AWS IAM Role (OIDC)

Create GitHub OIDC provider in AWS:

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

Create IAM role `github-actions-role`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
        }
      }
    }
  ]
}
```

Attach policies:
- `AmazonEC2ContainerRegistryPowerUser`
- `AmazonECS_FullAccess`
- `AmazonElasticLoadBalancingReadOnly`
- Custom policy for Terraform (S3, DynamoDB, etc.)

### 2. GitHub Secrets

Add to repository settings:

```
AWS_ACCOUNT_ID = 123456789012
```

### 3. GitHub Environments

Create environments in Settings → Environments:
- `sandbox` (no protection rules)
- `staging` (no protection rules)
- `production` (required reviewers)

### 4. Terraform Backend

Create backend config files:

**`infra/environments/sandbox/backend.hcl`**
```hcl
bucket         = "cdo-07-terraform-state"
key            = "sandbox/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "cdo-07-terraform-locks"
encrypt        = true
```

---

## 📊 Deployment Flow

### **Application Changes** (mock-services/)

```
1. Developer commits code
   ↓
2. Push to develop branch
   ↓
3. build-mock-services.yml triggered
   ↓
4. Detect changed services (payment-gw modified)
   ↓
5. Build Docker image for payment-gw only
   ↓
6. Push to ECR with tags: latest, ${{ github.sha }}
   ↓
7. Update ECS task definition (new image)
   ↓
8. Force new deployment (rolling update)
   ↓
9. Wait for services to stabilize
   ↓
10. ✅ Deployment complete (2-3 minutes)
```

**Timeline:** ~3-5 minutes per service

---

### **Infrastructure Changes** (infra/)

```
1. Developer modifies Terraform
   ↓
2. Create PR
   ↓
3. terraform-infra.yml runs plan
   ↓
4. Review plan in PR comments
   ↓
5. Merge to develop
   ↓
6. Apply to sandbox + staging
   ↓
7. Test in sandbox
   ↓
8. Merge to main
   ↓
9. Apply to production (with approval)
   ↓
10. ✅ Infrastructure updated (5-10 minutes)
```

**Timeline:** ~5-15 minutes depending on changes

---

### **Load Testing** (k6-tests/)

```
1. Navigate to Actions → K6 Load Tests
   ↓
2. Click "Run workflow"
   ↓
3. Select environment (sandbox)
   ↓
4. Select scenario (scenario-1-gradual-drift)
   ↓
5. Run workflow
   ↓
6. Wait 2 hours for test completion
   ↓
7. Download results artifacts
   ↓
8. Analyze in Grafana + calculate metrics
   ↓
9. ✅ Validation complete
```

**Timeline:** 2-8.5 hours depending on scenario

---

## 🎯 Best Practices

### **Smart Change Detection**

Only build/deploy what changed:

```yaml
- uses: dorny/paths-filter@v2
  with:
    filters: |
      payment-gw:
        - 'mock-services/payment-gw/**'
```

### **Docker Layer Caching**

Speed up builds with GitHub Actions cache:

```yaml
- uses: docker/build-push-action@v5
  with:
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

### **Terraform State Locking**

Prevent concurrent modifications:

```hcl
backend "s3" {
  dynamodb_table = "cdo-07-terraform-locks"
}
```

### **Environment Protection**

Production requires manual approval:

```yaml
environment:
  name: production
  url: https://grafana.cdo-07.example.com
```

---

## 🐛 Troubleshooting

### Issue: "OIDC role assumption failed"

**Cause:** GitHub OIDC provider not configured or role trust policy incorrect

**Fix:**
```bash
# Verify OIDC provider exists
aws iam list-open-id-connect-providers

# Check role trust policy
aws iam get-role --role-name github-actions-role
```

### Issue: "ECR login failed"

**Cause:** IAM role missing ECR permissions

**Fix:**
```bash
aws iam attach-role-policy \
  --role-name github-actions-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
```

### Issue: "ECS deployment stuck"

**Cause:** New tasks failing health checks

**Fix:**
```bash
# Check ECS task logs
aws logs tail /aws/ecs/sandbox-mock-services --follow

# Check ALB target health
aws elbv2 describe-target-health --target-group-arn <ARN>
```

### Issue: "K6 test connectivity failed"

**Cause:** ALB is internal, GitHub runner cannot reach it

**Fix:**
- Use self-hosted runner in VPC
- Or run k6 tests from EC2 in VPC
- Or use VPN connection

---

## 📈 Monitoring CI/CD

### GitHub Actions Insights

- View workflow runs: Actions tab
- Monitor success rate
- Track build times
- Review artifacts

### AWS CloudWatch

- ECS deployment events
- Task start/stop logs
- Application logs

### Grafana

- Service health metrics
- Deployment annotations
- Latency impact analysis

---

## 🎓 Advanced Patterns

### **Blue/Green Deployment**

Modify ECS deployment to use CodeDeploy:

```yaml
- name: Deploy with CodeDeploy
  run: |
    aws deploy create-deployment \
      --application-name cdo-07-app \
      --deployment-group-name cdo-07-dg \
      --deployment-config-name CodeDeployDefault.ECSAllAtOnce
```

### **Canary Testing**

Progressive rollout:

```yaml
stages:
  - 10% traffic → 30 min soak
  - 50% traffic → 30 min soak
  - 100% traffic
```

### **Rollback on Failure**

Automatic rollback if health checks fail:

```yaml
- name: Monitor deployment
  run: |
    aws ecs wait services-stable || \
    aws ecs update-service --rollback
```

---

## 📚 References

- [GitHub Actions Docs](https://docs.github.com/en/actions)
- [AWS OIDC Setup](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [Terraform CI/CD](https://developer.hashicorp.com/terraform/tutorials/automation/github-actions)
- [k6 CI/CD](https://k6.io/docs/integrations/ci/)
