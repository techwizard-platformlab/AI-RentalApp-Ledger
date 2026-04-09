# Cloud Resource Constraints (Quick Reference)

## Azure (dev environment)
- Regions: East US (`eastus`)
- VMs: Standard_D2s_v3 (system/appnode pools), Standard_B2s (qa/uat)
- AKS: Standard SKU, 1 node (dev) — destroy when not in use
- SQL: Basic tier, 5 DTUs, max 2 GB
- ACR: Basic SKU (persistent — keep running, cheap daily billing)
- Key Vault: Standard SKU, soft delete 7 days
- All resources in one resource group — delete group to nuke everything

## GCP (dev environment)
- Regions: US-based only
- VMs: e2-standard-2 (system + appnode pools)
- GKE: Standard mode, 1 node per pool — destroy when not in use
- Artifact Registry: persistent (cheap storage billing)
- Cloud NAT: destroy with GKE (charged per hour)

## Cost guardrails
- Weekly budget: 400 INR (~$5 USD) per cloud
- Deploy-destroy pattern: 3-4 hrs/day × 22 days = 88 hrs/month
- Run ONLY ONE cloud at a time to stay under budget
- OPA deny threshold: $22/month | warn: $15/month
- Azure-only at 88 hrs: ~$30/month (~2520 INR) ✓
- Both clouds simultaneously: over budget ✗
