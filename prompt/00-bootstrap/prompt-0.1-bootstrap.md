# Prompt 0.1 - Bootstrap: State Backends + Identity Prereqs

```
Act as a DevSecOps engineer preparing bootstrap prerequisites for a multi-cloud Terraform
learning project in KodeKloud Playground.

CONTEXT:
- Project: rentalAppLedger
- KodeKloud constraints:
  * Azure: Cannot create new Resource Groups (use existing RG)
  * GCP: Only default project; cannot create new project
- Goal: create Terraform state backends and minimal identity prerequisites ONCE.

TASK:
Provide a concise bootstrap plan with commands and required inputs:

1) Azure Backend (existing RG):
- Use existing resource_group_name
- Create Storage Account (Standard_LRS) + container "tfstate"
- Enable HTTPS-only on storage account
- Output: storage_account_name, container_name, resource_group_name, key

2) GCP Backend (default project):
- Create GCS bucket for tfstate
- Enable versioning
- Output: bucket_name

3) Identity prerequisites:
- Azure: create an App Registration + Service Principal for OIDC (no secrets)
- GCP: create Workload Identity Pool + Provider + Service Account (no JSON keys)

4) Files to update (placeholders only):
- Azure backend.tf
- GCP backend.tf
- GitHub Actions repo secrets list

IMPORTANT:
- Do NOT create Resource Groups or Projects.
- Assume Azure/GCP CLI is available.

OUTPUT:
- Step-by-step bootstrap commands (az + gcloud)
- Expected outputs to paste into Terraform variables
- Minimal warnings for cost and permissions
```
