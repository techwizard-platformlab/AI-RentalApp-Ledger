# Bootstrap — One-time Cloud Setup

Run **once** per subscription/project before any Terraform work. All steps are idempotent — safe to re-run.

---

## Resource Group Model

```
PLATFORM_RG  (shared across ALL your apps — pre-existing, you created this)
  ├── Managed Identity    ← GitHub Actions authenticates as this
  └── Key Vault           ← all secrets live here (shared + app-scoped)

AZURE_SHARED_RG  (this project only — my-Rental-App)
  ├── ACR                 ← container registry for AI-RentalApp-Ledger
  └── Terraform state SA  ← tfstate blobs

my-Rental-App-Dev / QA   (Terraform-owned — safe to destroy)
  ├── AKS, VNet, PostgreSQL, Storage
  └── Per-env Key Vault   ← app runtime secrets (DB passwords, ACR URL)
```

## Secret Management Model

```
❌ Old (unsafe):  secrets stored in bootstrap/.env file on disk
✅ New (secure):  secrets stored in platform Key Vault, fetched at runtime
```

| Type | Where stored | Examples |
|------|-------------|---------|
| Identifiers | `bootstrap/.env` (gitignored, safe on disk) | Subscription ID, RG names |
| Shared secrets | Platform Key Vault (`PLATFORM_KV_NAME`) | `github-pat`, `argocd-github-pat` |
| App secrets | Platform Key Vault (prefixed `rentalapp-`) | `rentalapp-discord-webhook` |
| Runtime secrets | Per-env Key Vault (Terraform-managed) | DB password, ACR login server |
| CI secrets | GitHub Actions Secrets | Injected by `set-github-secrets.py` |

**`bootstrap/.env` contains only non-secret identifiers** — IDs, names, regions. Gitignored but safe to store locally.

---

## Prerequisites

```bash
# Azure CLI
az login
az account set --subscription "<your-subscription-id>"

# Python dependencies (for set-github-secrets.py)
pip install -r bootstrap/requirements.txt
```

---

## Phase 1 — Fill in bootstrap/.env

```bash
cp bootstrap/.env.example bootstrap/.env

# Required fields:
#   PLATFORM_RG        ← your central RG (with MI + KV)
#   PLATFORM_KV_NAME   ← Key Vault name inside PLATFORM_RG
#   PLATFORM_MI_NAME   ← Managed Identity name
#   AZURE_SUBSCRIPTION_ID, AZURE_TENANT_ID, AZURE_CLIENT_ID
#   AZURE_SHARED_RG    ← app-specific RG (my-Rental-App)
#   GITHUB_ORG, GITHUB_REPO
```

Lookup commands:
```bash
az account show --query id          -o tsv   # AZURE_SUBSCRIPTION_ID
az account show --query tenantId    -o tsv   # AZURE_TENANT_ID
az identity show --name <mi-name> \
  --resource-group <platform-rg> \
  --query clientId -o tsv                    # AZURE_CLIENT_ID
```

---

## Phase 2 — Run bootstrap (creates Terraform state storage)

```bash
az login
bash bootstrap/bootstrap.sh

# → Creates storage account in AZURE_SHARED_RG (my-Rental-App)
# → Adds OIDC federated credentials to the Managed Identity in PLATFORM_RG
# → Prints all GitHub Secrets values at the end
```

---

## Phase 3 — Store secrets in platform Key Vault (run once)

```bash
bash bootstrap/store-secrets.sh
```

Prompts for each secret interactively (input hidden, never written to disk):
- `github-pat` — shared GitHub PAT (`repo` scope) — used by all your apps
- `argocd-github-pat` — shared GitHub PAT for ArgoCD
- `rentalapp-discord-webhook` — Discord webhook for this app (app-prefixed)

---

## Phase 4 — Provision app shared layer (creates ACR)

```
GitHub → Actions → Infra (terraform.yml)
  cloud: azure | action: apply → Approve at "shared" gate
  → ACR is created in AZURE_SHARED_RG
```

After apply, update `bootstrap/.env`:
```bash
terraform -chdir=infrastructure/azure/shared output -raw acr_name  # → ACR_NAME
# Edit bootstrap/.env: fill in ACR_NAME and ACR_LOGIN_SERVER
```

---

## Phase 4 — Push secrets to GitHub Actions

```bash
# Loads PAT from Key Vault automatically, then pushes all secrets
python bootstrap/set-github-secrets.py

# Preview without making changes
python bootstrap/set-github-secrets.py --dry-run

# Push only to build repo (after ACR_NAME is known)
python bootstrap/set-github-secrets.py --repo build
```

---

## Day-to-day: Load secrets into a new terminal session

Secrets are never stored on disk. Source this in each terminal where you need them:

```bash
source bootstrap/load-secrets.sh

# Loads into current shell (memory only — gone when terminal closes):
#   GITHUB_PAT
#   ARGOCD_GITHUB_PAT
#   DISCORD_WEBHOOK_URL
```

---

## Auth model

```
No client secrets. No rotating passwords. No .env secrets.

GitHub Actions  →  OIDC token  →  Azure AD
                                      │
                              Federated credential
                              on Managed Identity
                                      │
                              ARM API calls (Terraform, az CLI)

Local shell     →  az login   →  Azure AD
                                      │
                              Key Vault (RBAC)
                                      │
                              Secrets fetched at runtime
```

---

## Bootstrap script files

| File | Purpose |
|------|---------|
| `bootstrap.sh` | Creates storage account, managed identity, OIDC federated creds |
| `store-secrets.sh` | Prompts for secrets and stores them in Key Vault (run once) |
| `load-secrets.sh` | Sources secrets from Key Vault into current shell session |
| `set-github-secrets.py` | Pushes all GitHub Actions secrets (reads PAT from KV) |
| `.env` | Non-secret identifiers only (IDs, names, regions) |
| `.env.example` | Committed template — placeholder values only |

---

## Resource group layout

```
my-Rental-App          ← permanent, never destroyed by Terraform
  ├── automation           (Managed Identity for GitHub Actions OIDC)
  ├── rentalledgertfXXXX   (Terraform state storage account)
  ├── kv-rentalXXXXXXXX    (Key Vault — secrets: github-pat, discord-webhook)
  └── rentaleusacrXXXXX    (ACR — from shared Terraform)

my-Rental-App-Dev      ← Terraform-owned, safe to destroy/recreate
  ├── AKS cluster
  ├── VNet + subnets
  ├── PostgreSQL Flexible Server
  └── Storage account (uploads/backups)

my-Rental-App-QA       ← same pattern as Dev
```

---

## Cost

- Storage Account (Standard_LRS): ~$0.02/GB/month — negligible for tfstate
- Managed Identity: free
- Key Vault: ~$1/month (standard tier, per-operation pricing)
- Federated credentials: free

---

See [STEPS.md](../STEPS.md) for the complete step-by-step deployment playbook.
