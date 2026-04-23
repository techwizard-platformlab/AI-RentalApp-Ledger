# GitOps — ArgoCD Configuration

Helm-based ArgoCD configuration. Application and AppProject manifests are generated via Helm templates, not stored as static YAML — enabling multi-cloud and multi-environment support without duplication.

## Structure

```
platform/gitops/argocd/
├── charts/
│   ├── rental-app/               # Helm chart: ArgoCD Application + AppProject
│   │   ├── Chart.yaml
│   │   ├── values.yaml           # Base defaults
│   │   └── templates/
│   │       ├── appproject.yaml   # Helm template for AppProject CRD
│   │       └── application.yaml  # Helm template for Application CRD
│   └── platform-addons/          # Helm chart: Istio + Prometheus ArgoCD Applications
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── istio-base.yaml     # ArgoCD Application: Istio CRDs (wave 0)
│           ├── istiod.yaml         # ArgoCD Application: istiod (wave 1)
│           ├── istio-gateway.yaml  # ArgoCD Application: ingress gateway (wave 2)
│           └── prometheus.yaml     # ArgoCD Application: kube-prometheus-stack
├── environments/
│   ├── dev/
│   │   ├── values.yaml           # Azure dev overrides
│   │   ├── values-gcp.yaml       # GCP dev overrides
│   │   └── addons-values.yaml    # Istio + Prometheus dev settings
│   └── qa/
│       ├── values.yaml
│       ├── values-gcp.yaml
│       └── addons-values.yaml
└── values/
    ├── argocd-install.yaml       # ArgoCD Helm install values
    └── postgresql-values.yaml    # Bitnami PostgreSQL fallback values (helm-pg mode)
```

## Deploy via GitHub Actions (recommended)

```
GitHub → Actions → argocd-bootstrap.yml
  cloud: azure | gcp
  environment: dev | qa | uat | prod
  action: install          ← full install: ArgoCD + ESO + app secrets
  action: apply-apps       ← generate + apply AppProject + Application
  action: apply-addons     ← deploy Istio + Prometheus via ArgoCD
  action: uninstall-apps   ← remove Application + AppProject only
  action: uninstall-addons ← remove Istio + Prometheus Applications
  action: uninstall        ← remove everything including ArgoCD namespace
```

## Manual bootstrap

```bash
# 1. Install ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm install argocd argo/argo-cd \
  -n argocd --create-namespace \
  -f platform/gitops/argocd/install/argocd-install.yaml

# 2. Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# 3. Generate + apply AppProject + Application (Azure dev)
helm template rentalapp-dev platform/gitops/argocd/charts/rental-app \
  --values platform/gitops/argocd/environments/dev/values-azure.yaml \
  | kubectl apply -n argocd -f -

# 4. Deploy platform add-ons
helm template platform-addons platform/gitops/argocd/charts/platform-addons \
  --values platform/gitops/argocd/environments/dev/addons-values.yaml \
  | kubectl apply -n argocd -f -
```

## Image tag flow

```
RentalApp-Build CI
  → docker build + push → ACR / Artifact Registry (tagged with git SHA)
       │
ArgoCD Image Updater (polls registry every 2m)
  → detects new semver tag
  → commits updated kustomization.yaml to platform repo
       │
ArgoCD auto-sync
  → applies diff to AKS / GKE
  → rolling update (readiness probe gates traffic)
       │
Discord notification → #deployments
```

## GitHub Environments

Create these in repo Settings → Environments:

| Environment | Required reviewers | Purpose |
|---|---|---|
| `shared` | yourself | Protects ACR + Key Vault (shared Terraform) |
| `terraform-destructive-approval` | yourself | Blocks apply/destroy with deletions |
| `dev` | none | OIDC subject scoping for dev runs |
| `qa` | yourself | Manual approval gate for QA deploys |
