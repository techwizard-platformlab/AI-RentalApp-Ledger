# rentalAppLedger — Platform Repository

Cloud-native, AI-augmented rental property management platform. This repository contains the **platform layer**: infrastructure as code, Kubernetes manifests, GitOps configuration, security policies, observability, and AI tooling. The Django REST API lives in the companion [RentalApp-Build](https://github.com/techwizard-platformlab/RentalApp-Build) repo.

---

## Repository Structure

```
AI-RentalApp-Ledger/
├── .github/workflows/          # GitHub Actions CI/CD pipelines
├── apps/
│   └── ai-engine/
│       ├── prompt/             # Prompt engineering guides (per build phase)
│       ├── rag/                # RAG API (FastAPI + ChromaDB + LLM)
│       └── tools/
│           ├── k8s-assistant/  # AI-powered pod diagnostics
│           └── anomaly-detector/ # Statistical anomaly detection (Z-score, IQR)
├── bootstrap/                  # One-time cloud bootstrap scripts (Azure + GCP)
├── ci-cd/
│   └── scripts/                # deploy-compute.sh / destroy-compute.sh
├── environments/
│   └── dev/
│       └── testing/            # BDD tests (Behave), post-deploy validation
├── infrastructure/
│   ├── azure/
│   │   ├── shared/              # Shared layer — ACR + Key Vault (permanent, run once)
│   │   ├── environments/dev|qa/ # Terraform root configs per environment
│   │   └── modules/            # aks, postgresql, sql_database, vnet, keyvault, budget, …
│   └── gcp/
│       ├── environments/dev|qa/
│       └── modules/            # gke, artifact_registry, cloud_sql, vpc, …
├── platform/
│   ├── gitops/argocd/
│   │   ├── apps/               # ArgoCD Application + AppProject + ApplicationSet CRDs
│   │   ├── argocd/             # ArgoCD Helm install values
│   │   ├── helm/               # PostgreSQL fallback Helm values
│   │   └── notifications/      # Discord notification templates + triggers
│   ├── kubernetes/
│   │   ├── base/               # Kustomize base manifests (api-gateway, rental/ledger/notification services)
│   │   └── overlays/dev|qa/    # Environment overlays (replicas, image tags, labels)
│   ├── networking/
│   │   └── istio/              # mTLS, gateway, virtual services, auth policies
│   ├── observability/
│   │   ├── alerting/           # Discord notifier, email notifier, K8s event watcher
│   │   └── monitoring/         # Prometheus Helm values, alert rules, Grafana dashboards
│   └── security/
│       ├── gatekeeper/         # OPA Gatekeeper constraint templates + constraints
│       ├── kyverno/            # Admission control policies + exceptions
│       └── policies/           # OPA/Rego policies (cost, Terraform, PR)
└── .infracost/                 # Infracost project config
```

---

## Workflows

| Workflow | Trigger | What it does |
|---|---|---|
| `terraform.yml` | Manual / cron | Plan / apply / destroy + scheduled dev lifecycle |
| `argocd-bootstrap.yml` | Manual | Install ArgoCD, apply AppProject + Application CRDs |
| `k8s-validate.yml` | Manual / path trigger | kubeconform + kustomize build validation |
| `ci-build.yml` | Manual / path trigger | OPA Rego lint + Trivy security scan |
| `cost-check.yml` | Manual / path trigger | Infracost estimate + OPA cost guardrail |

### Inputs: `terraform.yml`

| Input | Options | Default |
|---|---|---|
| `target_env` | dev / qa / uat / prod | dev |
| `cloud` | azure / gcp / both | azure |
| `action` | plan / apply / destroy | plan |
| `scope` | compute-only / full | compute-only |
| `confirm` | type env name for non-dev apply/destroy | — |

`compute-only` destroys AKS/GKE + VNet/VPC but keeps ACR, Key Vault, and Storage Account — preserving data between sessions.

**Scheduled runs** (cron — no manual input needed):
- Saturday 07:30 IST → `apply` dev compute (start session)
- Sunday 23:30 IST → `destroy` dev compute (stop billing)

### Inputs: `argocd-bootstrap.yml`

| Input | Options | Default |
|---|---|---|
| `environment` | dev / qa | dev |
| `action` | install / upgrade / apply-apps / uninstall | install |
| `db_mode` | azure-sql / helm-pg / azure-pg | azure-sql |

---

## Cost Model

Weekly budget target: **~400 INR / ~$5 USD**.

- Compute (AKS/GKE) runs only when needed — created at session start, destroyed at end.
- ACR, SQL, Key Vault, and Storage Account persist between sessions (kept for data continuity).
- `ci-cd/scripts/deploy-compute.sh` and `destroy-compute.sh` for quick manual control.
- `terraform-schedule.yml` automates the destroy/recreate cycle (Saturday morning / Sunday night cron).
- `cost-check.yml` blocks Terraform apply if Infracost estimate exceeds the weekly budget via OPA.

---

## Quick Start

### 1 — One-time bootstrap

```bash
# Azure
az login
az account set --subscription "<your-subscription-id>"
CLOUD=azure bash bootstrap/bootstrap.sh

# GCP
gcloud auth login && gcloud config set project <your-project-id>
CLOUD=gcp bash bootstrap/bootstrap.sh

# Both clouds
CLOUD=both bash bootstrap/bootstrap.sh
```

The script creates the Service Principal / Workload Identity and prints all required GitHub Secrets.

### 2 — Add GitHub Secrets

```
GitHub → Settings → Secrets and variables → Actions

# Azure OIDC (no client secret — uses Managed Identity + federated credentials)
AZURE_CLIENT_ID          # Managed Identity client ID
AZURE_TENANT_ID          # Azure AD tenant ID
AZURE_SUBSCRIPTION_ID    # Subscription ID

# Terraform state backend (in my-Rental-App)
TF_BACKEND_RG            # Storage Account resource group  (my-Rental-App)
TF_BACKEND_SA            # Storage Account name
TF_BACKEND_CONTAINER     # Blob container name (e.g. tfstate)

# Shared permanent layer (obtained after first azure_shared_apply run)
TF_SHARED_RG             # Permanent resource group name   (my-Rental-App)
ACR_NAME                 # Azure Container Registry name   (output of shared Terraform)
KEY_VAULT_NAME           # Key Vault name                  (output of shared Terraform)

# GCP OIDC
GCP_PROJECT_ID, GCP_WORKLOAD_IDENTITY_PROVIDER, GCP_SERVICE_ACCOUNT

# Notifications
DISCORD_WEBHOOK_URL, SMTP_PASSWORD, MAIL_TO
```

**RentalApp-Build repo** (`techwizard-platformlab/RentalApp-Build` → Settings → Secrets):

```
AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID
ACR_NAME, ACR_LOGIN_SERVER
DOCKERHUB_USERNAME, DOCKERHUB_TOKEN
GROQ_API_KEY, ANTHROPIC_API_KEY   # optional — AI features
```

### 3 — Provision infrastructure

First run — provision the **shared layer** (ACR + Key Vault, runs once):

```
GitHub → Actions → terraform.yml
  cloud: azure
  action: apply    → approve in "shared" Environment gate
           ↳ captures ACR_NAME and KEY_VAULT_NAME — save these as GitHub Secrets
```

Then provision the **env layer** (AKS, SQL, VNet, etc.):

```
GitHub → Actions → terraform.yml
  cloud: azure (or gcp / both)
  target_env: dev
  action: plan     → review output
  action: apply    → approve in "terraform-destructive-approval" gate (if deletions detected)
```

> **GitHub Environments to create** (repo → Settings → Environments):
> - `shared` — add yourself as required reviewer (protects ACR + Key Vault)
> - `terraform-destructive-approval` — add yourself as required reviewer (protects apply/destroy with deletions)
> - `dev`, `qa` — optional, for environment-scoped OIDC federation

### 4 — Bootstrap ArgoCD + deploy apps

```
GitHub → Actions → argocd-bootstrap.yml
  action: install          # installs ArgoCD via Helm
  action: apply-apps       # creates AppProject + Application CRDs
```

### 5 — Install cluster add-ons (one-time, manual)

See [STEPS.md](STEPS.md) Phase 3 for step-by-step commands covering:
Istio, Kyverno, OPA Gatekeeper, Prometheus + Grafana.

---

## Day-to-day Operations

### Start a session (create compute)

```bash
bash ci-cd/scripts/deploy-compute.sh azure dev
# or via GitHub Actions: terraform.yml → action: apply
```

### End a session (destroy compute)

```bash
bash ci-cd/scripts/destroy-compute.sh azure dev
# or via GitHub Actions: infra-destroy.yml → scope: compute-only
```

### Force-sync ArgoCD app

```bash
argocd app sync rentalapp-dev --force
```

### Check pod status

```bash
kubectl get pods -n rental-dev
kubectl get pods -n rental-qa
```

### Run validation

```bash
bash environments/dev/testing/validate_deployment.sh --cloud azure --env dev --notify discord
```

### Run BDD tests locally

```bash
cd environments/dev/testing
BASE_URL=http://localhost:8000 behave features/ --tags @smoke
```

---

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for:
- Full component diagram (AKS, services, Istio mesh, Azure resources)
- Application component reference (API Gateway, Rental/Ledger/Notification services, RAG API, AI tools)
- Data models
- Infrastructure module details
- Security layers (Istio mTLS → Kyverno → OPA → Pod security)
- Observability (Prometheus alerts, Grafana dashboards, Discord notifications)
- Full CI/CD pipeline reference

---

## Key Access Points (after deploy)

| Service | Command |
|---|---|
| ArgoCD UI | `kubectl port-forward svc/argocd-server -n argocd 8080:443` → https://localhost:8080 |
| Grafana | `kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80` → http://localhost:3000 |
| API Gateway | `kubectl get svc api-gateway -n rental-dev` → EXTERNAL-IP:8000 |
| RAG API | `kubectl port-forward svc/rag-api -n rental-dev 8080:8080` → http://localhost:8080 |
| Prometheus | `kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090` |
