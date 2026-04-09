# Prompt 2.1 - Terraform GCP: Modular Folder Structure + Variables

```
Act as a Senior Cloud Architect specialising in Terraform on GCP.

CONTEXT:
- KodeKloud GCP Playground limits:
  * Max 5 VMs, max 7 vCPUs total
  * Disk: max 50 GB per disk, 250 GB total
  * Networking: max 8 External IPs, max 3 VPN Tunnels
  * GKE: Autopilot and Enterprise tiers BLOCKED - use Standard
  * VM series: E2 and N2 only
  * Regions: US-based only
  * Default project only (cannot create new projects)
- Environments: dev and qa
- App: rentalAppLedger
- Backend storage already created in Phase 0 (bootstrap)

TASK:
Generate complete Terraform GCP modular folder structure:

1. Folder layout:
   terraform/
   |-- modules/
   |   |-- vpc/
   |   |-- subnet/
   |   |-- cloud_armor/
   |   |-- artifact_registry/
   |   |-- gke/
   |   |-- secret_manager/
   |   |-- storage_bucket/
   |-- environments/
   |   |-- dev/
   |   |-- qa/
   |-- backend.tf (GCS bucket state backend)

2. For each module:
   - main.tf (cheapest viable config)
   - variables.tf
   - outputs.tf

3. Root-level files:
   - provider.tf (google ~>5.x)
   - variables.tf
   - terraform.tfvars example for dev

CONSTRAINTS:
- GKE: Standard mode, e2-standard-2, 1 node (respect CPU quota)
- No Autopilot (blocked in KodeKloud)
- State backend: GCS bucket with versioning (already created)
- Do NOT create projects; use existing default project

NAMING: {env}-{region-short}-{resource} e.g. dev-use1-gke

OUTPUT: Full folder tree + all files with cost comments
```
