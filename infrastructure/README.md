# Infrastructure

Modular Terraform infrastructure supporting Azure and GCP, with separate
per-environment configurations for dev, qa, uat, and prod.

## Folder structure

```
infrastructure/
├── azure/
│   ├── modules/                  # Reusable Azure Terraform modules
│   │   ├── acr/                  # Azure Container Registry
│   │   ├── aks/                  # Azure Kubernetes Service
│   │   ├── budget/               # Cost management budgets
│   │   ├── keyvault/             # Azure Key Vault
│   │   ├── load_balancer/        # Application Gateway / Load Balancer
│   │   ├── postgresql/           # Azure PostgreSQL Flexible Server
│   │   ├── security_group/       # Network Security Groups
│   │   ├── service_principal/    # Service Principal + OIDC federation
│   │   ├── sql_database/         # Azure SQL Database
│   │   ├── storage_account/      # Storage (TF state, app data)
│   │   ├── subnet/               # Virtual network subnets
│   │   ├── vnet/                 # Virtual Network
│   │   └── waf_policy/           # Web Application Firewall
│   │
│   └── environments/
│       ├── dev/                  # Dev environment root module
│       └── qa/                   # QA environment root module
│
└── gcp/
    ├── modules/                  # Reusable GCP Terraform modules
    │   ├── artifact_registry/    # Artifact Registry (container images)
    │   ├── cloud_armor/          # Cloud Armor (DDoS / WAF)
    │   ├── cloud_sql/            # Cloud SQL (managed PostgreSQL)
    │   ├── gke/                  # Google Kubernetes Engine
    │   ├── secret_manager/       # Secret Manager
    │   ├── storage_bucket/       # GCS buckets
    │   ├── vpc/                  # Virtual Private Cloud
    │   └── workload_identity/    # Workload Identity Pool + SA
    │
    ├── shared/                   # Shared GCP resources (cross-project)
    │
    └── environments/
        ├── dev/                  # Dev environment root module
        └── qa/                   # QA environment root module
```

## Module conventions

Each module follows the standard Terraform module structure:

```
modules/<name>/
  main.tf        # Resources
  variables.tf   # Input variables (all typed, all documented)
  outputs.tf     # Output values consumed by root modules
```

Modules never contain backend config or provider blocks — those live only in
the environment root modules.

## Environment root modules

Each environment (`environments/<env>/`) is a standalone Terraform root that:
- Composes modules via `module` blocks in `main.tf`
- Declares a remote backend in `backend.tf` (unique state per env)
- Provides non-sensitive defaults in `terraform.tfvars`
- Resolves sensitive values at runtime from GitHub Secrets (via `TF_VAR_*`)

## Azure vs GCP

| Capability | Azure | GCP |
|-----------|-------|-----|
| Kubernetes | AKS (`modules/aks`) | GKE (`modules/gke`) |
| Container registry | ACR (`modules/acr`) | Artifact Registry (`modules/artifact_registry`) |
| Database | PostgreSQL Flexible Server or SQL Database | Cloud SQL (`modules/cloud_sql`) |
| Secrets | Key Vault (`modules/keyvault`) | Secret Manager (`modules/secret_manager`) |
| Networking | VNet + Subnet + NSG | VPC + Subnets |
| Auth | Managed Identity + Federated Credential | Workload Identity |
| TF state | Azure Blob Storage | GCS Bucket |

## How to deploy

### Prerequisites

1. Run `bash bootstrap/bootstrap.sh` once to create platform resources
2. Ensure GitHub Secrets are set (run `python bootstrap/set-github-secrets.py`)

### Via GitHub Actions (recommended)

```
Actions → Infra → plan → select cloud + env → review PR comment → apply
```

### Manual (local)

```bash
# Azure dev
cd infrastructure/azure/environments/dev
az login
terraform init \
  -backend-config="resource_group_name=$TF_BACKEND_RG" \
  -backend-config="storage_account_name=$TF_BACKEND_SA" \
  -backend-config="container_name=rentalapp-dev-tfstate"
terraform plan -out=tfplan
terraform apply tfplan

# GCP dev
cd infrastructure/gcp/environments/dev
gcloud auth application-default login
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### Compute-only deploy/destroy (save costs)

```bash
# Destroy cluster + networking (keep DB, registry, secrets)
.github/scripts/destroy-compute.sh azure dev

# Re-deploy cluster + networking
.github/scripts/deploy-compute.sh azure dev
```

## Adding a new environment

1. Copy an existing environment:
   ```bash
   cp -r infrastructure/azure/environments/qa infrastructure/azure/environments/uat
   cp -r infrastructure/gcp/environments/qa   infrastructure/gcp/environments/uat
   ```
2. In the new `backend.tf`, change the state container/bucket name
3. In `terraform.tfvars`, adjust sizing for the new environment
4. Add `uat` entries to `.infracost/config.yml`
5. Wire the environment in workflows (argocd-bootstrap.yml, terraform.yml)

## Adding a new module

1. Create `infrastructure/azure/modules/<name>/` with `main.tf`, `variables.tf`, `outputs.tf`
2. Add a `module "<name>"` block in the relevant environment `main.tf`
3. Wire outputs through `outputs.tf` if other modules depend on them
4. Document required variables in `variables.tf` with `description` fields

## Cost model

The platform uses a **deploy-destroy** pattern to minimize costs:
- Cluster + networking: destroyed after each session
- Registry, database, secrets: always running (cheap persistent resources)

OPA budget enforcement: deny if projected monthly cost > $22, warn if > $15.
See `platform/security/policies/cost/tf_plan_cost.rego`.
