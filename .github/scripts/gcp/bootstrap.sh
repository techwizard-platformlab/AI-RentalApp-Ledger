#!/usr/bin/env bash
# .github/scripts/gcp/bootstrap.sh
# GCP-specific ArgoCD bootstrap logic
# Called by .github/workflows/argocd-bootstrap.yml
#
# Required env vars (set by workflow):
#   ACTION          install | upgrade | apply-apps | apply-addons | uninstall-apps | uninstall-addons | uninstall
#   ENVIRONMENT     dev | qa | uat | prod
#   DB_MODE         gcp-pg | cloudsql | helm-pg
#   ADDONS          all | istio | prometheus
#   GCP_PROJECT_ID
#   GCP_REGION
#   GCP_CLUSTER_NAME (optional — defaults to rentalapp-<env>-gke)
#   ARGOCD_GITHUB_PAT
#   GITHUB_ORG
#   GITHUB_REPO

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
ENV="${ENVIRONMENT:-dev}"
NAMESPACE="rental-${ENV}"
ARGOCD_NS="argocd"
CLUSTER_NAME="${GCP_CLUSTER_NAME:-rentalapp-${ENV}-gke}"
REGION="${GCP_REGION:-us-central1}"
PROJECT="${GCP_PROJECT_ID}"
SM_PREFIX="rentalapp-${ENV}"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo "[gcp/bootstrap] $*"; }
die()  { echo "[gcp/bootstrap] ERROR: $*" >&2; exit 1; }

fetch_sm_secret() {
  local name="$1"
  gcloud secrets versions access latest \
    --secret="${name}" \
    --project="${PROJECT}" 2>/dev/null || true
}

get_gke_credentials() {
  log "Fetching GKE credentials for ${CLUSTER_NAME} in ${REGION}…"
  gcloud container clusters get-credentials "${CLUSTER_NAME}" \
    --region "${REGION}" \
    --project "${PROJECT}"
}

get_ar_server() {
  echo "${REGION}-docker.pkg.dev"
}

patch_kustomize_overlay() {
  local overlay_dir="platform/kubernetes/overlays/${ENV}"
  local ar_server
  ar_server=$(get_ar_server)
  local ar_repo="${ar_server}/${PROJECT}/rentalapp"
  log "Patching kustomize overlay image references → ${ar_repo}"
  if [[ -f "${overlay_dir}/kustomization.yaml" ]]; then
    sed -i "s|newName:.*|newName: ${ar_repo}/rental-api|" "${overlay_dir}/kustomization.yaml" || true
  fi
}

create_ar_pull_secret() {
  log "Creating Artifact Registry pull secret in namespace ${NAMESPACE}…"
  kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

  local ar_server
  ar_server=$(get_ar_server)

  # Use Workload Identity — pods pull via node SA; create a helper secret for non-WI workloads
  ACCESS_TOKEN=$(gcloud auth print-access-token)
  kubectl create secret docker-registry ar-pull-secret \
    --namespace="${NAMESPACE}" \
    --docker-server="${ar_server}" \
    --docker-username=oauth2accesstoken \
    --docker-password="${ACCESS_TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f -
}

deploy_helm_pg() {
  log "Deploying PostgreSQL via Helm (fallback mode)…"
  helm repo add bitnami https://charts.bitnami.com/bitnami --force-update
  helm repo update

  local pg_pass
  pg_pass=$(fetch_sm_secret "${SM_PREFIX}-db-password")
  [[ -z "$pg_pass" ]] && pg_pass="postgres"

  helm upgrade --install postgresql bitnami/postgresql \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --set auth.postgresPassword="${pg_pass}" \
    --set auth.database="rentalapp" \
    --set persistence.size=5Gi \
    --wait --timeout=300s
}

fetch_db_secrets_from_sm() {
  log "Fetching DB connection secrets from Secret Manager…"
  DB_HOST=$(fetch_sm_secret "${SM_PREFIX}-db-host")
  DB_PORT=$(fetch_sm_secret "${SM_PREFIX}-db-port")
  DB_NAME=$(fetch_sm_secret "${SM_PREFIX}-db-name")
  DB_USER=$(fetch_sm_secret "${SM_PREFIX}-db-user")
  DB_PASS=$(fetch_sm_secret "${SM_PREFIX}-db-password")
  export DB_HOST DB_PORT DB_NAME DB_USER DB_PASS
}

seed_app_secrets() {
  log "Seeding application secrets into Kubernetes namespace ${NAMESPACE}…"
  fetch_db_secrets_from_sm

  local discord_webhook
  discord_webhook=$(fetch_sm_secret "rentalapp-discord-webhook")

  kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

  kubectl create secret generic rentalapp-db-secret \
    --namespace="${NAMESPACE}" \
    --from-literal=DB_HOST="${DB_HOST}" \
    --from-literal=DB_PORT="${DB_PORT:-5432}" \
    --from-literal=DB_NAME="${DB_NAME:-rentalapp}" \
    --from-literal=DB_USER="${DB_USER:-postgres}" \
    --from-literal=DB_PASSWORD="${DB_PASS}" \
    --dry-run=client -o yaml | kubectl apply -f -

  if [[ -n "${discord_webhook}" ]]; then
    kubectl create secret generic discord-secret \
      --namespace="${NAMESPACE}" \
      --from-literal=webhook-url="${discord_webhook}" \
      --dry-run=client -o yaml | kubectl apply -f -
  fi
}

install_eso() {
  log "Installing External Secrets Operator…"
  helm repo add external-secrets https://charts.external-secrets.io --force-update
  helm repo update
  helm upgrade --install external-secrets external-secrets/external-secrets \
    --namespace external-secrets \
    --create-namespace \
    --set installCRDs=true \
    --wait --timeout=180s
}

apply_cluster_secret_store() {
  log "Applying ClusterSecretStore for GCP Secret Manager…"
  cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: gcp-secret-manager
spec:
  provider:
    gcpsm:
      projectID: ${PROJECT}
EOF
}

install_argocd() {
  log "Installing ArgoCD via Helm…"
  helm repo add argo https://argoproj.github.io/argo-helm --force-update
  helm repo update
  kubectl create namespace "${ARGOCD_NS}" --dry-run=client -o yaml | kubectl apply -f -
  helm upgrade --install argocd argo/argo-cd \
    --namespace "${ARGOCD_NS}" \
    --values platform/gitops/argocd/values/argocd-install.yaml \
    --wait --timeout=300s
}

upgrade_argocd() {
  log "Upgrading ArgoCD…"
  helm repo add argo https://argoproj.github.io/argo-helm --force-update
  helm repo update
  helm upgrade argocd argo/argo-cd \
    --namespace "${ARGOCD_NS}" \
    --values platform/gitops/argocd/values/argocd-install.yaml \
    --wait --timeout=300s
}

wait_for_argocd_ip() {
  log "Waiting for ArgoCD server external IP (GCP Load Balancer)…"
  local retries=30
  local ip=""
  for ((i=1; i<=retries; i++)); do
    ip=$(kubectl get svc argocd-server -n "${ARGOCD_NS}" \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    [[ -n "$ip" ]] && break
    log "  Waiting… (${i}/${retries})"
    sleep 15
  done
  if [[ -z "$ip" ]]; then
    log "WARN: No external IP assigned after ${retries} attempts. Using port-forward."
    ip="localhost"
  fi
  echo "$ip"
}

register_gitops_repo() {
  local pat="${ARGOCD_GITHUB_PAT:-}"
  local org="${GITHUB_ORG:-}"
  local repo="${GITHUB_REPO:-}"
  [[ -z "$pat" || -z "$org" || -z "$repo" ]] && { log "WARN: Missing ARGOCD_GITHUB_PAT/GITHUB_ORG/GITHUB_REPO — skipping repo registration"; return; }

  log "Registering GitOps repo https://github.com/${org}/${repo} with ArgoCD…"
  argocd repo add "https://github.com/${org}/${repo}" \
    --username git \
    --password "${pat}" \
    --upsert 2>/dev/null || true
}

apply_apps() {
  log "Applying ArgoCD AppProject + Applications for ${ENV} on GCP…"

  local values_file="platform/gitops/argocd/environments/${ENV}/values-gcp.yaml"
  [[ ! -f "$values_file" ]] && values_file="platform/gitops/argocd/environments/${ENV}/values.yaml"

  helm template rentalapp-"${ENV}" \
    platform/gitops/argocd/charts/rental-app \
    --values "${values_file}" \
    --set cloud=gcp \
    | kubectl apply -n "${ARGOCD_NS}" -f -
}

create_grafana_secret() {
  log "Creating Grafana admin secret…"
  local grafana_pass
  grafana_pass=$(fetch_sm_secret "${SM_PREFIX}-grafana-password")
  [[ -z "$grafana_pass" ]] && grafana_pass="prom-operator"

  kubectl create secret generic kube-prometheus-stack-grafana \
    --namespace monitoring \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="${grafana_pass}" \
    --dry-run=client -o yaml | kubectl apply -f -
}

create_alertmanager_secret() {
  log "Creating Alertmanager Discord secret…"
  local discord_webhook
  discord_webhook=$(fetch_sm_secret "rentalapp-discord-webhook")
  [[ -z "$discord_webhook" ]] && return

  kubectl create secret generic alertmanager-discord-secret \
    --namespace monitoring \
    --from-literal=webhook-url="${discord_webhook}" \
    --dry-run=client -o yaml | kubectl apply -f -
}

deploy_istio() {
  log "Deploying Istio via ArgoCD Helm chart (platform-addons)…"
  local addons_values="platform/gitops/argocd/environments/${ENV}/addons-values.yaml"

  helm template platform-addons \
    platform/gitops/argocd/charts/platform-addons \
    --values "${addons_values}" \
    --set cloud=gcp \
    --set addons="${ADDONS:-all}" \
    | kubectl apply -n "${ARGOCD_NS}" -f -
}

deploy_prometheus() {
  log "Deploying Prometheus stack via ArgoCD (included in platform-addons chart)…"
  log "  → Grafana and Alertmanager secrets must be seeded first."
  create_grafana_secret
  create_alertmanager_secret
  deploy_istio  # shared chart deploys both Istio + Prometheus
}

uninstall_apps() {
  log "Uninstalling ArgoCD applications for ${ENV}…"
  local values_file="platform/gitops/argocd/environments/${ENV}/values-gcp.yaml"
  [[ ! -f "$values_file" ]] && values_file="platform/gitops/argocd/environments/${ENV}/values.yaml"

  helm template rentalapp-"${ENV}" \
    platform/gitops/argocd/charts/rental-app \
    --values "${values_file}" \
    --set cloud=gcp \
    | kubectl delete -n "${ARGOCD_NS}" -f - --ignore-not-found
}

uninstall_addons() {
  log "Uninstalling platform add-ons (Istio + Prometheus) for ${ENV}…"
  local addons_values="platform/gitops/argocd/environments/${ENV}/addons-values.yaml"

  helm template platform-addons \
    platform/gitops/argocd/charts/platform-addons \
    --values "${addons_values}" \
    --set cloud=gcp \
    | kubectl delete -n "${ARGOCD_NS}" -f - --ignore-not-found
}

uninstall_argocd() {
  log "Uninstalling ArgoCD from cluster…"
  helm uninstall argocd --namespace "${ARGOCD_NS}" || true
  kubectl delete namespace "${ARGOCD_NS}" --ignore-not-found
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
main() {
  get_gke_credentials

  case "${ACTION}" in
    install)
      install_eso
      apply_cluster_secret_store
      seed_app_secrets
      create_ar_pull_secret
      patch_kustomize_overlay
      install_argocd
      wait_for_argocd_ip
      register_gitops_repo
      ;;
    upgrade)
      upgrade_argocd
      ;;
    apply-apps)
      [[ "${DB_MODE}" == "helm-pg" ]] && deploy_helm_pg
      [[ "${DB_MODE}" == "gcp-pg" ]] && fetch_db_secrets_from_sm
      apply_apps
      ;;
    apply-addons)
      case "${ADDONS:-all}" in
        istio)      deploy_istio ;;
        prometheus) deploy_prometheus ;;
        all)        deploy_istio ;;
      esac
      ;;
    uninstall-apps)
      uninstall_apps
      ;;
    uninstall-addons)
      uninstall_addons
      ;;
    uninstall)
      uninstall_apps
      uninstall_addons
      uninstall_argocd
      ;;
    *)
      die "Unknown ACTION: ${ACTION}. Valid: install|upgrade|apply-apps|apply-addons|uninstall-apps|uninstall-addons|uninstall"
      ;;
  esac

  log "Done — action=${ACTION} env=${ENV} cloud=gcp"
}

main "$@"
