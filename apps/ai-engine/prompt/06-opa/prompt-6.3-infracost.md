# Prompt 6.3 - OPA: Cost Validation with Infracost Integration

```
Act as a FinOps-aware DevSecOps engineer.

CONTEXT:
- Terraform for Azure + GCP
- GitHub Actions pipeline
- KodeKloud: budget extremely tight (playground)
- Goal: fail PR if estimated infra cost exceeds threshold

TASK:
Generate complete cost validation setup:

### 1. Infracost Integration
- GitHub Actions step: run infracost breakdown --format json
- Output: cost JSON per resource
- Pass JSON as OPA input

### 2. OPA Cost Policy (policy/cost/cost_guard.rego)
package cost

- RULE: Deny if total monthly cost > $30 (playground safety)
- RULE: Warn if any single resource > $10/month
- RULE: Deny if AKS monthly estimate > $15 (B2s baseline)
- RULE: List top 3 most expensive resources in violation message
- RULE: Allow with warning if cost 20-30 USD (amber zone)

### 3. GitHub Actions Workflow Step
- Run infracost after terraform plan
- Generate JSON cost breakdown
- Run conftest against cost JSON
- Post cost table as PR comment (markdown table: Resource | Monthly Cost | Status)
- Fail PR if deny rule triggered

### 4. Cost Baseline File (data/cost_baseline.json)
- Expected monthly costs for dev environment
- Drift detection: warn if 20% above baseline

ALSO INCLUDE:
- Infracost config file (.infracost/config.yml)
- How to get free Infracost API key
- Cost optimisation tips specific to KodeKloud playground limits

OUTPUT: .rego files + GitHub Actions YAML steps + cost_baseline.json + infracost config
```
