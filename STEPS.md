# rentalAppLedger — Full Deployment Steps & Reference

> **Project**: rentalAppLedger — Python FastAPI microservices on AKS (Azure) + GKE (GCP)
> **Constraints**: KodeKloud playground — B2s nodes, max 2-3 nodes, 7 vCPU quota, $30/month limit
> **Cycle**: Destroy every Sunday night → Recreate every Saturday morning

---

## ✅ What's Been Built (Prompts 00 → 11)

| Prompt | Layer | Key Files |
|--------|-------|-----------|
| 00 | Bootstrap (OIDC, secrets) | `bootstrap/azure/bootstrap.sh`, `bootstrap/gcp/bootstrap.sh` |
| 01 | Terraform — Azure | `terraform/azure/` (AKS, ACR, KeyVault, VNet) |
| 02 | Terraform — GCP | `terraform/gcp/` (GKE, Artifact Registry, VPC) |
| 03 | GitHub Actions CI | `.github/workflows/ci-build.yml`, `Dockerfile` |
| 04 | K8s manifests + ArgoCD | `k8s/`, `gitops/apps/` |
| 05 | Istio mTLS + Kyverno | `istio/`, `kyverno/` |
| 06 | OPA + Gatekeeper + Infracost | `policy/`, `gatekeeper/`, `.infracost/` |
| 07 | Prometheus + Grafana | `monitoring/` |
| 08 | AI K8s Assistant + Anomaly Detector | `ai-tools/` |
| 09 | RAG Pipeline | `rag/` |
| 10 | BDD Tests + Post-Deploy Validation | `qa/` |
| 11 | Discord + Email + ArgoCD Notifications | `notify/`, `gitops/notifications/` |

---

## PHASE 1 — One-Time Bootstrap (Run Locally First)

### Step 1 — Edit the bootstrap script

```bash
# Open bootstrap/bootstrap.sh and set your GitHub username/org:
#   GITHUB_ORG="your-github-username"   ← change this line
```

### Step 2 — Run the unified bootstrap script

```bash
# Interactive menu — you choose the cloud at runtime:
bash bootstrap/bootstrap.sh

# ┌──────────────────────────────────────────┐
# │   rentalAppLedger — Bootstrap Wizard     │
# └──────────────────────────────────────────┘
#   Which cloud do you want to bootstrap?
#
#   1) Azure only  (AKS + ACR + KeyVault)
#   2) GCP only    (GKE + Artifact Registry)
#   3) Both        (Azure + GCP)
#
#   Enter choice [1/2/3]:

# Non-interactive (CI / scripted):
CLOUD=azure bash bootstrap/bootstrap.sh
CLOUD=gcp   bash bootstrap/bootstrap.sh
CLOUD=both  bash bootstrap/bootstrap.sh
```

**Azure prerequisites** (needed only if you select 1 or 3):
```bash
az login
az account set --subscription "<your-subscription-id>"
```

**GCP prerequisites** (needed only if you select 2 or 3):
```bash
gcloud auth login
gcloud config set project <your-project-id>
```

The script creates and prints all GitHub Secrets at the end.

### Step 3 — Add GitHub Secrets

```
Go to: GitHub → Your Repo → Settings → Secrets and variables → Actions → New secret

Required secrets (follow bootstrap/github-secrets.md for full list):

  Azure:
    AZURE_CLIENT_ID          → from Step 1 output
    AZURE_TENANT_ID          → from Step 1 output
    AZURE_SUBSCRIPTION_ID    → from Step 1 output

  GCP:
    GCP_PROJECT_ID                    → your GCP project ID
    GCP_WORKLOAD_IDENTITY_PROVIDER    → from Step 2 output
    GCP_SERVICE_ACCOUNT               → from Step 2 output

  Notifications:
    DISCORD_WEBHOOK_URL      → Discord server → Edit Channel → Integrations → Webhooks
    SMTP_PASSWORD            → Gmail App Password (not login password)
    MAIL_TO                  → recipient email address

  Optional (for RAG/AI):
    GROQ_API_KEY             → https://console.groq.com (free tier)
    ANTHROPIC_API_KEY        → https://console.anthropic.com (Claude Haiku cheapest)
```

---

## PHASE 2 — Provision Cloud Infrastructure (Terraform via GitHub Actions)

### Step 4 — Push Code to GitHub

```bash
git init                              # if not already a git repo
git remote add origin https://github.com/<org>/rentalAppLedger.git
git add .
git commit -m "feat: initial infra setup prompts 00-11"
git push origin main

# → Automatically triggers .github/workflows/terraform.yml
```

### Step 5 — Verify Terraform Plan (GitHub Actions)

```
GitHub → Actions → terraform.yml → latest run
  ✔ Lint & validate: terraform fmt -check, terraform validate
  ✔ OPA/Conftest: must show 0 DENY violations
  ✔ Infracost: estimated cost must be < $30/month
  ✔ Plan output: shows resources to be created
```

### Step 6 — Approve Terraform Apply

```
GitHub → Actions → terraform.yml → "Review deployment" → Approve

Wait 10-15 minutes for:
  ✔ Azure: AKS cluster (rental-dev-aks) + ACR + KeyVault
  ✔ GCP:   GKE cluster (rental-dev-gke) + Artifact Registry
```

---

## PHASE 3 — Install Cluster Add-ons (Manual, One-Time)

### Step 7 — Get Cluster Credentials

```bash
# Azure AKS
az aks get-credentials \
  --resource-group rental-dev-rg \
  --name rental-dev-aks \
  --overwrite-existing

# GCP GKE
gcloud container clusters get-credentials rental-dev-gke \
  --region us-central1 \
  --project <your-project-id>

# Verify both clusters are accessible
kubectl config get-contexts
kubectl get nodes    # should show 2-3 B2s nodes
```

### Step 8 — Install ArgoCD (AKS Hub Cluster)

```bash
# Set context to AKS
kubectl config use-context rental-dev-aks

# Create namespace and install
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd \
  --namespace argocd \
  --version 6.x.x \
  -f gitops/argocd/install-values.yaml

# Wait for ArgoCD to be ready
kubectl rollout status deploy/argocd-server -n argocd

# Get initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Port-forward to UI (optional)
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open: https://localhost:8080  (admin / <password from above>)
```

### Step 9 — Install ArgoCD Notifications

```bash
# Apply notifications ConfigMap (5 Discord templates)
kubectl apply -f gitops/notifications/argocd-notifications-cm.yaml

# Create secret with real Discord webhook URL
kubectl create secret generic argocd-notifications-secret \
  --namespace argocd \
  --from-literal=discord-webhook-url="https://discord.com/api/webhooks/<id>/<token>"

# Verify
kubectl get secret argocd-notifications-secret -n argocd
```

### Step 10 — Install Istio

```bash
# Install istioctl
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.20.0 sh -
export PATH=$PWD/istio-1.20.0/bin:$PATH

# Install Istio minimal profile (fits B2s node constraints)
istioctl install --set profile=minimal -y

# Enable sidecar injection for app namespaces
kubectl label namespace rental-dev istio-injection=enabled --overwrite
kubectl label namespace rental-qa  istio-injection=enabled --overwrite

# Apply Istio config (mTLS, gateway, virtual services, auth policies)
kubectl apply -f istio/peer-auth.yaml
kubectl apply -f istio/gateway.yaml
kubectl apply -f istio/destination-rules/
kubectl apply -f istio/virtual-services/
kubectl apply -f istio/authorization-policies/

# Verify mTLS is STRICT
istioctl x describe pod <any-app-pod> -n rental-dev
```

### Step 11 — Install Kyverno

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --set replicaCount=1    # fit B2s constraints

# Apply all 7 policies + exception
kubectl apply -f kyverno/policies/
kubectl apply -f kyverno/exceptions/

# Verify policies are loaded
kubectl get clusterpolicies
```

### Step 12 — Install Gatekeeper (OPA)

```bash
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update
helm install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace

# Apply ConstraintTemplates (CRD definitions)
kubectl apply -f gatekeeper/constraint-templates/

# Wait for CRDs to be established
kubectl wait --for=condition=established crd/requiresignedimages.constraints.gatekeeper.sh --timeout=60s

# Apply Constraints (enforce rules)
kubectl apply -f gatekeeper/constraints/

# Verify
kubectl get constrainttemplates
kubectl get constraints
```

### Step 13 — Install Prometheus + Grafana

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f monitoring/helm/prometheus-values.yaml

# Apply ServiceMonitors (one per microservice)
kubectl apply -f monitoring/servicemonitors/

# Apply PrometheusRules (alerts)
kubectl apply -f monitoring/alerts/

# Load Grafana dashboards
bash monitoring/dashboards/apply-dashboards.sh

# Access Grafana (default: admin/prom-operator)
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
# Open: http://localhost:3000
```

---

## PHASE 4 — Deploy the Application via ArgoCD

### Step 14 — Apply ArgoCD Application Resources

```bash
# Create AppProject (namespace + resource restrictions)
kubectl apply -f gitops/apps/appproject.yaml

# Deploy dev environment (auto-sync enabled)
kubectl apply -f gitops/apps/app-dev.yaml

# Deploy qa environment (manual sync)
kubectl apply -f gitops/apps/app-qa.yaml

# → ArgoCD pulls k8s/overlays/dev from GitHub and deploys:
#     api-gateway (port 8000, LoadBalancer)
#     rental-service (port 8001, ClusterIP)
#     ledger-service (port 8002, ClusterIP)
#     notification-service (port 8003, ClusterIP)
```

### Step 15 — Verify ArgoCD Sync

```bash
# Install ArgoCD CLI (optional but useful)
brew install argocd    # macOS
# or: https://argo-cd.readthedocs.io/en/stable/cli_installation/

# List apps
argocd app list

# Expected output:
#   rentalapp-dev   Synced    Healthy   rental-dev
#   rentalapp-qa    OutOfSync Healthy   rental-qa  (manual sync)

# Check pod status
kubectl get pods -n rental-dev
kubectl get pods -n rental-qa
```

### Step 16 — Setup Multi-Cluster (GKE Spoke)

```bash
# Switch to GKE context
kubectl config use-context rental-dev-gke

# Apply RBAC so ArgoCD hub (AKS) can manage GKE spoke
kubectl apply -f gitops/apps/gke-cluster-rbac.yaml

# Switch back to AKS hub
kubectl config use-context rental-dev-aks

# Register GKE cluster in ArgoCD
argocd cluster add rental-dev-gke

# Apply ApplicationSet (deploys to both AKS + GKE)
kubectl apply -f gitops/apps/applicationset-multicluster.yaml
```

---

## PHASE 5 — Enable AI Tools + RAG

### Step 17 — Deploy RAG API

```bash
# Apply PVC + Deployment + Service
kubectl apply -f rag/k8s/deployment.yaml

# Apply hourly indexer CronJob
kubectl apply -f rag/k8s/cronjob-indexer.yaml

# Seed test data (run once)
pip install sqlalchemy psycopg2-binary
python rag/seed_test_data.py

# Test RAG endpoint
kubectl port-forward svc/rag-api -n rental-dev 8080:8080
curl http://localhost:8080/health
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"question": "Show overdue payments"}'
```

### Step 18 — Deploy K8s Assistant

```bash
# Apply RBAC for the assistant
kubectl apply -f ai-tools/k8s-assistant/rbac.yaml

# Run locally (reads your current kubeconfig)
pip install kubernetes rich httpx
python ai-tools/k8s-assistant/k8s-assistant.py --watch

# Or analyse a specific pod
python ai-tools/k8s-assistant/k8s-assistant.py --pod <pod-name> --analyse

# Auto-fix (dry run first!)
python ai-tools/k8s-assistant/k8s-assistant.py --auto-fix --dry-run
```

### Step 19 — Deploy Anomaly Detector

```bash
# Apply CronJob (runs every 5 minutes)
kubectl apply -f ai-tools/anomaly-detector/k8s/cronjob.yaml
kubectl apply -f ai-tools/anomaly-detector/k8s/rbac.yaml

# Verify CronJob is scheduled
kubectl get cronjobs -n rental-dev

# Check logs after first run (~5 min)
kubectl logs -l app=anomaly-detector -n rental-dev --tail=50
```

---

## PHASE 6 — Run QA Validation

### Step 20 — Trigger BDD Tests (GitHub Actions)

```
GitHub → Actions → qa-validate.yml → Run workflow
  Select: environment = dev, cloud = azure

Or run locally:
  pip install behave requests
  cd qa
  BASE_URL=http://localhost:8000 behave features/ --tags @smoke
  behave features/ --tags @smoke --format html --outfile reports/smoke-report.html
```

### Step 21 — Post-Deploy Validation Script

```bash
# Run full validation (pods, health, TLS, memory, Istio)
bash qa/validate_deployment.sh

# Expected output sections:
#   [1/5] Pod Status Check       → all pods Running
#   [2/5] Service Health Check   → all /health return 200
#   [3/5] TLS Certificate Check  → cert valid, expiry > 30 days
#   [4/5] Resource Usage Check   → memory < 80%
#   [5/5] Istio Sidecar Check    → all pods have istio-proxy

# ArgoCD PostSync hook (auto-runs after each sync)
kubectl apply -f qa/argocd-postsync-hook.yaml
```

### Step 22 — Verify Notifications Are Working

```bash
# Discord: trigger a test notification manually
kubectl exec -n argocd deploy/argocd-notifications-controller -- \
  argocd-notifications trigger notify on-sync-succeeded \
    --app rentalapp-dev

# GitHub Actions notify.yml: call from another workflow
# uses: ./.github/workflows/notify.yml
# with:
#   event_type: deployment
#   status: success
#   message: "api-gateway v1.2.3 deployed to dev"
#   environment: dev

# K8s event watcher: deploy and tail logs
kubectl apply -f notify/k8s/event-watcher-deployment.yaml
kubectl logs -l app=k8s-event-watcher -n rental-dev -f
```

---

## PHASE 7 — Weekly KodeKloud Cycle (Automated)

```
Every Saturday morning (IST 23:30 → UTC 18:00):
  → terraform-schedule.yml triggers automatically
  → Runs terraform apply for Azure + GCP
  → Rebuilds AKS + GKE clusters from scratch
  → ArgoCD re-deploys all apps automatically
  → Discord notification: "Clusters recreated ✅"

Every Sunday night:
  → terraform-schedule.yml triggers destroy job
  → Destroys all Azure + GCP resources
  → Discord notification: "Clusters destroyed 🔴"

Every PR to main:
  → ci-build.yml: lint → Trivy scan → build → push to ACR/GCR
  → cost-check.yml: Infracost estimate → OPA guard ($30 limit)
  → ArgoCD Image Updater: detects new image tag → auto-deploys to dev
```

---

## 🔑 Quick Reference — Key URLs After Deployment

| Service | How to Access |
|---------|--------------|
| ArgoCD UI | `kubectl port-forward svc/argocd-server -n argocd 8080:443` → https://localhost:8080 |
| Grafana | `kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80` → http://localhost:3000 |
| API Gateway | `kubectl get svc api-gateway -n rental-dev` → EXTERNAL-IP:8000 |
| RAG API | `kubectl port-forward svc/rag-api -n rental-dev 8080:8080` → http://localhost:8080 |
| Prometheus | `kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090` |

---

## 🚨 Common Troubleshooting

```bash
# Pod stuck in Pending (resource pressure on B2s nodes)
kubectl describe pod <pod-name> -n rental-dev | grep -A5 Events

# OOMKilled — increase memory limit in k8s/base/<service>/deployment.yaml
kubectl top pods -n rental-dev

# ArgoCD out of sync — force refresh
argocd app sync rentalapp-dev --force

# Istio sidecar not injected
kubectl get pod <pod-name> -n rental-dev -o jsonpath='{.spec.containers[*].name}'
# Should include "istio-proxy". If missing:
kubectl delete pod <pod-name> -n rental-dev   # respawn triggers injection

# Kyverno blocking a deployment
kubectl get policyreport -n rental-dev
kubectl describe clusterpolicyreport

# Gatekeeper constraint violation
kubectl get events -n rental-dev | grep constraint

# ArgoCD notifications not firing
kubectl logs -n argocd deploy/argocd-notifications-controller | tail -50

# Cost check failing OPA
cat infracost-output.json | jq '.totalMonthlyCost'
# Edit .infracost/config.yml to exclude dev resources from estimate
```

---

## 📁 Project Structure Reference

```
rentalAppLedger/
├── .github/workflows/          # CI/CD pipelines
│   ├── ci-build.yml            # Main app CI (build, scan, push)
│   ├── terraform.yml           # Infrastructure provisioning
│   ├── terraform-schedule.yml  # Weekly destroy/recreate
│   ├── cost-check.yml          # Infracost + OPA guard
│   ├── qa-validate.yml         # BDD test runner
│   └── notify.yml              # Reusable notification workflow
├── terraform/
│   ├── azure/                  # AKS, ACR, KeyVault, VNet modules
│   └── gcp/                    # GKE, Artifact Registry, VPC modules
├── k8s/
│   ├── base/                   # Base manifests (4 services)
│   └── overlays/dev|qa/        # Kustomize overlays
├── gitops/
│   ├── apps/                   # ArgoCD Application CRDs
│   └── notifications/          # ArgoCD notification templates
├── istio/                      # mTLS, gateway, virtual services
├── kyverno/                    # Admission policies + exceptions
├── gatekeeper/                 # OPA constraint templates + constraints
├── policy/                     # Conftest OPA policies + tests
├── monitoring/                 # Prometheus, Grafana, AlertManager
├── ai-tools/
│   ├── k8s-assistant/          # AI pod troubleshooter
│   └── anomaly-detector/       # Statistical anomaly detection
├── rag/                        # RAG pipeline (ChromaDB + LLM)
├── qa/                         # BDD tests + post-deploy validation
├── notify/                     # Discord + email + K8s event watcher
└── bootstrap/                  # One-time OIDC setup scripts
```

---

## ✅ Next Steps Options

Choose what to build next:

| Option | Description |
|--------|-------------|
| **A** | Write the actual FastAPI microservice code (api-gateway, rental-service, ledger-service, notification-service) |
| **B** | Create a master `Makefile` — single `make deploy` command for all Phase 3 installs |
| **C** | Create a `docker-compose.yml` for local development without Kubernetes |
| **D** | Add GitHub Environments + approval gates for QA → Prod promotion |
| **E** | Write `terraform test` files for infrastructure unit testing |
