# rentalAppLedger — Full Deployment Steps & Reference

> **Project**: rentalAppLedger — Django REST API + microservices on AKS (Azure) + GKE (GCP)
> **Cost target**: ~400 INR / ~$5 USD per week — compute destroyed between sessions
> **Cycle**: `deploy-compute.sh` at session start → `destroy-compute.sh` at session end

---

## ✅ What's Been Built (Prompts 00 → 11)

| Prompt | Layer | Key Files |
|--------|-------|-----------|
| 00 | Bootstrap (OIDC, secrets) | `bootstrap/azure/bootstrap.sh`, `bootstrap/gcp/bootstrap.sh` |
| 01 | Terraform — Azure | `infrastructure/azure/` (AKS, ACR, KeyVault, VNet) |
| 02 | Terraform — GCP | `infrastructure/gcp/` (GKE, Artifact Registry, VPC) |
| 03 | GitHub Actions CI | `.github/workflows/ci-build.yml` |
| 04 | K8s manifests + ArgoCD | `platform/kubernetes/`, `platform/gitops/argocd/` |
| 05 | Istio mTLS + Kyverno | `platform/networking/istio/`, `platform/security/kyverno/` |
| 06 | OPA + Gatekeeper + Infracost | `platform/security/policies/`, `platform/security/gatekeeper/`, `.infracost/` |
| 07 | Prometheus + Grafana | `platform/observability/monitoring/` |
| 08 | AI K8s Assistant + Anomaly Detector | `apps/ai-engine/tools/` |
| 09 | RAG Pipeline | `apps/ai-engine/rag/` |
| 10 | BDD Tests + Post-Deploy Validation | `tests/dev/testing/` |
| 11 | Discord + Email + ArgoCD Notifications | `platform/observability/alerting/`, `platform/gitops/argocd/notifications/` |

---

## PHASE 1 — One-Time Bootstrap (Run Locally First)

> **Secret model**: secrets (PATs, webhooks) are stored in Azure Key Vault — never in files.
> `bootstrap/.env` holds only non-secret identifiers (IDs, names, regions).

### Step 1 — Fill in bootstrap/.env (identifiers only, no secrets)

```bash
cp bootstrap/.env.example bootstrap/.env
# Edit bootstrap/.env — set AZURE_SUBSCRIPTION_ID, AZURE_TENANT_ID,
# AZURE_CLIENT_ID, AZURE_SHARED_RG, GITHUB_ORG, GITHUB_REPO, etc.
# Do NOT add PATs or webhook URLs here — those go to Key Vault in Step 4.
```

### Step 2 — Run the bootstrap script

```bash
az login    # browser-based login, once per session

bash bootstrap/bootstrap.sh
# → Creates Terraform state storage account in my-Rental-App
# → Creates OIDC federated credentials on Managed Identity
# → Prints the GitHub Secrets table at the end
```

For GCP:
```bash
gcloud auth login
gcloud config set project <your-project-id>
CLOUD=gcp bash bootstrap/bootstrap.sh
```

### Step 2.1 — Configure GitHub Environments (Manual UI Step)

You must create these environments in your GitHub repository to enable OIDC authentication and the approval gate.

1.  Go to **Settings** → **Environments** → **New environment**.
2.  Create **`dev`**:
    *   No protection rules needed.
    *   Used for OIDC auth from *any* feature branch.
3.  Create **`qa`**:
    *   No protection rules needed.
4.  Create **`terraform-destructive-approval`**:
    *   **Required reviewers**: Add yourself.
    *   This is the mandatory gate for all `apply` and `destroy` actions.

> [!TIP]
> Ensure **Deployment branches** for `dev` and `qa` are set to **"All branches"** to allow testing pipelines from feature branches.

### Step 3 — Push identifiers to GitHub Secrets

```bash
pip install -r bootstrap/requirements.txt
python bootstrap/set-github-secrets.py --dry-run   # preview first
python bootstrap/set-github-secrets.py              # push to GitHub
# → Prompts for GitHub PAT interactively (not read from any file)
```

### Step 4 — Provision shared layer (creates Key Vault + ACR)

```
GitHub → Actions → Infra (terraform.yml)
  cloud: azure | action: apply → Approve at "shared" gate
  → Key Vault and ACR are created here
```

After apply, update `bootstrap/.env` with the outputs:
```bash
terraform -chdir=infrastructure/azure/shared output -raw acr_name      # → ACR_NAME
terraform -chdir=infrastructure/azure/shared output -raw key_vault_name # → KEY_VAULT_NAME
# Edit bootstrap/.env: fill in ACR_NAME and KEY_VAULT_NAME
```

### Step 5 — Store secrets in Key Vault (run once)

```bash
bash bootstrap/store-secrets.sh
# Prompts for each secret (input hidden, never written to disk):
#   github-pat        → GitHub PAT with 'repo' scope
#   argocd-github-pat → GitHub PAT for ArgoCD
#   discord-webhook   → Discord channel webhook URL
```

### Step 6 — Push secrets + ACR name to GitHub

```bash
python bootstrap/set-github-secrets.py
# → PAT is loaded automatically from Key Vault (no manual input needed)
# → Pushes DISCORD_WEBHOOK_URL, ACR_NAME, ACR_LOGIN_SERVER, etc.
```

### Day-to-day: load secrets in a new terminal

```bash
source bootstrap/load-secrets.sh
# Exports GITHUB_PAT, ARGOCD_GITHUB_PAT, DISCORD_WEBHOOK_URL into the shell
# Memory only — cleared when the terminal closes. No files written.
```

---

---

## PHASE 2 — Infrastructure Pipeline (Terraform)

Use the **Infra** workflow (`terraform.yml`) to manage your cloud resources.

### Step 4 — Run Infra Pipeline (Plan)

1.  GitHub → **Actions** → **Infra** → **Run workflow**.
2.  Inputs:
    - **Target environment**: `dev` or `qa`
    - **Target cloud**: `azure` (or `gcp` / `both`)
    - **Action**: `plan`
    - **Scope**: `full` (for first run) or `compute-only`
3.  **Verify the Plan**:
    - ✔ **Lint & validate**: terraform fmt -check, terraform validate
    - ✔ **Security Scan**: `tfsec` must show 0 critical findings.
    - ✔ **OPA Cost Check**: Check the Job Summary for budget compliance.
    - ✔ **Plan output**: Inspect the logs to see what will be created.

### Step 5 — Run Infra Pipeline (Apply)

1.  GitHub → **Actions** → **Infra** → **Run workflow**.
2.  Inputs:
    - **Action**: `apply`
    - **Scope**: `full` (for first run to create ACR/KV) or `compute-only`
3.  **Approve**:
    - The workflow will pause at the **terraform-destructive-approval** gate.
    - Click **Review deployment** and **Approve**.

Wait 10-15 minutes for AKS/GKE and managed databases to be provisioned.

---

## PHASE 3 — GitOps Pipeline (ArgoCD & Add-ons)

Use the **ArgoCD Bootstrap** workflow (`argocd-bootstrap.yml`) to install the platform layer.

### Step 6 — Install ArgoCD

1.  GitHub → **Actions** → **ArgoCD Bootstrap** → **Run workflow**.
2.  Inputs:
    - **Action**: `install`
    - **Cloud**: `azure` (or `gcp`)
    - **Database backend**: `azure-pg` (matches your Terraform config)
3.  **What happens**:
    - Installs ArgoCD via Helm.
    - Configures External Secrets Operator (ESO) for Key Vault access.
    - Registers the GitHub repo as a source in ArgoCD.

### Step 7 — Deploy Applications

1.  GitHub → **Actions** → **ArgoCD Bootstrap** → **Run workflow**.
2.  Inputs:
    - **Action**: `apply-apps`
3.  **What happens**:
    - Applies `AppProject` and `Application` CRDs.
    - ArgoCD begins syncing manifests from `platform/kubernetes/overlays/dev`.

### Step 8 — Install Platform Add-ons

1.  GitHub → **Actions** → **ArgoCD Bootstrap** → **Run workflow**.
2.  Inputs:
    - **Action**: `apply-addons`
    - **Add-ons scope**: `all` (Istio + Prometheus/Grafana)
3.  **What happens**:
    - Deploys Istio service mesh (mTLS, Gateway).
    - Deploys Prometheus, Grafana, and Alertmanager.
    - Configures dashboards and alert rules.

---

## PHASE 4 — Day-to-Day Lifecycle (Cost-Saving Pattern)

To keep costs under **$5/week**, destroy compute (AKS/GKE) when not in use.

### Start a Session (Create Compute)

1.  GitHub → **Actions** → **Infra**
2.  Inputs: **action: apply**, **scope: compute-only**.
3.  Wait ~10 mins for cluster to be ready. ArgoCD will auto-sync applications.

### End a Session (Destroy Compute)

1.  GitHub → **Actions** → **Infra**
2.  Inputs: **action: destroy**, **scope: compute-only**.
3.  **Kept**: ACR (images), SQL (data), Key Vault (secrets) — no data loss.
4.  **Destroyed**: AKS/GKE, VNet/VPC, Load Balancer — billing stops.

---

---

## PHASE 4 — AI Engine & Advanced Tools

Deploy the AI-augmented components of the platform.

### Step 9 — Deploy RAG Pipeline

1.  **Deploy API**:
    ```bash
    kubectl apply -f apps/ai-engine/rag/k8s/deployment.yaml
    ```
2.  **Deploy Indexer**:
    ```bash
    kubectl apply -f apps/ai-engine/rag/k8s/cronjob-indexer.yaml
    ```
3.  **Seed Test Data**:
    ```bash
    python apps/ai-engine/rag/seed_test_data.py
    ```

### Step 10 — Deploy AI Assistant Tools

1.  **K8s Assistant**:
    ```bash
    kubectl apply -f apps/ai-engine/tools/k8s-assistant/rbac.yaml
    # Run locally or as a pod:
    python apps/ai-engine/tools/k8s-assistant/k8s-assistant.py --watch
    ```
2.  **Anomaly Detector**:
    ```bash
    kubectl apply -f apps/ai-engine/tools/anomaly-detector/k8s/cronjob.yaml
    ```

---

## PHASE 5 — Validation & Testing

Verify the deployment is healthy and secure.

### Step 11 — Run Manifest Validation

- GitHub → **Actions** → **K8s Validate** → **Run workflow**.
- Validates manifests via `kubeconform` and `kustomize build`.

### Step 12 — Post-Deploy Health Check

- Run the automated validation script:
  ```bash
  bash tests/shared/testing/validate_deployment.sh --cloud azure --env dev --notify discord
  ```

---

## PHASE 6 — Lifecycle Management

### Start Session (Create Compute)

- GitHub → **Actions** → **Infra** → **action: apply**, **scope: compute-only**.
- ArgoCD automatically reconciles applications once the cluster is up.

### End Session (Destroy Compute)

- GitHub → **Actions** → **Infra** → **action: destroy**, **scope: compute-only**.
- **Important**: This stops compute billing while preserving data in SQL and ACR.

---

## 🔑 Quick Reference — Key URLs

| Service | Access Command |
|---------|----------------|
| **ArgoCD UI** | `kubectl port-forward svc/argocd-server -n argocd 8080:443` |
| **Grafana** | `kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80` |
| **API Gateway** | `kubectl get svc api-gateway -n rental-dev` |
| **RAG API** | `kubectl port-forward svc/rag-api -n rental-dev 8080:8080` |

---

## 📁 Project Structure Reference

```
AI-RentalApp-Ledger/
├── .github/workflows/   # CI/CD Pipelines (Infra, ArgoCD, Validate)
├── apps/ai-engine/      # RAG Pipeline & AI Assistant Tools
├── bootstrap/           # One-time Cloud Setup Scripts
├── infrastructure/      # Terraform Modules (Azure & GCP)
├── platform/
│   ├── gitops/          # ArgoCD Charts & App Definitions
│   ├── kubernetes/      # K8s Manifests (Base & Overlays)
│   ├── networking/      # Istio Service Mesh
│   └── observability/   # Prometheus & Grafana
└── tests/               # BDD Tests & Health Check Scripts
```
