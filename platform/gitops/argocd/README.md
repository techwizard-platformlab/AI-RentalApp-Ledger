# GitOps — ArgoCD Configuration

## Structure

```
platform/gitops/argocd/
├── apps/
│   ├── appproject.yaml              # AppProject — scopes allowed repos/namespaces
│   ├── app-dev.yaml                 # Application CRD — auto-sync to rental-dev
│   ├── app-qa.yaml                  # Application CRD — manual sync to rental-qa
│   ├── applicationset-multicluster.yaml  # Multi-cluster ApplicationSet (AKS + GKE)
│   ├── health-check-config.yaml     # Custom health check rules
│   └── notification-config.yaml     # ArgoCD Notifications — Discord triggers
├── argocd/
│   └── install-values.yaml          # Helm values for ArgoCD install
├── helm/
│   └── postgresql/
│       └── values-dev.yaml          # Fallback in-cluster PostgreSQL (if not using Azure PG)
└── notifications/
    ├── argocd-notifications-cm.yaml # Notification templates + triggers ConfigMap
    ├── argocd-notifications-secret.yaml  # Discord webhook secret template
    └── app-notification-annotations.yaml # Per-app notification annotations
```

## Bootstrap via GitHub Actions (recommended)

```
GitHub → Actions → argocd-bootstrap.yml
  environment: dev
  action: install        ← installs ArgoCD via Helm
  action: apply-apps     ← creates AppProject + Application CRDs
```

## Manual bootstrap

```bash
# 1. Add Argo Helm repo
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update

# 2. Install ArgoCD
helm install argocd argo/argo-cd \
  -n argocd --create-namespace \
  -f platform/gitops/argocd/argocd/install-values.yaml

# 3. Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# 4. Apply AppProject + Applications
kubectl apply -f platform/gitops/argocd/apps/appproject.yaml
kubectl apply -f platform/gitops/argocd/apps/app-dev.yaml
kubectl apply -f platform/gitops/argocd/apps/app-qa.yaml

# 5. Set Discord webhook secret
kubectl create secret generic argocd-notifications-secret \
  -n argocd \
  --from-literal=discord-webhook-url="<your-discord-webhook-url>"

# 6. Apply notification config
kubectl apply -f platform/gitops/argocd/notifications/argocd-notifications-cm.yaml
```

## Image Updater

ArgoCD Image Updater polls ACR for new image tags and commits updated
image references back to `platform/kubernetes/overlays/dev/` (GitOps write-back).

```bash
# Install Image Updater
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml

# Configure ACR credentials via Managed Identity (no client secret needed)
# The AKS node pool identity is assigned AcrPull by the bootstrap script.
kubectl create secret docker-registry acr-pull-secret \
  -n argocd \
  --docker-server=${ACR_NAME}.azurecr.io \
  --docker-username=00000000-0000-0000-0000-000000000000 \
  --docker-password=$(az acr login --name ${ACR_NAME} --expose-token --query accessToken -o tsv)
```

## Image tag flow

```
RentalApp-Build CI
  → docker build + push → ACR (tagged with git SHA)
       │
ArgoCD Image Updater (polls ACR every 2m)
  → detects new tag
  → commits updated kustomization.yaml to AI-RentalApp-Ledger
       │
ArgoCD auto-sync
  → applies diff to AKS
  → rolling update (readiness probe gates traffic)
       │
Discord notification → #deployments
```

## GitHub Environments (recommended)

Create these in repo Settings → Environments:

| Environment | Required reviewers | Purpose |
|---|---|---|
| `shared` | yourself | Protects ACR + Key Vault (shared Terraform) |
| `terraform-destructive-approval` | yourself | Blocks apply/destroy with deletions |
| `dev` | none | OIDC subject scoping for dev runs |
| `qa` | yourself | Manual approval gate for QA deploys |
