# Bootstrap

One-time setup scripts that provision cloud infrastructure prerequisites and wire
GitHub Actions secrets. Run these before the first `terraform apply`.

All steps are idempotent — safe to re-run.

## Supported clouds

| Cloud | Auth | Secrets store | TF state |
|-------|------|---------------|----------|
| Azure | OIDC / Managed Identity | Azure Key Vault | Azure Blob Storage |
| GCP | OIDC / Workload Identity | Secret Manager | GCS Bucket |

## Prerequisites

| Tool | Min version |
|------|-------------|
| `az` CLI | 2.50+ |
| `gcloud` CLI | 450+ |
| Python | 3.10+ |

```bash
pip install -r bootstrap/requirements.txt
```

## Quick start

```bash
# 1. Copy and fill in the config (no secrets — names and regions only)
cp bootstrap/.env.example bootstrap/.env
$EDITOR bootstrap/.env

# 2. Login to your cloud(s)
az login                    # Azure
gcloud auth login           # GCP

# 3. Run bootstrap (creates MI/WI, Key Vault/Secret Manager, TF state bucket)
bash bootstrap/bootstrap.sh

# 4. Push GitHub Secrets from cloud secrets store → GitHub repo
python bootstrap/set-github-secrets.py
```

## Scripts

| Script | Purpose |
|--------|---------|
| `bootstrap.sh` | Creates platform resources: Managed Identity / Workload Identity, Key Vault / Secret Manager, TF state storage, OIDC federation |
| `load-secrets.sh` | Loads secrets from cloud store into shell env — **source only**, never exec directly |
| `set-github-secrets.py` | Reads secrets from cloud store → sets GitHub Actions secrets via API |
| `store-secrets.sh` | Stores manually-provided secrets (API keys, webhooks) into cloud secrets store |

## Cloud-specific notes

### Azure

`bootstrap.sh` creates or validates:
- Managed Identity in `PLATFORM_RG` with OIDC federation for GitHub Actions
- Azure Key Vault for platform and app secrets
- Storage Account + blob container for Terraform state

Resource group naming used by Terraform environments:

```
rental-app-dev    ← dev
rental-app-qa     ← qa
rental-app-uat    ← uat
rental-app-prod   ← prod
```

### GCP

`bootstrap.sh` creates or validates:
- Workload Identity Pool + Provider for GitHub OIDC
- Service Account with minimum required IAM roles
- GCS bucket for Terraform state

## Security model

```
GitHub Actions OIDC token
      │
      ▼
Cloud identity provider  (Azure AD / GCP Workload Identity)
      │  exchanges for short-lived cloud credential
      ▼
Azure Managed Identity / GCP Service Account
      │  reads from
      ▼
Azure Key Vault / GCP Secret Manager
```

No long-lived credentials stored anywhere. All cloud access uses short-lived
federated OIDC tokens that expire when the workflow run completes.

## Adding a new environment

1. Copy an existing Terraform environment:
   ```bash
   cp -r infrastructure/azure/environments/qa infrastructure/azure/environments/uat
   cp -r infrastructure/gcp/environments/qa   infrastructure/gcp/environments/uat
   ```
2. Update `backend.tf` with a new state container/bucket name
3. Update `terraform.tfvars` with environment-specific sizing
4. Add the new env to workflow `options` in:
   - `.github/workflows/terraform.yml`
   - `.github/workflows/argocd-bootstrap.yml`
5. Add entries to `.infracost/config.yml`
