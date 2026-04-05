# Phase 0 — Bootstrap

Run **once** at the start of each KodeKloud session before any Terraform work.

## What this phase sets up

| Component | Azure | GCP |
|-----------|-------|-----|
| Terraform state backend | Storage Account + blob container | GCS bucket with versioning |
| Identity for CI/CD | App Registration + Service Principal (OIDC) | Workload Identity Pool + Provider + Service Account |
| Long-lived secrets needed | None | None |

---

## Prerequisites

- Azure CLI (`az`) logged in: `az login`
- gcloud CLI logged in: `gcloud auth login && gcloud auth application-default login`
- Know your existing Azure Resource Group name (KodeKloud pre-creates it)
- Know your GitHub org/username and repo name

---

## Steps

### 1. Azure

```bash
# Edit INPUTS section at the top of the script first
vim bootstrap/azure/bootstrap.sh

bash bootstrap/azure/bootstrap.sh
```

Copy the printed outputs into:
- [terraform/azure/backend.tf](../terraform/azure/backend.tf) — replace `<placeholders>`
- GitHub repo secrets (see [github-secrets.md](github-secrets.md))

### 2. GCP

```bash
# Ensure correct project is set
gcloud config set project <your-default-project-id>

# Edit INPUTS section at the top of the script first
vim bootstrap/gcp/bootstrap.sh

bash bootstrap/gcp/bootstrap.sh
```

Copy the printed outputs into:
- [terraform/gcp/backend.tf](../terraform/gcp/backend.tf) — replace `<placeholders>`
- GitHub repo secrets (see [github-secrets.md](github-secrets.md))

---

## KodeKloud Constraints

- Azure: Cannot create Resource Groups — script uses existing RG only.
- GCP: Only default project — script uses `gcloud config get-value project`.
- Session limit: 1 hour/day — re-run bootstrap if the session expires and resources were lost.

---

## Cost Warnings

- Azure Storage Account (Standard_LRS): ~$0.02/GB/month — negligible for tfstate.
- GCS bucket: free tier covers small state files.
- Service Principals and Workload Identity: free.
- No VMs or clusters are created in this phase.

---

## Next Step

Proceed to **Phase 1**: [terraform/azure/](../terraform/azure/) — Modular Azure infrastructure.
