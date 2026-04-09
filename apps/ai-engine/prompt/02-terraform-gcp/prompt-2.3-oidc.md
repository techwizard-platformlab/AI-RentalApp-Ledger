# Prompt 2.3 - Terraform GCP: Workload Identity + GitHub Actions OIDC

```
Act as a GCP IAM and GitHub Actions security expert.

CONTEXT:
- Project: rentalAppLedger on GCP
- CI/CD: GitHub Actions
- Goal: Terraform + kubectl pipelines authenticate to GCP via OIDC - no JSON keys

TASK:
Generate Terraform + GitHub Actions code for:

1. Workload Identity Pool + Provider:
   - Pool: github-actions-pool
   - Provider: github-oidc
   - Attribute mapping: google.subject = assertion.sub
   - Condition: attribute.repository == "{github_org}/{repo}"

2. GCP Service Account for Terraform:
   - Roles: roles/editor (dev only - note to restrict in prod)
   - Roles: roles/container.admin, roles/secretmanager.admin
   - Bind to Workload Identity Pool

3. GitHub Actions step using google-github-actions/auth@v2:
   - workload_identity_provider reference
   - service_account reference
   - No JSON key file anywhere

4. GCP provider block using OIDC (no credentials file):
   provider "google" {
     // credentials provided via OIDC at runtime
   }

5. GitHub repository secrets needed:
   - GCP_WORKLOAD_IDENTITY_PROVIDER
   - GCP_SERVICE_ACCOUNT

ALSO INCLUDE:
- How to verify OIDC token claims (gcloud iam command)
- .gitignore: never commit *.json credentials
- Difference between JSON key (bad) vs OIDC (good) - one-paragraph explainer

OUTPUT: Terraform files + GitHub Actions YAML snippet + security notes
```
