# Prompt 4.2 - ArgoCD: GitOps Setup + Application YAMLs

```
Act as a Senior Platform Engineer specialising in ArgoCD and GitOps.

CONTEXT:
- Clusters: AKS (Azure) and GKE (GCP) - ArgoCD installed on each
- App repo: rentalAppLedger (separate from infra repo)
- K8s manifests: kustomize overlays (dev/qa) - from Prompt 4.1
- Goal: fully automated GitOps - push to main = auto-deploy to dev,
  push to qa branch = auto-deploy to qa (with approval gate)

TASK:
Generate complete ArgoCD setup:

### 1. ArgoCD Installation (Helm values)
- Minimal install (dev constraints, low resource)
- Ingress: enabled, hostname: argocd.{cluster-ip}.nip.io
- ResourceRequests: reduced for KodeKloud constraints
- HA: disabled (single replica, learning environment)
- Include ArgoCD Notifications installation (not part of core by default)

### 2. ArgoCD Application YAMLs

#### app-dev.yaml (Application CRD)
- Project: rental-ledger
- Source: github.com/{org}/rentalAppLedger, path: k8s/overlays/dev
- Destination: in-cluster, namespace: rental-dev
- Sync policy: automated (prune: true, selfHeal: true)
- Retry: 3 attempts, backoff: 5s

#### app-qa.yaml (Application CRD)
- Same as dev but overlays/qa
- Sync policy: manual (require human approval in ArgoCD UI)
- Notifications: Discord on sync success/failure

#### appproject.yaml (AppProject CRD)
- Name: rental-ledger
- Source repos: rentalAppLedger repo only
- Destinations: rental-dev, rental-qa namespaces only
- Cluster resources: limited to Deployment, Service, Ingress, HPA

### 3. Image Updater (ArgoCD Image Updater)
- Watch ACR/GCR for new image tags
- Auto-commit updated image tag to git on new push
- Annotation-based config on Application CRD
- Auth: use imagePullSecret from ACR/GCR

### 4. GitOps Repo Structure:
- gitops/
  |-- apps/
  |   |-- app-dev.yaml
  |   |-- app-qa.yaml
  |   |-- appproject.yaml
  |-- argocd/
  |   |-- install-values.yaml
  |-- README.md

### 5. ArgoCD Notification Config (basic):
- Discord webhook on: Sync Success, Sync Failed, App Health Degraded

OUTPUT: All YAML files + ArgoCD install command + README for GitOps repo
```
