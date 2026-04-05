# Prompt 6.1 - OPA: Terraform Plan + Cloud Resource Policies

```
Act as a Senior DevSecOps engineer expert in OPA Rego and Conftest.

CONTEXT:
- Terraform for Azure + GCP
- KodeKloud constraints embedded as policy rules
- Goal: prevent playground quota violations AND enforce security baselines

TASK:
Write complete OPA/Conftest policies:

### Azure Policies (policy/azure/)

#### azure_resources.rego
package azure

- RULE: Deny AKS nodes > 2 (KodeKloud quota protection)
- RULE: Deny VM sizes not in [Standard_B2s, Standard_D2s_v3, Standard_B1s]
- RULE: Deny resources in non-US regions
- RULE: Deny storage accounts without https_traffic_only_enabled = true
- RULE: Deny Key Vault without soft_delete_retention_days
- RULE: Deny ACR with SKU = Premium (cost)
- RULE: Deny any resource missing required tags (env, project, owner)
- RULE: Warn if AKS node pool > 1 node in dev

#### azure_networking.rego
package azure

- RULE: Deny VNet CIDR outside 10.0.0.0/8 (private ranges only)
- RULE: Deny NSG with inbound allow-all rule (0.0.0.0/0 on all ports)
- RULE: Deny subnet without NSG association

### GCP Policies (policy/gcp/)

#### gcp_resources.rego
package gcp

- RULE: Deny GKE node count > 3 (KodeKloud CPU quota: 7 vCPUs)
- RULE: Deny GKE Autopilot (blocked in playground)
- RULE: Deny GKE node type not in [e2-standard-2, n2-standard-2]
- RULE: Deny Artifact Registry without cleanup policy
- RULE: Deny GCS bucket without versioning enabled
- RULE: Deny resources outside US regions
- RULE: Deny service account with primitive roles (owner/editor on project level)

### Shared Policies (policy/shared/)

#### security_baseline.rego
package shared

- RULE: Deny any resource tagged environment=prod (playground safety guard)
- RULE: Deny more than 3 public IP addresses across all resources
- RULE: Warn if no encryption at rest configured

FOR EACH RULE INCLUDE:
- deny message with clear explanation
- warn (not deny) for non-blocking issues
- Unit tests in *_test.rego files
- Example input JSON (terraform plan JSON format)

ALSO INCLUDE:
- conftest.toml configuration
- How to generate terraform plan JSON: terraform show -json tfplan > plan.json
- How to run: conftest test plan.json --policy policy/
- Explain: warn output is non-blocking and should be posted to PR comment

OUTPUT: All .rego + _test.rego files + conftest.toml + example plan.json snippets
```
