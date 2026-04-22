# Prompt 1.1 - Terraform Azure: Modular Folder Structure + Variables

```
Act as a Senior Cloud Architect specialising in Terraform on Azure.

CONTEXT:
- I am a DevOps engineer learning multi-cloud on KodeKloud Playground.
- KodeKloud Azure limits: West/East/Central/South Central US regions only,
  Standard SKUs for AKS, no Premium Disks, max 128 GB disk, Basic/Standard SQL tiers.
- IMPORTANT: Cannot create Resource Groups - must use existing RG.
- Environments: dev and qa (future: staging, prod - design for extensibility).
- App: rentalAppLedger (microservice, separate repo).
- Cost goal: minimum viable, free-tier or lowest-cost SKUs.
- Backend storage already created in Phase 0 (bootstrap).

TASK:
Generate a complete Terraform modular folder structure for Azure with:

1. Folder layout:
    |-- environments/
    |   |-- dev/             # AKS + VNet + DB (env layer)
    |   |-- qa/
    |-- modules/             # aks, vnet, postgresql, keyvault, acr, ...
    |-- backend.tf (Azure Storage state backend)

2. For each module, provide:
   - main.tf (resource block, lowest-cost SKU)
   - variables.tf (with types and defaults)
   - outputs.tf

3. Root-level files:
   - variables.tf
   - terraform.tfvars example for dev
   - backend.tf using Azure Storage Account for state locking

4. Naming convention: {env}-{region-short}-{resource} e.g. dev-eus-aks

CONSTRAINTS:
- Use azurerm provider ~> 3.x
- Regions: eastus, westus, centralus, southcentralus only
- AKS: Standard SKU, 1 node pool, Standard_B2s VM size
- No Premium storage
- All resources tagged: env, project=rentalAppLedger, owner=ramprasath
- Resource Group is passed as input (do NOT create RG)

OUTPUT FORMAT:
- Show full folder tree first
- Then each file with filename as header
- Add inline comments explaining cost-sensitive choices
```
