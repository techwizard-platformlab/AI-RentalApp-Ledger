# Prompt 6.2 - OPA: Kubernetes Admission Policies (Gatekeeper)

```
Act as a Senior Platform Engineer specialising in OPA Gatekeeper.

CONTEXT:
- Kubernetes: AKS + GKE
- Namespaces: rental-dev, rental-qa
- OPA Gatekeeper: installed as admission controller
- Note: Kyverno handles most K8s policies (Phase 5), OPA handles complex logic

TASK:
Generate OPA Gatekeeper ConstraintTemplates for complex policies Kyverno can't handle:

### Template 1: Require Signed Images
- ConstraintTemplate: RequireSignedImage
- Check: image has valid cosign signature
- Implementation: use Rego to validate image digest signature annotation
- Constraint: apply to rental-dev, rental-qa namespaces

### Template 2: Enforce Naming Convention
- ConstraintTemplate: EnforceNamingConvention
- Deployment names must match: {service}-{env}-{version} pattern
- Service names must match: svc-{name} pattern
- Configurable regex via constraint parameters

### Template 3: Cost Guard - Replica Limit
- ConstraintTemplate: ReplicaLimit
- Max replicas per Deployment: configurable per namespace
- rental-dev: max 2 replicas
- rental-qa: max 3 replicas
- Block scale-up beyond limit

ALSO INCLUDE:
- Gatekeeper install (Helm, minimal for dev)
- How Gatekeeper + Kyverno coexist (admission webhook ordering)
- AuditInterval: 60s (dev - reduce noise)

OUTPUT: ConstraintTemplate + Constraint YAML files per policy
```
