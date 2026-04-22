# Prompt 3.1 - GitHub Actions: Terraform Pipeline (Plan, Apply, Destroy)

```
Act as a Senior DevSecOps Engineer specialising in GitHub Actions and Terraform.

CONTEXT:
- Repo: infrastructure repo (AI-RentalApp-Ledger)
- Clouds: Azure AND GCP (run in parallel within the same workflow)
- Environments: dev, qa, uat, prod (runtime input — NOT separate files per env)
- Auth: OIDC for both Azure and GCP (no stored secrets, no JSON keys)
- State: Azure Blob (azurerm backend) + GCS bucket — one state file per env per cloud
- Playground constraint: destroy every Sunday night, recreate Saturday morning
  (KodeKloud 1-hour session limit — must automate lifecycle)
- Timezone note: 18:00 UTC = 23:30 IST

DESIGN PRINCIPLE:
One workflow file per concern — NOT one file per environment or one file per action.
Environment is a RUNTIME INPUT, not a file split. Approval gates are enforced by
GitHub Environments (repo Settings → Environments), not by separate workflow files.

.github/workflows/ FINAL STRUCTURE:
  terraform.yml          ← ALL envs, ALL actions (plan/apply/destroy), runtime inputs
  terraform-schedule.yml ← cron destroy + recreate (dev only, no user input)

TASK:
Generate these 2 workflow files:

─────────────────────────────────────────────────────────────────────────────
File 1: terraform.yml
─────────────────────────────────────────────────────────────────────────────

Triggers:
  pull_request to main  → auto: env=dev, action=plan
  push to main          → auto: env=dev, action=apply
  workflow_dispatch     → user selects: environment / cloud / action

workflow_dispatch inputs:
  environment: choice [dev, qa, uat, prod]  default: dev
  cloud:       choice [azure, gcp, both]    default: both
  action:      choice [plan, apply, destroy] default: plan
  confirm:     string (required for apply/destroy on non-dev envs — type env name)

Jobs:
  setup job (runs first):
    - Resolves env/action/cloud from trigger context
    - For PR:   env=dev,  action=plan
    - For push: env=dev,  action=apply
    - For dispatch: use inputs; validate confirm field for non-dev apply/destroy
    - Outputs: env, action, run_azure, run_gcp

  azure job (runs after setup, if run_azure=true):
    - environment: azure-${env}   ← dynamic; GitHub enforces approval gate per env
    - working-directory: infrastructure/azure/environments/${env}  ← dynamic
    - Steps: fmt check → init → validate → tfsec → plan (if not destroy) →
             OPA/conftest check (if not destroy) → apply OR destroy
    - Post plan output as PR comment (github-script)
    - Job summary for apply/destroy

  gcp job (same structure, runs in parallel with azure):
    - environment: gcp-${env}
    - working-directory: terraform/gcp/environments/${env}

GitHub Environments to configure (repo Settings → Environments):
  azure-dev   → no approval required
  azure-qa    → 1 required reviewer
  azure-uat   → 1 required reviewer
  azure-prod  → 2 required reviewers + 15-min wait timer
  gcp-dev     → no approval required
  gcp-qa      → 1 required reviewer
  gcp-uat     → 1 required reviewer
  gcp-prod    → 2 required reviewers + 15-min wait timer

Secrets (set once at repo level, or override per GitHub Environment):
  AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID, AZURE_RESOURCE_GROUP
  GCP_WORKLOAD_IDENTITY_PROVIDER, GCP_SERVICE_ACCOUNT, GCP_PROJECT_ID
  DISCORD_WEBHOOK_URL

State locking (explain in comments):
  Azure: azurerm backend acquires a blob lease automatically — no extra config needed
  GCP:   GCS backend uses object generation conditions — concurrent applies blocked

─────────────────────────────────────────────────────────────────────────────
File 2: terraform-schedule.yml
─────────────────────────────────────────────────────────────────────────────

Triggers:
  schedule cron "0 18 * * 0"  → Sunday 18:00 UTC  = destroy dev
  schedule cron "0 2  * * 6"  → Saturday 02:00 UTC = recreate dev
  workflow_dispatch → inputs: action (destroy|recreate), cloud (azure|gcp|both)

Design:
  setup job resolves action from day-of-week (scheduled) or input (dispatch)
  azure + gcp jobs run in parallel; both do destroy OR apply depending on action
  Discord notification on success/failure for each cloud

FOR BOTH FILES INCLUDE:
  - id-token: write permission (OIDC requirement)
  - azure/login@v2 for Azure OIDC
  - google-github-actions/auth@v2 for GCP OIDC
  - Terraform pinned to 1.5.7 via hashicorp/setup-terraform@v3
  - concurrency group keyed on environment to prevent parallel apply to same env
  - conftest OPA check against policy/terraform/{azure,gcp}.rego

OUTPUT: Both YAML files, complete and production-ready
```
