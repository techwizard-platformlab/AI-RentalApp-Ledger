# GitOps Repository — rentalAppLedger

## Structure

```
gitops/
├── apps/
│   ├── appproject.yaml          # AppProject CRD — scopes allowed repos/namespaces
│   ├── app-dev.yaml             # Application CRD — auto-sync to rental-dev
│   ├── app-qa.yaml              # Application CRD — manual sync to rental-qa
│   └── notification-config.yaml # ArgoCD Notifications Discord config
└── argocd/
    └── install-values.yaml      # Helm values for ArgoCD install
```

## Bootstrap ArgoCD

```bash
# 1. Add Argo Helm repo
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# 2. Install ArgoCD (minimal, single-replica)
helm install argocd argo/argo-cd \
  -n argocd --create-namespace \
  -f gitops/argocd/install-values.yaml

# 3. Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# 4. Apply AppProject + Applications
kubectl apply -f gitops/apps/appproject.yaml
kubectl apply -f gitops/apps/app-dev.yaml
kubectl apply -f gitops/apps/app-qa.yaml
kubectl apply -f gitops/apps/notification-config.yaml

# 5. Set Discord webhook secret
kubectl create secret generic argocd-notifications-secret \
  -n argocd \
  --from-literal=discord-webhook-url="<your-discord-webhook-url>"
```

## Image Updater

ArgoCD Image Updater watches ACR/GCR for new image tags and commits updated
image references back to the git repository (GitOps write-back pattern).

```bash
# Install Image Updater
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml

# Configure ACR credentials (imagePullSecret)
kubectl create secret docker-registry acr-pull-secret \
  -n argocd \
  --docker-server={ACR_NAME}.azurecr.io \
  --docker-username=<sp-client-id> \
  --docker-password=<sp-client-secret>
```

## GitHub Environments / Branch Protection (recommended)

- Require PR before merging to `main`
- Required status checks: `lint-and-test`, `security-scan`, `conftest`
- At least 1 required reviewer for `qa` branch merges

## Passing image tag to ArgoCD

The CI pipeline (`ci-build.yml`) builds and pushes images tagged with the git SHA.
ArgoCD Image Updater detects the new tag, updates `k8s/overlays/dev/kustomization.yaml`
via a git commit, which triggers ArgoCD to sync the new image to the cluster.
