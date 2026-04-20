# Infrastructure

Terraform root configs and reusable modules for Azure and GCP.

## Structure

```
infrastructure/
├── azure/
│   ├── shared/              # Permanent layer — ACR + Key Vault (run once)
│   ├── environments/
│   │   ├── dev/             # Dev AKS + SQL + VNet
│   │   └── qa/              # QA AKS + SQL + VNet
│   └── modules/
│       ├── aks/             # AKS cluster
│       ├── postgresql/      # Azure Database for PostgreSQL
│       ├── sql_database/    # Azure SQL Database
│       ├── vnet/            # Virtual Network + subnets
│       ├── keyvault/        # Key Vault secrets
│       └── budget/          # Azure cost budget
└── gcp/
    ├── environments/
    │   ├── dev/             # Dev GKE + Cloud SQL + VPC
    │   └── qa/              # QA GKE + Cloud SQL + VPC
    └── modules/
        ├── gke/             # GKE cluster
        ├── artifact_registry/ # Container registry
        ├── cloud_sql/       # Cloud SQL (PostgreSQL)
        └── vpc/             # VPC + subnets
```

## Two-tier resource group model (Azure)

| Layer | Resource Group | Contains | Lifecycle |
|---|---|---|---|
| Platform | `PLATFORM_RG` | Managed Identity, Key Vault, TF state storage | Permanent |
| App-shared | `AZURE_SHARED_RG` | ACR | Permanent |
| Env compute | auto-named per env | AKS, VNet, SQL | Created/destroyed per session |

## How to deploy

### Azure

**1 — Bootstrap (one-time):**
```bash
az login
CLOUD=azure bash bootstrap/bootstrap.sh
```

**2 — Shared layer (ACR + Key Vault, one-time):**
```
GitHub Actions → terraform.yml
  cloud: azure  action: apply  scope: full  target_env: (leave default)
  → Approve in "shared" environment gate
  → Copy ACR_NAME and KEY_VAULT_NAME outputs to GitHub Secrets
```

**3 — Env compute (per session):**
```
GitHub Actions → terraform.yml
  cloud: azure  action: apply  scope: compute-only  target_env: dev
```

Or locally:
```bash
bash .github/scripts/deploy-compute.sh azure dev
```

**4 — Destroy compute (end of session):**
```bash
bash .github/scripts/destroy-compute.sh azure dev
```

### GCP

**1 — Bootstrap (one-time):**
```bash
gcloud auth login && gcloud config set project <project-id>
CLOUD=gcp bash bootstrap/bootstrap.sh
```

**2 — Env compute:**
```
GitHub Actions → terraform.yml
  cloud: gcp  action: apply  scope: compute-only  target_env: dev
```

## State backend

Terraform state is stored in an Azure Blob Storage container (`tfstate`) inside `PLATFORM_RG`. All environments share the same backend, keyed by workspace:

| Environment | Workspace key |
|---|---|
| `dev` | `azure/dev/terraform.tfstate` |
| `qa`  | `azure/qa/terraform.tfstate` |

## Cost guardrail

`cost-check.yml` runs Infracost on every PR. OPA policy blocks apply if estimate exceeds **$22/month** (deny) or warns at **$15/month**.

See [../.infracost/config.yml](../.infracost/config.yml) for project configuration.

## Inputs reference: `terraform.yml`

| Input | Options | Default |
|---|---|---|
| `target_env` | dev / qa / uat / prod | dev |
| `cloud` | azure / gcp / both | azure |
| `action` | plan / apply / destroy | plan |
| `scope` | compute-only / full | compute-only |
| `confirm` | type env name to confirm non-dev apply/destroy | — |

`compute-only` destroys AKS/GKE + VNet/VPC but keeps ACR, Key Vault, and Storage Account.
