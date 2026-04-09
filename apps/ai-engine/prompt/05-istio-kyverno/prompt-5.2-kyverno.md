# Prompt 5.2 - Kyverno: Security Policies for rentalAppLedger

```
Act as a Senior Platform Engineer specialising in Kyverno policy management.

CONTEXT:
- Kubernetes: AKS + GKE
- Namespaces: rental-dev, rental-qa
- App: rentalAppLedger microservices
- Goal: enforce security baseline, image governance, resource discipline

TASK:
Generate production-ready Kyverno policies:

### Policy 1: Disallow Privileged Containers (ClusterPolicy)
- Block: privileged: true
- Block: allowPrivilegeEscalation: true
- Block: hostPID, hostIPC, hostNetwork
- Action: Enforce (block)
- Exceptions: kube-system namespace

### Policy 2: Enforce Resource Limits (ClusterPolicy)
- Require: all containers have cpu + memory limits AND requests
- Minimum: requests.cpu >= 50m, requests.memory >= 64Mi
- Maximum: limits.cpu <= 2, limits.memory <= 1Gi
- Action: Enforce
- Generate: default ResourceQuota if missing

### Policy 3: Restrict Image Registry (ClusterPolicy)
- Allow only:
  * {acr_name}.azurecr.io/* (Azure)
  * us-central1-docker.pkg.dev/{project}/* (GCP)
  * registry.k8s.io/* (official K8s images)
- Block: docker.io/*, quay.io/* (in production namespaces)
- Action: Enforce in rental-qa, Audit in rental-dev (use validationFailureActionOverrides)

### Policy 4: Require Labels (Policy - namespace scoped)
- All Deployments must have labels:
  * app, version, environment, project=rentalAppLedger
- Action: Enforce

### Policy 5: Disallow Latest Tag (ClusterPolicy)
- Block any image tag = latest or missing tag
- Require: image:sha256:... or image:1.2.3 format
- Action: Enforce in rental-qa, Audit in rental-dev

### Policy 6: Generate Default NetworkPolicy (ClusterPolicy)
- On namespace creation: auto-generate default-deny NetworkPolicy
- Allow: DNS (port 53)
- Label selector: auto-generate for known services

### Policy 7: Pod Security (replace deprecated PodSecurityPolicy)
- runAsNonRoot: true required
- readOnlyRootFilesystem: true required
- seccompProfile: RuntimeDefault

ALSO INCLUDE:
- PolicyException example (for ArgoCD system pods)
- How to check policy reports: kubectl get policyreport
- Kyverno install command (Helm, minimal resources for dev)

OUTPUT:
kyverno/
|-- policies/
|   |-- disallow-privileged.yaml
|   |-- require-resource-limits.yaml
|   |-- restrict-registries.yaml
|   |-- require-labels.yaml
|   |-- disallow-latest-tag.yaml
|   |-- generate-networkpolicy.yaml
|   |-- pod-security.yaml
|-- exceptions/
|   |-- argocd-exception.yaml
|-- README.md
```
