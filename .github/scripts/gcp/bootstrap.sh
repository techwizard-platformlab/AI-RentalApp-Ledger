#!/usr/bin/env bash
# .github/scripts/gcp/bootstrap.sh
# GCP-specific bootstrap logic called by argocd-bootstrap.yml
#
# Required env vars (set by workflow):
#   ENV, ACTION, DB_MODE, ADDONS
#   GCP_PROJECT_ID, GCP_REGION, GKE_CLUSTER_NAME, GKE_CLUSTER_ZONE
#   ARGOCD_GITHUB_PAT, GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_REF_NAME
#   DISCORD_WEBHOOK_URL (optional)
#   OPENAI_API_KEY, SMTP_PASSWORD (optional — seeded into Secret Manager)
#   ARGOCD_VERSION, NAMESPACE_ARGOCD, NAMESPACE_APP
#   GITHUB_OUTPUT, GITHUB_ENV, GITHUB_STEP_SUMMARY

set -euo pipefail

ENV="${ENV:-dev}"
ACTION="${ACTION:-install}"
DB_MODE="${DB_MODE:-gcp-pg}"
ADDONS="${ADDONS:-all}"
ARGOCD_VERSION="${ARGOCD_VERSION:-7.3.11}"
NAMESPACE_ARGOCD="${NAMESPACE_ARGOCD:-argocd}"
NAMESPACE_APP="${NAMESPACE_APP:-rental-${ENV}}"
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
GCP_REGION="${GCP_REGION:-us-central1}"
GKE_CLUSTER_NAME="${GKE_CLUSTER_NAME:-${ENV}-gke}"
GKE_CLUSTER_ZONE="${GKE_CLUSTER_ZONE:-${GCP_REGION}-a}"

# ── Helpers ───────────────────────────────────────────────────────────────────
sm_secret() {
  local name="$1"
  gcloud secrets versions access latest \
    --secret="$name" \
    --project="$GCP_PROJECT_ID" 2>/dev/null || true
}

set_sm_secret() {
  local name="$1" value="$2"
  if [ -z "$value" ]; then
    echo "Skipping $name — value not set"
    return 0
  fi
  echo "::add-mask::$value"
  # Create secret if it doesn't exist
  gcloud secrets describe "$name" --project="$GCP_PROJECT_ID" &>/dev/null || \
    gcloud secrets create "$name" \
      --project="$GCP_PROJECT_ID" \
      --replication-policy="automatic"
  echo -n "$value" | gcloud secrets versions add "$name" \
    --project="$GCP_PROJECT_ID" \
    --data-file=-
  echo "Set $name in Secret Manager"
}

# ── Platform secrets from Secret Manager ────────────────────────────────────
fetch_platform_secrets() {
  local pat
  pat=$(sm_secret "argocd-github-pat")
  if [ -n "$pat" ]; then
    echo "::add-mask::$pat"
    echo "ARGOCD_GITHUB_PAT=$pat" >> "$GITHUB_ENV"
  fi

  local discord
  discord=$(sm_secret "discord-webhook-url")
  if [ -n "$discord" ]; then
    echo "::add-mask::$discord"
    echo "DISCORD_WEBHOOK_URL=$discord" >> "$GITHUB_ENV"
  fi
}

# ── Get GKE credentials ───────────────────────────────────────────────────────
get_gke_credentials() {
  gcloud container clusters get-credentials "$GKE_CLUSTER_NAME" \
    --zone "$GKE_CLUSTER_ZONE" \
    --project "$GCP_PROJECT_ID"
  kubectl get nodes
}

# ── Artifact Registry image URL ───────────────────────────────────────────────
get_registry_url() {
  local registry="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/rental-${ENV}"
  echo "registry_url=$registry" >> "$GITHUB_OUTPUT"
  echo "Artifact Registry: $registry"
}

# ── Patch kustomize overlay ───────────────────────────────────────────────────
patch_kustomize_overlay() {
  local registry_url
  registry_url=$(grep "registry_url" "$GITHUB_OUTPUT" | tail -1 | cut -d= -f2)

  sed -i -E "s#(REGISTRY_URL|[a-z0-9-]+\.pkg\.dev/[^/]+/[^/]+)#${registry_url}#g" \
    "platform/kubernetes/overlays/${ENV}/kustomization.yaml" 2>/dev/null || \
    echo "Kustomize overlay not found — skipping ACR patch"

  git config user.email "argocd-bootstrap@github-actions"
  git config user.name "ArgoCD Bootstrap"
  git add "platform/kubernetes/overlays/${ENV}/kustomization.yaml" 2>/dev/null || true
  git diff --cached --quiet && echo "No registry change needed" && return 0
  git commit -m "ci: patch GCP registry ${registry_url} in ${ENV} overlay [skip ci]"
  git push \
    "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" \
    "HEAD:${GITHUB_REF_NAME}"
}

# ── GCR / Artifact Registry imagePullSecret ──────────────────────────────────
create_registry_pull_secret() {
  local registry_url
  registry_url=$(grep "registry_url" "$GITHUB_OUTPUT" | tail -1 | cut -d= -f2)

  kubectl create namespace "$NAMESPACE_APP" --dry-run=client -o yaml | kubectl apply -f -

  # Use workload identity — no password-based pull secret needed for GKE
  # Just annotate the default service account
  kubectl annotate serviceaccount default \
    --namespace "$NAMESPACE_APP" \
    "iam.gke.io/gcp-service-account=${GCP_GSA_EMAIL:-}" \
    --overwrite 2>/dev/null || \
    echo "Workload identity annotation skipped — GCP_GSA_EMAIL not set"
}

# ── DB: gcp-pg / cloudsql ────────────────────────────────────────────────────
deploy_cloudsql() {
  local db_password django_secret_key
  db_password=$(openssl rand -base64 32 | tr -d '/+=')
  django_secret_key=$(openssl rand -base64 64 | tr -d '/+=')

  set_sm_secret "db-password"       "$db_password"
  set_sm_secret "django-secret-key" "$django_secret_key"

  local sql_instance
  sql_instance=$(gcloud sql instances list \
    --project="$GCP_PROJECT_ID" \
    --filter="name~${ENV}" \
    --format="value(name)" 2>/dev/null | head -1 || true)

  if [ -n "$sql_instance" ]; then
    local db_host
    db_host=$(gcloud sql instances describe "$sql_instance" \
      --project="$GCP_PROJECT_ID" \
      --format="value(ipAddresses[0].ipAddress)" 2>/dev/null || echo "")

    {
      echo "db_host=${db_host}"
      echo "db_name=rental_db"
      echo "db_user=rentaladmin"
      echo "db_port=5432"
    } >> "$GITHUB_OUTPUT"
  else
    echo "::warning::No Cloud SQL instance found matching ${ENV} — DB outputs not set"
  fi
}

fetch_db_secrets_from_sm() {
  local db_host db_name db_user db_port
  db_host=$(sm_secret "db-host")
  db_name=$(sm_secret "db-name")
  db_user=$(sm_secret "db-user")
  db_port=$(sm_secret "db-port")

  {
    echo "db_host=${db_host}"
    echo "db_name=${db_name}"
    echo "db_user=${db_user}"
    echo "db_port=${db_port}"
  } >> "$GITHUB_OUTPUT"
}

# ── Seed app secrets ─────────────────────────────────────────────────────────
seed_app_secrets() {
  set_sm_secret "discord-webhook-url" "${DISCORD_WEBHOOK_URL:-}"
  set_sm_secret "openai-api-key"      "${OPENAI_API_KEY:-}"
  set_sm_secret "smtp-password"       "${SMTP_PASSWORD:-}"
}

# ── ESO install for GCP Secret Manager ──────────────────────────────────────
install_eso() {
  local eso_sa="${ESO_GSA_EMAIL:-}"
  local eso_app="platform/gitops/argocd/apps/external-secrets-app.yaml"

  if [ -f "$eso_app" ]; then
    if [ -n "$eso_sa" ]; then
      sed "s/REPLACE_AFTER_TERRAFORM_APPLY/${eso_sa}/" "$eso_app" | kubectl apply -f -
    else
      kubectl apply -f "$eso_app"
    fi
    kubectl rollout status deployment/external-secrets -n external-secrets --timeout=5m || true
  else
    echo "ESO app manifest not found — skipping"
  fi
}

# ── ClusterSecretStore for GCP Secret Manager ────────────────────────────────
apply_cluster_secret_store() {
  local store_file="platform/kubernetes/overlays/${ENV}/secrets/cluster-secret-store-gcp.yaml"
  local fallback="platform/kubernetes/overlays/${ENV}/secrets/cluster-secret-store.yaml"

  local target_file=""
  [ -f "$store_file" ] && target_file="$store_file"
  [ -z "$target_file" ] && [ -f "$fallback" ] && target_file="$fallback"

  if [ -n "$target_file" ]; then
    kubectl apply -f "$target_file"
    sleep 10
    kubectl get clustersecretstore -o name 2>/dev/null || true
  else
    echo "No ClusterSecretStore manifest found — skipping"
  fi
}

# ── ArgoCD helpers (same pattern as Azure) ───────────────────────────────────
add_argo_helm_repo() {
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo update
}

install_argocd() {
  kubectl create namespace "$NAMESPACE_ARGOCD" --dry-run=client -o yaml | kubectl apply -f -
  local values="platform/gitops/argocd/values/argocd-install.yaml"
  [ -f "$values" ] || values="platform/gitops/argocd/argocd/install-values.yaml"

  helm upgrade --install argocd argo/argo-cd \
    --namespace "$NAMESPACE_ARGOCD" \
    --version "$ARGOCD_VERSION" \
    --values "$values" \
    --set server.service.type=LoadBalancer \
    --set server.ingress.enabled=false \
    --timeout 10m \
    --wait
}

upgrade_argocd() {
  local values="platform/gitops/argocd/values/argocd-install.yaml"
  [ -f "$values" ] || values="platform/gitops/argocd/argocd/install-values.yaml"

  helm upgrade argocd argo/argo-cd \
    --namespace "$NAMESPACE_ARGOCD" \
    --version "$ARGOCD_VERSION" \
    --values "$values" \
    --set server.service.type=LoadBalancer \
    --set server.ingress.enabled=false \
    --timeout 10m \
    --wait
}

wait_for_argocd_ip() {
  kubectl rollout status deployment/argocd-server -n "$NAMESPACE_ARGOCD" --timeout=8m
  local ip=""
  for i in $(seq 1 36); do
    ip=$(kubectl get svc argocd-server -n "$NAMESPACE_ARGOCD" \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    [ -z "$ip" ] && ip=$(kubectl get svc argocd-server -n "$NAMESPACE_ARGOCD" \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    if [ -n "$ip" ]; then
      echo "argocd_ip=$ip" >> "$GITHUB_OUTPUT"
      echo "ArgoCD endpoint: $ip"
      return 0
    fi
    sleep 10
  done
  echo "::error::ArgoCD LoadBalancer did not get an IP after 6 minutes"
  exit 1
}

register_gitops_repo() {
  local repo_url="${GITOPS_REPO_URL:-https://github.com/${GITHUB_REPOSITORY}}"
  kubectl create secret generic argocd-repo-credentials \
    --namespace "$NAMESPACE_ARGOCD" \
    --from-literal=type=git \
    --from-literal=url="$repo_url" \
    --from-literal=username=git \
    --from-literal=password="${ARGOCD_GITHUB_PAT:-}" \
    --dry-run=client -o json \
  | jq '.metadata.labels["argocd.argoproj.io/secret-type"] = "repository"' \
  | kubectl apply -f -
}

apply_apps() {
  kubectl apply -f platform/gitops/argocd/apps/appproject.yaml
  kubectl apply -f "platform/gitops/argocd/apps/app-${ENV}.yaml"
}

# ── Grafana / Alertmanager ────────────────────────────────────────────────────
create_grafana_secret() {
  local pass
  pass=$(sm_secret "grafana-admin-password")
  if [ -z "$pass" ]; then
    pass=$(openssl rand -base64 24 | tr -d '/+=')
    set_sm_secret "grafana-admin-password" "$pass"
  fi
  kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic grafana-admin-secret \
    --namespace monitoring \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$pass" \
    --dry-run=client -o yaml | kubectl apply -f -
}

create_alertmanager_secret() {
  local discord_url smtp_pass alert_email smtp_host smtp_user
  discord_url="${DISCORD_WEBHOOK_URL:-$(sm_secret "discord-webhook-url")}"
  smtp_pass="${SMTP_PASSWORD:-$(sm_secret "smtp-password")}"
  alert_email="${ALERT_EMAIL:-alerts@example.com}"
  smtp_host="${SMTP_HOST:-smtp.example.com}"
  smtp_user="${SMTP_USERNAME:-$alert_email}"

  local config_file="platform/observability/monitoring/alertmanager-config.yaml"
  [ -f "$config_file" ] || { echo "Alertmanager config not found — skipping"; return 0; }

  kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
  local config
  config=$(sed \
    -e "s|\${DISCORD_WEBHOOK_URL}|${discord_url}|g" \
    -e "s|\${ALERT_EMAIL_TO}|${alert_email}|g" \
    -e "s|\${SMTP_HOST}|${smtp_host}|g" \
    -e "s|\${SMTP_USERNAME}|${smtp_user}|g" \
    -e "s|\${SMTP_PASSWORD}|${smtp_pass}|g" \
    "$config_file")

  kubectl create secret generic alertmanager-config-secret \
    --namespace monitoring \
    --from-literal=alertmanager.yaml="$config" \
    --dry-run=client -o yaml | kubectl apply -f -
}

deploy_istio() {
  kubectl apply -f platform/gitops/argocd/apps/platform-project.yaml
  kubectl apply -f platform/gitops/argocd/apps/istio-base-app.yaml
  for i in $(seq 1 24); do
    local count
    count=$(kubectl get crd 2>/dev/null | grep -c "istio.io" || true)
    [ "$count" -ge 10 ] && echo "Istio CRDs ready" && break
    sleep 15
  done
  kubectl apply -f platform/gitops/argocd/apps/istiod-app.yaml
  kubectl rollout status deployment/istiod -n istio-system --timeout=5m || true
  kubectl apply -f platform/gitops/argocd/apps/istio-gateway-app.yaml
  local istio_ip=""
  for i in $(seq 1 36); do
    istio_ip=$(kubectl get svc istio-ingressgateway -n istio-system \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    [ -n "$istio_ip" ] && echo "istio_ip=$istio_ip" >> "$GITHUB_OUTPUT" && break
    sleep 10
  done
  kubectl apply -f platform/gitops/argocd/apps/istio-networking-app.yaml
  echo "::notice::Istio deployed (GKE) — gateway IP: ${istio_ip:-pending}"
}

deploy_prometheus() {
  kubectl apply -f platform/gitops/argocd/apps/prometheus-app.yaml
  echo "::notice::kube-prometheus-stack submitted to ArgoCD (GKE)"
}

uninstall_apps() {
  kubectl delete application "rental-ledger-${ENV}" -n "$NAMESPACE_ARGOCD" --ignore-not-found
  kubectl delete appproject "rental-ledger" -n "$NAMESPACE_ARGOCD" --ignore-not-found
  echo "Apps removed."
}

uninstall_addons() {
  for app in istio-networking istio-gateway istiod istio-base kube-prometheus-stack; do
    kubectl delete application "$app" -n "$NAMESPACE_ARGOCD" --ignore-not-found || true
  done
  kubectl delete namespace istio-system monitoring --ignore-not-found || true
  echo "Add-ons removed."
}

uninstall_argocd() {
  helm uninstall argocd --namespace "$NAMESPACE_ARGOCD" || true
  kubectl delete namespace "$NAMESPACE_ARGOCD" --ignore-not-found
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
echo "==> GCP bootstrap: ENV=$ENV ACTION=$ACTION DB_MODE=$DB_MODE ADDONS=$ADDONS"

fetch_platform_secrets
get_gke_credentials

case "$ACTION" in

  install|upgrade)
    [ "$ACTION" = "install" ] && get_registry_url && patch_kustomize_overlay && create_registry_pull_secret

    case "$DB_MODE" in
      gcp-pg|cloudsql)  deploy_cloudsql ;;
      helm-pg)          echo "::warning::helm-pg on GCP: deploy PostgreSQL Helm chart manually or use Cloud SQL" ;;
      *)
        echo "::error::Unknown db_mode for GCP: $DB_MODE"
        exit 1
        ;;
    esac

    seed_app_secrets
    install_eso
    apply_cluster_secret_store
    add_argo_helm_repo

    [ "$ACTION" = "install" ] && install_argocd || upgrade_argocd
    wait_for_argocd_ip
    register_gitops_repo
    apply_apps
    ;;

  apply-apps)
    get_registry_url
    apply_apps
    ;;

  apply-addons)
    kubectl apply -f platform/gitops/argocd/apps/platform-project.yaml
    case "$ADDONS" in
      all|prometheus) create_grafana_secret; create_alertmanager_secret ;;
    esac
    case "$ADDONS" in
      all|istio)      deploy_istio ;;
    esac
    case "$ADDONS" in
      all|prometheus) deploy_prometheus ;;
    esac
    ;;

  uninstall-apps)   uninstall_apps ;;
  uninstall-addons) uninstall_addons ;;
  uninstall)        uninstall_argocd ;;

  *)
    echo "::error::Unknown action: $ACTION"
    exit 1
    ;;
esac

echo "==> GCP bootstrap complete: $ACTION/$ENV"
