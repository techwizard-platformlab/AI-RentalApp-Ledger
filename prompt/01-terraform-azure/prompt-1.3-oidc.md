# Prompt 1.3 - Terraform Azure: Service Principal + GitHub Actions OIDC

```
Act as a DevSecOps engineer expert in Azure IAM and GitHub Actions.

CONTEXT:
- Project: rentalAppLedger on Azure
- CI/CD: GitHub Actions
- Goal: Terraform pipeline authenticates to Azure without storing long-lived secrets
- IMPORTANT: Resource Group already exists; scope role assignments at RG level

TASK:
Generate Terraform code and instructions for:

1. Service Principal module (modules/service_principal/):
   - Create App Registration + Service Principal
   - Minimum permissions:
     * Contributor on resource group (not subscription)
     * AcrPull on ACR
     * Key Vault Secrets Officer on KeyVault
   - Output: client_id, tenant_id (NOT client_secret - use OIDC)

2. Federated Identity Credential for GitHub Actions OIDC:
   - Configure azuread_application_federated_identity_credential
   - Subject: repo:{github_org}/{repo_name}:environment:dev
   - No client secrets stored anywhere

3. GitHub Actions secrets list (what to set in repo settings):
   - AZURE_CLIENT_ID
   - AZURE_TENANT_ID
   - AZURE_SUBSCRIPTION_ID

4. Sample azure/login@v2 step using OIDC (no password)

5. Least-privilege IAM policy document (JSON) for reference

ALSO INCLUDE:
- azurerm provider block using OIDC (no hardcoded credentials)
- azuread provider block (~>2.x) required for federated identity credential
- How to rotate access (update federated credential subject or repo env)
- .gitignore entries that MUST be present for security

OUTPUT: Terraform files + inline security notes
```
