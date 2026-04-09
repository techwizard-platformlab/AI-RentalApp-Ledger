# Prompt 4.3 - ArgoCD: Multi-Cluster Setup (Azure AKS + GCP GKE)

```
Act as a Senior Platform Engineer with multi-cluster ArgoCD experience.

CONTEXT:
- Hub cluster: AKS (Azure) - ArgoCD installed here
- Spoke cluster: GKE (GCP) - managed remotely by ArgoCD
- App: rentalAppLedger - deploy to BOTH clusters simultaneously
- Goal: single ArgoCD manages both Azure and GCP deployments

TASK:
Generate multi-cluster ArgoCD configuration:

### 1. Register GKE as Remote Cluster
- argocd cluster add command
- ServiceAccount + RBAC on GKE for ArgoCD
- Secret manifest for cluster credentials (kubeconfig reference)

### 2. ApplicationSet for Multi-Cluster Deploy
- Use cluster generator to deploy to both AKS + GKE
- Template: one Application per cluster, same git source
- Parameterise: registry URL (ACR for Azure, GCR for GCP) per cluster
- Labels: cloud=azure / cloud=gcp for filtering

### 3. Sync Wave Strategy
- Wave 0: namespaces
- Wave 1: configmaps + secrets
- Wave 2: deployments
- Wave 3: ingress + HPA

### 4. Rollback Strategy
- ArgoCD history: keep last 5 revisions
- How to rollback via CLI: argocd app rollback
- How to rollback via UI

### 5. Health Checks
- Custom health check for rentalAppLedger API (/health endpoint)
- Degraded state: pod restarts > 3 in 5 minutes

OUTPUT: ApplicationSet YAML + cluster registration commands + sync wave annotations
```
