# Prompt 3.3 - GitHub Actions: OPA/Conftest Policy Validation in Pipeline

```
Act as a Senior DevSecOps Engineer specialising in OPA and Conftest.

CONTEXT:
- Terraform code for Azure + GCP
- GitHub Actions pipeline
- Goal: enforce policies BEFORE terraform apply (shift-left)

TASK:
Generate OPA policies + GitHub Actions integration for:

### Policy Set 1: Terraform Plan Validation
File: policy/terraform/azure.rego
- Deny AKS with vm_size not in approved list (B2s, D2s_v3)
- Deny any resource outside allowed regions (eastus, westus, centralus, southcentralus)
- Deny storage account without HTTPS-only enabled
- Deny Key Vault without soft_delete_retention_days >= 7
- Deny Public IPs on VMs/Load Balancers
- Deny wide-open NSG rules (0.0.0.0/0 or *)
- Enforce infrastructure_encryption_enabled on storage accounts

File: policy/terraform/gcp.rego
- Deny GKE with node count > 3 (KodeKloud quota)
- Deny GKE Autopilot (not available in playground)
- Deny resources outside US regions
- Deny storage bucket without versioning

### Policy Set 2: Cost Validation
File: policy/cost/cost_limits.rego
- Warn if estimated monthly cost > $50 (use infracost JSON input)
- Deny if estimated monthly cost > $100
- Output: cost breakdown per resource

### Policy Set 3: PR Merge Validation
File: policy/pr/pr_checks.rego
- Deny merge if: terraform fmt not run (detect unformatted files)
- Deny merge if: no CHANGELOG entry for infra changes
- Warn if: no corresponding QA environment plan exists

### GitHub Actions Integration:
- Step to run conftest against terraform plan JSON
- Step to run infracost + pass JSON to OPA
- How to fail PR on policy violation
- How to post policy results as PR comment
- Explain: warn rules are non-blocking and must be surfaced in PR comment

FILE STRUCTURE:
policy/
|-- terraform/
|   |-- azure.rego
|   |-- gcp.rego
|-- cost/
|   |-- cost_limits.rego
|-- pr/
|   |-- pr_checks.rego
|-- data/
    |-- approved_skus.json

OUTPUT: All .rego files + GitHub Actions YAML steps + data files
```
