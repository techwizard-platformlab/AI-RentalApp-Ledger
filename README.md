# rentalAppLedger — Platform Repository

Cloud-native, AI-augmented rental property management platform.

This repository contains the **platform layer**: infrastructure as code,
Kubernetes manifests, GitOps configuration, security policies, observability,
and AI tooling. The Django REST API lives in the companion
[RentalApp-Build](https://github.com/YOUR_ORG/RentalApp-Build) repo.

**Multi-cloud**: Azure (AKS + ACR + Key Vault) and GCP (GKE + Artifact Registry + Secret Manager)  
**GitOps**: ArgoCD with Helm-based environment configuration  
**IaC**: Terraform with modular, per-environment state  

---

## Repository structure

```
.
├── .github/
│   ├── scripts/                  # Cloud-specific shell scripts (logic layer)
│   │   ├── azure/
│   │   │   ├── bootstrap.sh      # Azure ArgoCD bootstrap logic
│   │   │   └── ci-rag-api.sh     # Azure ACR login + tag resolution
│   │   ├── gcp/
│   │   │   ├── bootstrap.sh      # GCP ArgoCD bootstrap logic
│   │   │   └── ci-rag-api.sh     # GCP Artifact Registry auth + tag resolution
│   │   ├── deploy-compute.sh     # Re-deploy cluster (after session destroy)
│   │   └── destroy-compute.sh    # Destroy cluster to stop billing
│   └── workflows/                # GitHub Actions orchestration (thin wrappers)
│       ├── argocd-bootstrap.yml  # Install/manage ArgoCD on AKS/GKE
│       ├── ci-rag-api.yml        # Build + push RAG API container image
│       ├── terraform.yml         # Terraform plan / apply / destroy
│       ├── ci-build.yml          # Linting, OPA policy checks, Trivy scans
│       ├── cost-check.yml        # Infracost budget enforcement
│       ├── k8s-validate.yml      # Kubernetes manifest validation
│       └── qa-validate.yml       # BDD smoke tests post-deploy
│
├── .infracost/
│   └── config.yml                # Multi-env, multi-cloud cost analysis config
│
├── apps/
│   └── ai-engine/
│       ├── prompt/               # Prompt engineering guides per build phase
│       ├── rag/                  # RAG API (FastAPI + ChromaDB + OpenAI)
│       └── tools/
│           ├── k8s-assistant/    # AI-powered pod diagnostics
│           └── anomaly-detector/ # Statistical anomaly detection
│
├── bootstrap/                    # One-time cloud setup (Azure + GCP)
│   ├── .env.example              # Generic config template (no secrets)
│   ├── bootstrap.sh              # Create MI/WI, Key Vault, TF state bucket
│   ├── load-secrets.sh           # Source secrets into shell (never exec)
│   ├── set-github-secrets.py     # Push cloud secrets → GitHub repo secrets
│   └── store-secrets.sh          # Store third-party secrets into cloud store
│
├── environments/
│   ├── shared/testing/           # Generic smoke validation (all clouds/envs)
│   │   ├── validate_deployment.sh
│   │   └── argocd-postsync-hook.yaml
│   ├── dev/testing/              # Dev BDD tests (Behave)
│   └── qa/testing/               # QA BDD tests
│
├── infrastructure/
│   ├── azure/
│   │   ├── modules/              # 13 reusable Azure modules (AKS, ACR, KV, PG, …)
│   │   └── environments/         # dev / qa root modules
│   └── gcp/
│       ├── modules/              # 8 reusable GCP modules (GKE, AR, CloudSQL, …)
│       ├── shared/               # Cross-env GCP shared resources
│       └── environments/         # dev / qa root modules
│
└── platform/
    ├── gitops/argocd/
    │   ├── apps/                 # ArgoCD Application manifests (bootstrap applies)
    │   ├── charts/               # Helm charts for ArgoCD manifests
    │   │   ├── rental-app/       # App + AppProject chart
    │   │   └── platform-addons/  # Istio, Prometheus chart
    │   ├── environments/         # Per-env Helm value overrides (dev/, qa/)
    │   ├── values/               # Shared values (argocd-install, postgresql)
    │   └── notifications/        # ArgoCD notification config
    ├── kubernetes/               # Kustomize base + overlays per environment
    ├── observability/            # Grafana dashboards, alertmanager config
    └── security/
        └── policies/             # OPA / Conftest policies (cost, k8s)
```

---

## Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `terraform.yml` | PR + manual | Plan / apply / destroy infrastructure |
| `argocd-bootstrap.yml` | Manual | Install/manage ArgoCD on AKS or GKE |
| `ci-rag-api.yml` | Push to main / manual | Build and push RAG API image to registry |
| `ci-build.yml` | Manual | OPA policy lint + Trivy security scan |
| `cost-check.yml` | PR | Infracost budget check ($22/month limit) |
| `k8s-validate.yml` | PR | Kubeconform manifest validation |
| `qa-validate.yml` | Manual | BDD smoke tests against live cluster |

---

## Quick start

### 1. Bootstrap cloud prerequisites

```bash
cp bootstrap/.env.example bootstrap/.env
$EDITOR bootstrap/.env      # fill names and regions — no secrets here
az login                     # or: gcloud auth login
bash bootstrap/bootstrap.sh
python bootstrap/set-github-secrets.py
```

### 2. Deploy infrastructure

```
GitHub Actions → Infra → workflow_dispatch
  target_env: dev
  cloud: azure
  action: plan
# Review plan → re-run with action: apply
```

### 3. Install ArgoCD

```
GitHub Actions → ArgoCD Bootstrap → workflow_dispatch
  cloud: azure
  environment: dev
  action: install
  db_mode: azure-pg
```

### 4. Deploy platform add-ons (Istio + Prometheus)

```
GitHub Actions → ArgoCD Bootstrap → workflow_dispatch
  action: apply-addons
  addons: all
```

---

## Cloud support matrix

| Feature | Azure | GCP |
|---------|-------|-----|
| Kubernetes | AKS | GKE |
| Container registry | ACR | Artifact Registry |
| Database | PostgreSQL Flexible / SQL Database | Cloud SQL |
| Secrets | Key Vault + ESO | Secret Manager + ESO |
| Auth | Managed Identity + OIDC | Workload Identity + OIDC |
| TF state | Azure Blob Storage | GCS Bucket |
| Bootstrap scripts | `.github/scripts/azure/` | `.github/scripts/gcp/` |

---

## Key design decisions

- **No secrets in code** — all secrets live in cloud secrets stores; GitHub Secrets hold only OIDC federation config
- **Scripts separate from workflows** — workflows are thin orchestration; logic lives in `.github/scripts/azure/` or `.github/scripts/gcp/`
- **Helm-based GitOps** — ArgoCD Applications and AppProjects are generated from Helm charts with per-env value overrides
- **Deploy-destroy cost pattern** — cluster is destroyed after each session; ACR/SQL persist (cheap); OPA budget: $22/month cap
- **Manual destroy only** — no scheduled destroy; all destructive operations require human approval

---

## Further reading

- [bootstrap/README.md](bootstrap/README.md) — cloud prerequisites and onboarding
- [infrastructure/README.md](infrastructure/README.md) — Terraform module guide
- [platform/gitops/argocd/README.md](platform/gitops/argocd/README.md) — ArgoCD GitOps guide
- [environments/shared/testing/README.md](environments/shared/testing/README.md) — testing framework
- [ARCHITECTURE.md](ARCHITECTURE.md) — full system architecture reference
