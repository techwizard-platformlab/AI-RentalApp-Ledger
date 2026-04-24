# rentalAppLedger — Platform Repository

Cloud-native, AI-augmented rental property management platform. This repository contains the **platform layer**: infrastructure as code, Kubernetes manifests, GitOps configuration, security policies, observability, and AI tooling. The Django REST API lives in the companion [RentalApp-Build](https://github.com/techwizard-platformlab/RentalApp-Build) repo.

Multi-cloud: **Azure** (AKS, ACR, Key Vault) and **GCP** (GKE, Artifact Registry, Secret Manager).

---

## Repository Structure

```
AI-RentalApp-Ledger/
├── .github/
│   ├── workflows/              # GitHub Actions CI/CD pipelines
│   └── scripts/
│       ├── azure/              # Azure-specific logic (bootstrap.sh, ci-rag-api.sh)
│       ├── gcp/                # GCP-specific logic (bootstrap.sh, ci-rag-api.sh)
│       ├── deploy-compute.sh   # Trigger Terraform apply via gh CLI
│       └── destroy-compute.sh  # Trigger Terraform destroy via gh CLI
├── apps/
│   └── ai-engine/
│       ├── prompt/             # Prompt engineering guides (per build phase)
│       ├── rag/                # RAG API (FastAPI + ChromaDB + LLM)
│       └── tools/
│           ├── k8s-assistant/  # AI-powered pod diagnostics
│           └── anomaly-detector/ # Statistical anomaly detection (Z-score, IQR)
├── bootstrap/                  # One-time cloud bootstrap scripts (Azure + GCP)
├── tests/
│   ├── dev/
│   │   └── testing/            # BDD smoke tests, dev-only validation
│   ├── qa/
│   │   └── testing/            # Full BDD regression suite
│   └── shared/
│       └── testing/            # Shared validate_deployment.sh + ArgoCD PostSync hook
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
│   │   ├── charts/             # Helm charts for ArgoCD App + AppProject + platform add-ons
│   │   ├── environments/       # Per-env Helm values (dev/qa × azure/gcp)
│   │   └── values/             # ArgoCD install values + PostgreSQL fallback values
│   ├── kubernetes/
│   │   ├── base/               # Kustomize base manifests (api-gateway, rental/ledger/notification)
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
└── .infracost/                 # Infracost project config (all envs × both clouds)
```

---

## Workflows

| Workflow | Trigger | What it does |
|---|---|---|
| `terraform.yml` | Manual / PR | Plan / apply / destroy |
| `argocd-bootstrap.yml` | Manual | Install ArgoCD, apply AppProject + Application CRDs, deploy add-ons |
| `k8s-validate.yml` | Manual / path trigger | kubeconform + kustomize build validation |
| `ci-build.yml` | Manual / path trigger | OPA Rego lint + Trivy security scan |
| `cost-check.yml` | Manual / path trigger | Infracost estimate + OPA cost guardrail |
| `ci-rag-api.yml` | Push to main / manual | Build + push RAG API image (Azure ACR or GCP AR) |

### Inputs: `terraform.yml`

| Input | Options | Default |
|---|---|---|
| `target_env` | dev / qa / uat / prod | dev |
| `cloud` | azure / gcp / both | azure |
| `action` | plan / apply / destroy | plan |
| `scope` | compute-only / full | compute-only |
| `confirm` | type env name for non-dev apply/destroy | — |

`compute-only` destroys AKS/GKE + VNet/VPC but keeps ACR, Key Vault, and Storage Account — preserving data between sessions.

### Inputs: `argocd-bootstrap.yml`

| Input | Options | Default |
|---|---|---|
| `cloud` | azure / gcp | azure |
| `environment` | dev / qa / uat / prod | dev |
| `action` | install / upgrade / apply-apps / apply-addons / uninstall-apps / uninstall-addons / uninstall | install |
| `addons` | all / istio / prometheus | all |
| `db_mode` | azure-pg / azure-sql / helm-pg / gcp-pg / cloudsql | azure-pg |

---

## Cost Model

Weekly budget target: **~400 INR / ~$5 USD**.

- Compute (AKS/GKE) runs only when needed — created at session start, destroyed at end.
- ACR, SQL, Key Vault, and Storage Account persist between sessions (kept for data continuity).
- `.github/scripts/deploy-compute.sh` and `destroy-compute.sh` for quick manual control.
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

See [bootstrap/README.md](bootstrap/README.md) for the full multi-phase bootstrap guide.

### 2 — Add GitHub Secrets

```
GitHub → Settings → Secrets and variables → Actions

# Azure OIDC (no client secret — uses Managed Identity + federated credentials)
AZURE_CLIENT_ID          # Managed Identity client ID
AZURE_TENANT_ID          # Azure AD tenant ID
AZURE_SUBSCRIPTION_ID    # Subscription ID
PLATFORM_KV_NAME         # Platform Key Vault name

# Terraform state backend
TF_BACKEND_RG            # Storage Account resource group
TF_BACKEND_SA            # Storage Account name
TF_BACKEND_CONTAINER     # Blob container name (e.g. tfstate)

# Shared permanent layer (obtained after first azure shared apply)
TF_SHARED_RG             # Permanent resource group name
ACR_NAME                 # Azure Container Registry name
KEY_VAULT_NAME           # Key Vault name

# GCP OIDC
GCP_PROJECT_ID, GCP_REGION, GCP_WORKLOAD_IDENTITY_PROVIDER, GCP_SERVICE_ACCOUNT

# Notifications
DISCORD_WEBHOOK_URL, SMTP_PASSWORD, MAIL_TO

# ArgoCD
ARGOCD_GITHUB_PAT        # GitHub PAT for ArgoCD repo access
```

### 3 — Provision infrastructure

First run — provision the **shared layer** (ACR + Key Vault, one-time):

```
GitHub → Actions → terraform.yml
  cloud: azure | action: apply
  → Approve in "shared" Environment gate
  → Copy ACR_NAME and KEY_VAULT_NAME outputs to GitHub Secrets
```

Then provision the **env layer** (AKS, SQL, VNet, etc.):

```
GitHub → Actions → terraform.yml
  cloud: azure (or gcp / both)  target_env: dev  action: apply
  → Approve in "terraform-destructive-approval" gate
```

See [infrastructure/README.md](infrastructure/README.md) for full details.

### 4 — Bootstrap ArgoCD + deploy apps

```
GitHub → Actions → argocd-bootstrap.yml
  cloud: azure  environment: dev  action: install
  cloud: azure  environment: dev  action: apply-apps
```

### 5 — Install cluster add-ons

```
GitHub → Actions → argocd-bootstrap.yml
  action: apply-addons  addons: all
```

---

## Day-to-day Operations

### Start a session (create compute)

```bash
bash .github/scripts/deploy-compute.sh azure dev
# or: GitHub Actions → terraform.yml → action: apply
```

### End a session (destroy compute)

```bash
bash .github/scripts/destroy-compute.sh azure dev
# or: GitHub Actions → terraform.yml → action: destroy
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
bash tests/shared/testing/validate_deployment.sh --cloud azure --env dev --notify discord
```
### Run BDD tests locally

```bash
cd tests/dev/testing
BASE_URL=http://localhost:8000 behave features/ --tags @smoke
```

---

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for:
- Full component diagram (AKS/GKE, services, Istio mesh, cloud resources)
- Application component reference (API Gateway, Rental/Ledger/Notification services, RAG API, AI tools)
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

---

## Maintenance & Security Hardening (Recent Updates)

The platform recently underwent a security and stability hardening phase:

- **Terraform Workflow Hardening**:
  - Automated `TF_VAR_env_resource_group_name` injection to prevent interactive prompt failures in CI/CD.
  - Fixed artifact upload paths for Trivy security reports (reports now correctly appear in GitHub Action summaries).
  - Enforced strict `terraform fmt` compliance across all modules.
- **AKS Security (Zero-Trust)**:
  - Enabled **API Server Authorized IP Ranges** (defaulting to restricted access).
  - Enforced **Azure Network Policy** for granular pod-to-pod communication control.
  - Explicitly enabled **RBAC** for all identity operations.
- **Data Protection**:
  - **Key Vault**: Implemented Network ACLs with a default `Deny` action and `AzureServices` bypass.
  - **Storage Account**: Enforced Network Rules with default `Deny` and restricted access to trusted Azure services.

