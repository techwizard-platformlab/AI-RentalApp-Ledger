# KodeKloud Playground Constraints (Quick Reference)

```
## Azure (use in every Azure prompt)
- Regions: West US, East US, Central US, South Central US ONLY
- VMs: Standard_D2s_v3, Standard_B2s, Standard_B1s, Standard_DS1_v2
- AKS: Standard SKU only
- Disks: max 128 GB, NO Premium
- SQL: Basic or Standard tier only
- Cosmos DB: max 4000 RU/s
- Cannot create Resource Groups (use existing)
- Session: 1 hour/day limit

## GCP (use in every GCP prompt)
- Regions: US-based only
- VMs: E2 and N2 series ONLY
- Max VMs: 5 | Max vCPUs: 7
- Disk: max 50 GB per disk, 250 GB total
- GKE: Standard mode ONLY (Autopilot/Enterprise BLOCKED)
- Networking: max 8 External IPs, max 3 VPN Tunnels
- Only default project (cannot create new projects)
- Session: 1 hour/day limit
```
