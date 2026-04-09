# Prompt 1.2 - Terraform Azure: Core Resources (VNet, AKS, ACR, KeyVault)

```
Act as a Senior Cloud Architect. I am building Azure infra with Terraform for a learning
project called rentalAppLedger on KodeKloud Playground.

CONTEXT - KodeKloud Azure constraints:
- Allowed regions: West US, East US, Central US, South Central US
- AKS: Standard SKU only
- VM sizes: D2s_v3, B2s, B1s, DS1_v2
- No Premium Disks; max disk 128 GB
- SQL: Basic or Standard tier only
- IMPORTANT: Cannot create new Resource Groups

TASK:
Generate production-ready Terraform code for these Azure modules:

### Module 1: Virtual Network + Subnets
- VNet CIDR: 10.0.0.0/16
- Subnet: app-subnet 10.0.1.0/24
- Subnet: db-subnet  10.0.2.0/24
- Enable service endpoints: Microsoft.KeyVault, Microsoft.Storage

### Module 2: Network Security Group
- Allow: HTTP (80), HTTPS (443), Kubernetes API (6443) inbound
- Allow: all within VNet
- Deny: all other inbound

### Module 3: WAF Policy (Application Gateway WAF)
- Mode: Prevention
- OWASP ruleset 3.2
- Custom rule: block known bad IPs (placeholder list)

### Module 4: ACR (Azure Container Registry)
- SKU: Basic (cheapest for learning)
- Admin enabled: false
- Geo-replication: disabled (cost saving)

### Module 5: AKS Cluster
- Kubernetes version: variable with default "1.27" (use latest supported)
- Node pool: 1 node, Standard_B2s
- Network plugin: azure
- Enable RBAC
- Attach to ACR (acrPull role)
- Output: kubeconfig, cluster_name, resource_group

### Module 6: Key Vault
- SKU: standard
- Soft delete: enabled (7 days for dev)
- Purge protection: disabled (dev/qa only)
- Access policy for AKS managed identity

### Module 7: Storage Account
- SKU: Standard_LRS (cheapest)
- Kind: StorageV2
- Enable HTTPS only: true (security baseline)
- Enable blob versioning: false (dev cost saving)
- Container: tfstate (for Terraform backend)

FOR EACH MODULE OUTPUT:
- main.tf with full resource blocks
- variables.tf with all inputs (including resource_group_name)
- outputs.tf with all useful outputs
- Comment every SKU/tier choice with cost reason

USE: azurerm provider ~>3.x, Terraform ~>1.5
```
