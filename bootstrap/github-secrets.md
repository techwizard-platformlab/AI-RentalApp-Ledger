# GitHub Secrets & Variables Reference

Add in: **repo Settings → Secrets and variables → Actions → New repository secret**

Run both bootstrap scripts first and copy the printed outputs here.

---

## How secrets become Terraform variables

The workflow injects secrets as `TF_VAR_*` env vars at the job level.
Terraform picks them up automatically — no `-var=` flags needed in commands.

```
GitHub Secret: AZURE_RESOURCE_GROUP
       ↓  (workflow env block)
TF_VAR_resource_group_name: ${{ secrets.AZURE_RESOURCE_GROUP }}
       ↓  (Terraform auto-loads TF_VAR_* prefix)
var.resource_group_name  (sensitive = true in variables.tf)
```

Non-secret config (`environment`, `location`, `region`) lives in the committed
`terraform.tfvars` file in each environment directory.

---

## Azure Secrets (repo-level)

| Secret Name              | Where to get it                            | Becomes TF_VAR? |
|--------------------------|--------------------------------------------|-----------------|
| `AZURE_CLIENT_ID`        | App Registration → Application (client) ID | No (ARM_ var)   |
| `AZURE_TENANT_ID`        | Azure Active Directory → Tenant ID         | No (ARM_ var)   |
| `AZURE_SUBSCRIPTION_ID`  | `az account show --query id`               | No (ARM_ var)   |
| `AZURE_RESOURCE_GROUP`   | Existing KodeKloud resource group name     | `TF_VAR_resource_group_name` |

> No `AZURE_CLIENT_SECRET` — OIDC federated credentials are used.

---

## GCP Secrets (repo-level)

| Secret Name                      | Where to get it                          | Becomes TF_VAR? |
|----------------------------------|------------------------------------------|-----------------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Printed by bootstrap / Terraform output  | No (OIDC auth)  |
| `GCP_SERVICE_ACCOUNT`            | `github-actions-oidc@<project>.iam...`   | No (OIDC auth)  |
| `GCP_PROJECT_ID`                 | `gcloud config get-value project`        | `TF_VAR_project_id` |

> No `GCP_SA_KEY` (JSON key) — Workload Identity Federation is used.

---

## Notification Secrets

| Secret Name           | Purpose                              |
|-----------------------|--------------------------------------|
| `DISCORD_WEBHOOK_URL` | Destroy/recreate schedule alerts     |

---

## App Secrets (added in Phase 4 — K8s)

| Secret Name           | Purpose                              |
|-----------------------|--------------------------------------|
| `POSTGRES_PASSWORD`   | Injected into K8s Secret             |
| `DJANGO_SECRET_KEY`   | Injected into K8s Secret             |
| `INFRACOST_API_KEY`   | Cost estimation (Phase 6 OPA)        |

---

## GitHub Environments — approval gates

Configure in: repo **Settings → Environments**

| Environment   | Protection rule                        |
|---------------|----------------------------------------|
| `azure-dev`   | No approval (auto plan + apply on PR/push) |
| `azure-qa`    | 1 required reviewer                    |
| `azure-uat`   | 1 required reviewer                    |
| `azure-prod`  | 2 required reviewers + 15-min wait     |
| `gcp-dev`     | No approval                            |
| `gcp-qa`      | 1 required reviewer                    |
| `gcp-uat`     | 1 required reviewer                    |
| `gcp-prod`    | 2 required reviewers + 15-min wait     |

Each environment can override repo-level secrets if different credentials are
needed per environment (e.g. separate service principal per env in production).

---

## terraform.tfvars — what IS committed (not secrets)

```hcl
# terraform/azure/environments/dev/terraform.tfvars
environment = "dev"
location    = "eastus"

# terraform/gcp/environments/dev/terraform.tfvars
environment = "dev"
region      = "us-central1"
github_org  = "ramprasath-technology"
github_repo = "AI-RentalApp-Ledger"
```
