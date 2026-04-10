# Bootstrap — One-time Cloud Setup

Run **once** per subscription/project before any Terraform work. Safe to re-run — all steps are idempotent.

## What this sets up

| Component | Where | Purpose |
|-----------|-------|---------|
| Terraform state storage account | `my-Rental-App` (permanent RG) | Stores tfstate across all envs |
| `tfstate` blob container | inside storage account | One container, one key per env |
| `my-Rental-App-Dev` resource group | Azure | Env resources (AKS, SQL, VNet) |
| `my-Rental-App-QA` resource group | Azure | QA env resources |
| Managed Identity role assignments | 6 roles on 3 RGs | Allows Terraform to create/destroy resources |
| Federated credentials (OIDC) | 5 credentials | Trust GitHub Actions — no client secrets |

## Prerequisites

- Azure CLI logged in: `az login`
- Managed Identity already created in `my-Rental-App` via Azure Portal or:
  ```bash
  az identity create --name automation-identity --resource-group my-Rental-App --location eastus
  ```
- `bootstrap/.env` filled in (copy from `bootstrap/.env.example`)

## Steps

### 1. Fill in bootstrap/.env

```bash
cp bootstrap/.env.example bootstrap/.env
# Edit bootstrap/.env — fill in AZURE_SUBSCRIPTION_ID, AZURE_TENANT_ID,
# AZURE_CLIENT_ID (managed identity), GITHUB_PAT, etc.
```

### 2. Run the Azure bootstrap script

```bash
bash bootstrap/azure/bootstrap.sh
```

The script will:
- Create Terraform state storage account + container in `my-Rental-App`
- Create `my-Rental-App-Dev` and `my-Rental-App-QA` resource groups
- Assign 6 roles to the managed identity (Contributor, Storage Blob, Key Vault, AcrPush)
- Create 5 OIDC federated credentials for both repos
- Print the complete GitHub Secrets table for both repos

### 3. Push secrets to GitHub

```bash
pip install requests pynacl
python bootstrap/set-github-secrets.py --dry-run   # preview first
python bootstrap/set-github-secrets.py              # push to both repos
```

### 4. Provision shared layer (ACR + Key Vault — once only)

```
GitHub → Actions → Infra (terraform.yml)
  cloud: azure | action: apply
  → Approve at "shared" environment gate
  → Job Summary shows ACR_NAME and KEY_VAULT_NAME
```

Add those values to `bootstrap/.env`, then re-run:
```bash
python bootstrap/set-github-secrets.py --repo build   # push ACR secrets to RentalApp-Build
```

---

## Auth model

```
No client secrets. No rotating passwords.

GitHub Actions  →  OIDC token  →  Azure AD
                                      │
                              Federated credential
                              on Managed Identity
                                      │
                              ARM API calls
                              (Terraform, az CLI)
```

Federated credentials created by bootstrap.sh:

| Name | Subject | Used by |
|------|---------|---------|
| `github-platform-dev` | `environment:dev` | terraform.yml dev runs |
| `github-platform-destructive` | `environment:terraform-destructive-approval` | destroy/apply gate |
| `github-platform-shared` | `environment:shared` | shared Terraform apply |
| `github-build-main` | `ref:refs/heads/main` | RentalApp-Build CI |
| `github-build-dispatch` | `workflow_dispatch` | manual CI triggers |

---

## Resource group layout

```
my-Rental-App          ← permanent, never destroyed by Terraform
  ├── automation-identity   (Managed Identity)
  ├── rentalledgertfXXXX    (State storage account)
  ├── rental-shared-kv-XXX  (Key Vault — from shared Terraform)
  └── rentalXXXacr          (ACR — from shared Terraform)

my-Rental-App-Dev      ← Terraform-owned, safe to destroy/recreate
  ├── AKS cluster
  ├── VNet + subnets
  ├── PostgreSQL Flexible Server (or Azure SQL — selectable)
  └── Storage account (uploads/backups)

my-Rental-App-QA       ← same pattern as Dev
```

---

## Cost

- Storage Account (Standard_LRS): ~$0.02/GB/month — negligible for tfstate
- Managed Identity: free
- Federated credentials: free
- No VMs or clusters created in this phase

## Next step

Proceed to **Phase 1**: `infrastructure/azure/environments/dev/` — deploy AKS, database, networking.

See [STEPS.md](../STEPS.md) for the full step-by-step playbook.
