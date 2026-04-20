# ArgoCD GitOps — Helm-based Structure

This directory contains all ArgoCD configuration for the rental app platform.
It uses a Helm-based approach for environment-specific configuration, supporting
both Azure (AKS) and GCP (GKE).

## Directory layout

```
platform/gitops/argocd/
├── apps/                          # Raw ArgoCD Application manifests (bootstrap)
│   ├── app-dev.yaml
│   ├── app-qa.yaml
│   ├── appproject.yaml
│   ├── external-secrets-app.yaml
│   ├── istio-*.yaml               # Istio base, istiod, gateway, networking
│   ├── platform-project.yaml
│   └── prometheus-app.yaml
│
├── charts/                        # Helm chart for generating ArgoCD manifests
│   └── rental-app/
│       ├── Chart.yaml
│       ├── values.yaml            # Base defaults
│       └── templates/
│           ├── appproject.yaml
│           └── application.yaml
│
├── environments/                  # Per-environment value overrides
│   ├── dev/
│   │   ├── values.yaml            # Azure dev
│   │   └── values-gcp.yaml        # GCP dev
│   └── qa/
│       ├── values.yaml            # Azure qa
│       └── values-gcp.yaml        # GCP qa
│
├── values/                        # Shared Helm values
│   ├── argocd-install.yaml        # ArgoCD server install values
│   └── postgresql-values.yaml     # In-cluster PostgreSQL (helm-pg mode)
│
├── helm/postgresql/               # Legacy PostgreSQL values
│   └── values-dev.yaml
│
└── notifications/                 # ArgoCD notification config
    ├── argocd-notifications-cm.yaml
    ├── argocd-notifications-secret.yaml
    └── app-notification-annotations.yaml
```

## Environment → cluster mapping

| Environment | Cloud | Cluster | Namespace |
|-------------|-------|---------|-----------|
| dev | Azure | `dev-aks` | `rental-dev` |
| dev | GCP | `dev-gke` | `rental-dev` |
| qa | Azure | `qa-aks` | `rental-qa` |
| qa | GCP | `qa-gke` | `rental-qa` |

## Deployment

### Via GitHub Actions (recommended)
```
Actions → ArgoCD Bootstrap → install / azure / dev
```

### Manual Helm render + apply

```bash
# Azure dev
helm template rental-app platform/gitops/argocd/charts/rental-app \
  -f platform/gitops/argocd/charts/rental-app/values.yaml \
  -f platform/gitops/argocd/environments/dev/values.yaml \
  | kubectl apply -f -

# GCP dev
helm template rental-app platform/gitops/argocd/charts/rental-app \
  -f platform/gitops/argocd/charts/rental-app/values.yaml \
  -f platform/gitops/argocd/environments/dev/values-gcp.yaml \
  | kubectl apply -f -
```

### Install ArgoCD itself

```bash
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --values platform/gitops/argocd/values/argocd-install.yaml \
  --set server.service.type=LoadBalancer \
  --version 7.3.11
```

## Adding a new environment

1. Copy `environments/qa/values.yaml` → `environments/<env>/values.yaml`
2. Update `app.environment`, `app.namespace`, `app.manifestPath`
3. Add env to workflow `options` in `argocd-bootstrap.yml`
4. Create Kubernetes overlay: `platform/kubernetes/overlays/<env>/`

## Cloud-specific behaviour

| Setting | Azure | GCP |
|---------|-------|-----|
| `app.cloud` | `azure` | `gcp` |
| `app.registryServer` | `*.azurecr.io` (patched) | `*.pkg.dev/*` (patched) |
| Secret store | Azure Key Vault (ESO) | Secret Manager (ESO) |

`registryServer` is always patched at deploy time by the bootstrap script —
never hardcode a real registry URL in values files.

## RBAC

Defined in `values/argocd-install.yaml` under `configs.rbac`. The default
policy grants `platform-admins` group full access on both cloud clusters.
Add team mappings by extending `policy.csv`:
```yaml
configs:
  rbac:
    policy.csv: |
      g, your-github-team, role:admin
```
