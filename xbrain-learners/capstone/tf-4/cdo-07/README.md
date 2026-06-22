# CDO-07 · Task Force 4 - Foresight Lens

> Capstone Phase 2 · W11-W12 (22/06 - 02/07/2026)
> Platform infra cho AI engine predict drift + capacity exhaustion trên fintech 120-service stack.

---

## Thành viên nhóm

| Tên | Role | Jira | GitHub |
|---|---|---|---|
| `< TODO >` | CDO Lead | `< TODO >` | `< TODO >` |
| `< TODO >` | Infra / IaC | `< TODO >` | `< TODO >` |
| `< TODO >` | Security / Observability | `< TODO >` | `< TODO >` |

---

## Differentiation Angle

> **`< TODO: Điền sau khi lock T3 W11 >`**
>
> Ví dụ: "Managed Observability-first: Amazon Managed Prometheus + Managed Grafana native
> annotation, ops-light, tích hợp sẵn Grafana existing của Client."

---

## Cấu trúc repo

```
cdo-07/
├── docs/                          ← Documentation evidence pack (W11 focus)
│   ├── 01_requirements_analysis.md    ✅ Draft W11 T2
│   ├── 02_infra_design.md             ✅ Draft W11 T3-T4
│   ├── 03_security_design.md          ✅ Draft W11 T4
│   ├── 04_deployment_design.md        ✅ Draft W11 T4
│   ├── 05_cost_analysis.md            ✅ Skeleton W11 T6
│   ├── 07_test_eval_report.md         ⏳ W12 T4
│   ├── 08_adrs.md                     ✅ ≥3 ADR W11 T6
│   └── assets/                        ← Diagrams, screenshots
├── infra/                         ← Terraform IaC (W12 build)
├── standup-notes.md               ← Append-only daily standup
├── curveball-responses.md         ← 3 curveball responses
└── README.md                      ← This file
```

---

## Checklist tiến độ

### W11 Evidence Pack #1 (deadline: EOD T6 26/06)

**Docs**:
- [x] Repo skeleton setup
- [ ] `01_requirements_analysis.md` - final (T3)
- [ ] `02_infra_design.md` - final, angle locked (T4-T5)
- [ ] `03_security_design.md` - draft (T4-T5)
- [ ] `04_deployment_design.md` - draft (T4-T5)
- [ ] `05_cost_analysis.md` - skeleton với forecast (T5-T6)
- [ ] `08_adrs.md` - ≥3 ADR (T5-T6)

**Milestones**:
- [ ] Differentiation angle locked + committed (T3)
- [ ] Client interview debrief sent to mentor (EOD T2)
- [ ] AI contracts draft reviewed + push-back noted (EOD T4)
- [ ] Contracts signed T5 onsite
- [ ] Base infra (VPC + compute + observability skeleton) chạy được EOD T6

### W12 Evidence Pack #2 (deadline: EOD T4 01/07 - code freeze 18h)

- [ ] AI engine integration E2E chạy được (T3)
- [ ] Load test 100 RPS run (T3-T4)
- [ ] `05_cost_analysis.md` - measured actual (T4)
- [ ] `07_test_eval_report.md` - full results + curveball responses (T4)
- [ ] `08_adrs.md` - ≥5 ADR final (T4)
- [ ] `SLIDES.pdf` ready (T4)
- [ ] `demo-video.mp4` recorded (T4)
- [ ] `curveball-responses.md` - 3 entries filled (sau mỗi curveball)
- [ ] `git tag final` (8h T5 02/07)

---

## Links quan trọng

| Resource | Link |
|---|---|
| Jira project TF4 | `< TODO >` |
| AI team repo | `< TODO: link repo TF4 AI team >` |
| AI API endpoint (skeleton) | `< TODO: điền sau T5 W11 >` |
| AWS Account TF4 | `< TODO >` |
| Grafana dashboard | `< TODO: điền sau khi deploy W12 >` |

---

## Contracts (FREEZE sau T5 25/06)

> 3 contracts ký với AI team. KHÔNG thay đổi sau khi ký trừ khi qua curveball chính thức.

| Contract | File | Status |
|---|---|---|
| Telemetry Contract | `../../ai/contracts/telemetry-contract.md` | ⏳ Draft T4, ký T5 |
| AI API Contract | `../../ai/contracts/ai-api-contract.md` | ⏳ Draft T4, ký T5 |
| Deployment Contract | `../../ai/contracts/deployment-contract.md` | ⏳ Draft T4, ký T5 |

**AI API endpoint** (sau khi ký):
```
POST https://<skeleton-endpoint>/v1/predict
```
CDO-07 gọi endpoint này từ T6 W11 để test integration.

---

## Standup

14h hàng ngày. Log vào [`standup-notes.md`](standup-notes.md).

**Red flags tự escalate ngay** (đừng đợi thêm 1 ngày):
- 2 ngày liên tiếp cùng blocker chưa resolve
- AI và CDO disagree contract interpretation
- Build progress dưới 50% expected mid-week

Ping mentor: **anh Khánh / anh Nam Hồng / anh Toàn / anh Nghĩa** (pick 1, đợi reply nửa ngày).
