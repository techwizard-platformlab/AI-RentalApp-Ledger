# Kyverno — Security Policies for rentalAppLedger

## Install (minimal resources for dev)

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

helm install kyverno kyverno/kyverno \
  -n kyverno --create-namespace \
  --set replicaCount=1 \
  --set resources.requests.cpu=100m \
  --set resources.requests.memory=256Mi \
  --set resources.limits.cpu=500m \
  --set resources.limits.memory=512Mi
```

## Apply Policies

```bash
kubectl apply -f kyverno/policies/
kubectl apply -f kyverno/exceptions/
```

## Policy Summary

| Policy | Kind | Action | Scope |
|--------|------|--------|-------|
| `disallow-privileged` | ClusterPolicy | Enforce | All (except kube-system) |
| `require-resource-limits` | ClusterPolicy | Enforce | rental-dev, rental-qa |
| `restrict-registries` | ClusterPolicy | Enforce (qa) / Audit (dev) | rental-dev, rental-qa |
| `require-deployment-labels` | Policy | Enforce | rental-dev |
| `disallow-latest-tag` | ClusterPolicy | Enforce (qa) / Audit (dev) | rental-dev, rental-qa |
| `generate-networkpolicy` | ClusterPolicy | Generate | rental-dev, rental-qa |
| `pod-security-baseline` | ClusterPolicy | Enforce | rental-dev, rental-qa |

## Check Policy Reports

```bash
# Cluster-wide policy report
kubectl get clusterpolicyreport -o wide

# Namespace-scoped report
kubectl get policyreport -n rental-dev -o wide

# Detailed violations
kubectl describe policyreport -n rental-dev

# Check if a pod would be admitted (dry-run)
kubectl apply --dry-run=server -f k8s/base/api-gateway/deployment.yaml
```

## Exceptions

`kyverno/exceptions/argocd-exception.yaml` grants ArgoCD system pods exemptions
from registry restrictions, privilege checks, and latest-tag policy so ArgoCD
can manage the cluster without false positives.
