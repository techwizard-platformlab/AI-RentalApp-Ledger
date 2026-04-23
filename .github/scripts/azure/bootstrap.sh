#!/usr/bin/env bash
# .github/scripts/azure/bootstrap.sh
# Azure-specific bootstrap logic called by argocd-bootstrap.yml
#
# Required env vars (set by workflow):
#   ENV, ACTION, DB_MODE, ADDONS
#   PLATFORM_KV_NAME, AKS_NAME, LOCATION_SHORT
#   ARGOCD_GITHUB_PAT, GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_REF_NAME
#   DISCORD_WEBHOOK_URL, OPENAI_API_KEY, SMTP_PASSWORD (optional)
#   ARGOCD_VERSION, NAMESPACE_ARGOCD, NAMESPACE_APP
#   GITHUB_OUTPUT, GITHUB_ENV, GITHUB_STEP_SUMMARY

set -euo pipefail

ENV="${ENV:-dev}"
ACTION="${ACTION:-install}"
DB_MODE="${DB_MODE:-azure-pg}"
ADDONS="${ADDONS:-all}"
ARGOCD_VERSION="${ARGOCD_VERSION:-7.3.11}"
NAMESPACE_ARGOCD="${NAMESPACE_ARGOCD:-argocd}"
NAMESPACE_APP="${NAMESPACE_APP:-rental-${ENV}}"

# ── Helpers ───────────────────────────────────────────────────────────────────
env_rg() { echo "rental-app-${ENV}"; }

kv_name() {
  az keyvault list --resource-group "$(env_rg)" --query "[0].name" -o tsv
}

fetch_kv() {
  az keyvault secret show --vault-name "$1" --name "$2" --query value -o tsv
}

set_kv() {
  local kv="$1" name="$2" value="$3"
  [ -z "$value" ] && echo "Skipping $name — not set" && return 0
  echo "::add-mask::$value"
  az keyvault secret set --vault-name "$kv" --name "$name" --value "$value" --output none
  echo "Set $name in $kv"
}

# ── Platform secrets (ArgoCD PAT, Discord) ───────────────────────────────────
fetch_platform_secrets() {
  local plt_kv="${PLATFORM_KV_NAME:-}"
  [ -z "$plt_kv" ] && plt_kv=$(az keyvault list \
    --query "[?tags.role=='platform'].name | [0]" -o tsv 2>/dev/null || true)
  [ -z "$plt_kv" ] && echo "No platform KV found — skipping" && return 0

  local pat; pat=$(az keyvault secret show --vault-name "$plt_kv" \
    --name "argocd-github-pat" --query value -o tsv 2>/dev/null || true)
  [ -n "$pat" ] && echo "::add-mask::$pat" && echo "ARGOCD_GITHUB_PAT=$pat" >> "$GITHUB_ENV"

  local discord; discord=$(az keyvault secret show --vault-name "$plt_kv" \
    --name "discord-webhook-url" --query value -o tsv 2>/dev/null || true)
  [ -n "$discord" ] && echo "::add-mask::$discord" && echo "DISCORD_WEBHOOK_URL=$discord" >> "$GITHUB_ENV"
}

# ── AKS credentials ───────────────────────────────────────────────────────────
get_aks_credentials() {
  az aks get-credentials \
    --resource-group "$(env_rg)" \
    --name "${AKS_NAME:-${ENV}-aks}" \
    --overwrite-existing
  kubectl get nodes
}

# ── ACR login server ──────────────────────────────────────────────────────────
get_acr_server() {
  local kv; kv=$(kv_name)
  local server; server=$(az keyvault secret show --vault-name "$kv" \
    --name "acr-login-server" --query value -o tsv 2>/dev/null || \
    az acr list --resource-group "$(env_rg)" --query "[0].loginServer" -o tsv)
  echo "acr_login_server=$server" >> "$GITHUB_OUTPUT"
  echo "ACR: $server"
}

# ── Patch kustomize overlay ───────────────────────────────────────────────────
patch_kustomize_overlay() {
  local server; server=$(grep "^acr_login_server=" "$GITHUB_OUTPUT" | tail -1 | cut -d= -f2)
  local overlay="platform/kubernetes/overlays/${ENV}/kustomization.yaml"
  [ ! -f "$overlay" ] && echo "Overlay not found — skipping ACR patch" && return 0

  sed -i -E "s#(ACR_LOGIN_SERVER|[a-z0-9]+\.azurecr\.io)#${server}#g" "$overlay"
  git config user.email "argocd-bootstrap@github-actions"
  git config user.name "ArgoCD Bootstrap"
  git add "$overlay"
  git diff --cached --quiet && echo "No ACR change" && return 0
  git commit -m "ci: patch ACR server ${server} in ${ENV} overlay [skip ci]"
  git push "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "HEAD:${GITHUB_REF_NAME}"
}

# ── ACR imagePullSecret ───────────────────────────────────────────────────────
create_acr_pull_secret() {
  local server; server=$(grep "^acr_login_server=" "$GITHUB_OUTPUT" | tail -1 | cut -d= -f2)
  local name; name=$(echo "$server" | cut -d'.' -f1)
  kubectl create namespace "$NAMESPACE_APP" --dry-run=client -o yaml | kubectl apply -f -
  az acr update --name "$name" --admin-enabled true --output none
  local pass; pass=$(az acr credential show --name "$name" --query "passwords[0].value" -o tsv)
  kubectl create secret docker-registry acr-pull-secret \
    --namespace "$NAMESPACE_APP" \
    --docker-server="$server" --docker-username="$name" --docker-password="$pass" \
    --dry-run=client -o yaml | kubectl apply -f -
}

# ── DB: helm-pg ───────────────────────────────────────────────────────────────
deploy_helm_pg() {
  local kv; kv=$(kv_name)
  local db_pass; db_pass=$(openssl rand -base64 32 | tr -d '/+=')
  local dj_key; dj_key=$(openssl rand -base64 64 | tr -d '/+=')
  az keyvault secret set --vault-name "$kv" --name "db-password"       --value "$db_pass" --output none
  az keyvault secret set --vault-name "$kv" --name "django-secret-key" --value "$dj_key"  --output none

  local vals="platform/gitops/argocd/install/postgresql-values.yaml"
  [ ! -f "$vals" ] && vals="platform/gitops/argocd/environments/dev/postgresql-values.yaml"
  helm repo add bitnami https://charts.bitnami.com/bitnami && helm repo update
  helm upgrade --install postgresql bitnami/postgresql \
    --namespace "$NAMESPACE_APP" --values "$vals" \
    --set auth.password="$db_pass" --set auth.postgresPassword="$db_pass" \
    --timeout 5m --wait
  { echo "db_host=postgresql.${NAMESPACE_APP}.svc.cluster.local"
    echo "db_name=rental_db"; echo "db_user=rentaladmin"; echo "db_port=5432"; } >> "$GITHUB_OUTPUT"
}

# ── DB: azure-pg / azure-sql ──────────────────────────────────────────────────
fetch_db_secrets_from_kv() {
  local kv; kv=$(kv_name)
  { echo "db_host=$(fetch_kv "$kv" db-host)"
    echo "db_name=$(fetch_kv "$kv" db-name)"
    echo "db_user=$(fetch_kv "$kv" db-user)"
    echo "db_port=$(fetch_kv "$kv" db-port)"; } >> "$GITHUB_OUTPUT"
}

# ── Seed app secrets ──────────────────────────────────────────────────────────
seed_app_secrets() {
  local kv; kv=$(kv_name)
  set_kv "$kv" "discord-webhook-url" "${DISCORD_WEBHOOK_URL:-}"
  set_kv "$kv" "openai-api-key"      "${OPENAI_API_KEY:-}"
  set_kv "$kv" "smtp-password"       "${SMTP_PASSWORD:-}"
}

# ── ESO ───────────────────────────────────────────────────────────────────────
install_eso() {
  local client_id; client_id=$(az identity show \
    --name "${ENV}-${LOCATION_SHORT:-eus2}-eso-identity" \
    --resource-group "$(env_rg)" --query clientId -o tsv)
  sed "s/REPLACE_AFTER_TERRAFORM_APPLY/${client_id}/" \
    platform/gitops/argocd/platform-addons/external-secrets-app.yaml | kubectl apply -f -
  kubectl rollout status deployment/external-secrets -n external-secrets --timeout=5m || true
}

# ── ClusterSecretStore ────────────────────────────────────────────────────────
apply_cluster_secret_store() {
  local f="platform/kubernetes/overlays/${ENV}/secrets/cluster-secret-store.yaml"
  [ -f "$f" ] && kubectl apply -f "$f" && sleep 10 || echo "No ClusterSecretStore — skipping"
}

# ── ArgoCD install/upgrade ────────────────────────────────────────────────────
add_argo_helm_repo() { helm repo add argo https://argoproj.github.io/argo-helm && helm repo update; }

_argocd_values() {
  local v="platform/gitops/argocd/install/argocd-install.yaml"
  [ -f "$v" ] || v="platform/gitops/argocd/install/install-values.yaml"
  echo "$v"
}

install_argocd() {
  kubectl create namespace "$NAMESPACE_ARGOCD" --dry-run=client -o yaml | kubectl apply -f -
  helm upgrade --install argocd argo/argo-cd \
    --namespace "$NAMESPACE_ARGOCD" --version "$ARGOCD_VERSION" \
    --values "$(_argocd_values)" \
    --set server.service.type=LoadBalancer --set server.ingress.enabled=false \
    --timeout 10m --wait
}

upgrade_argocd() {
  helm upgrade argocd argo/argo-cd \
    --namespace "$NAMESPACE_ARGOCD" --version "$ARGOCD_VERSION" \
    --values "$(_argocd_values)" \
    --set server.service.type=LoadBalancer --set server.ingress.enabled=false \
    --timeout 10m --wait
}

wait_for_argocd_ip() {
  kubectl rollout status deployment/argocd-server -n "$NAMESPACE_ARGOCD" --timeout=8m
  local ip=""
  for i in $(seq 1 36); do
    ip=$(kubectl get svc argocd-server -n "$NAMESPACE_ARGOCD" \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    [ -z "$ip" ] && ip=$(kubectl get svc argocd-server -n "$NAMESPACE_ARGOCD" \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    [ -n "$ip" ] && echo "argocd_ip=$ip" >> "$GITHUB_OUTPUT" && echo "ArgoCD: $ip" && return 0
    echo "Attempt $i/36 — waiting 10s..."; sleep 10
  done
  echo "::error::ArgoCD LB IP not available after 6 minutes"; exit 1
}

register_gitops_repo() {
  kubectl create secret generic argocd-repo-credentials \
    --namespace "$NAMESPACE_ARGOCD" \
    --from-literal=type=git \
    --from-literal=url="${GITOPS_REPO_URL:-https://github.com/${GITHUB_REPOSITORY}}" \
    --from-literal=username=git \
    --from-literal=password="${ARGOCD_GITHUB_PAT:-}" \
    --dry-run=client -o json \
  | jq '.metadata.labels["argocd.argoproj.io/secret-type"] = "repository"' \
  | kubectl apply -f -
}

apply_apps() {
  local server; server=$(grep "^acr_login_server=" "$GITHUB_OUTPUT" 2>/dev/null | tail -1 | cut -d= -f2 || true)
  kubectl apply -f platform/gitops/argocd/projects/app-project.yaml
  if [ -n "$server" ]; then
    sed "s|ACR_LOGIN_SERVER|${server}|g" "platform/gitops/argocd/environments/${ENV}/app-azure.yaml" | kubectl apply -f -
  else
    kubectl apply -f "platform/gitops/argocd/environments/${ENV}/app-azure.yaml"
  fi
}

# ── Grafana / Alertmanager ────────────────────────────────────────────────────
create_grafana_secret() {
  local kv; kv=$(kv_name)
  local pass; pass=$(az keyvault secret show --vault-name "$kv" \
    --name "grafana-admin-password" --query value -o tsv 2>/dev/null || true)
  if [ -z "$pass" ]; then
    pass=$(openssl rand -base64 24 | tr -d '/+=')
    az keyvault secret set --vault-name "$kv" --name "grafana-admin-password" --value "$pass" --output none
  fi
  kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic grafana-admin-secret --namespace monitoring \
    --from-literal=admin-user=admin --from-literal=admin-password="$pass" \
    --dry-run=client -o yaml | kubectl apply -f -
}

create_alertmanager_secret() {
  local kv; kv=$(kv_name)
  local discord; discord="${DISCORD_WEBHOOK_URL:-$(az keyvault secret show \
    --vault-name "$kv" --name "discord-webhook-url" --query value -o tsv 2>/dev/null || true)}"
  local smtp_pass; smtp_pass="${SMTP_PASSWORD:-$(az keyvault secret show \
    --vault-name "$kv" --name "smtp-password" --query value -o tsv 2>/dev/null || true)}"
  local cfg="platform/observability/monitoring/alertmanager-config.yaml"
  [ -f "$cfg" ] || { echo "Alertmanager config not found — skipping"; return 0; }
  kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic alertmanager-config-secret --namespace monitoring \
    --from-literal=alertmanager.yaml="$(sed \
      -e "s|\${DISCORD_WEBHOOK_URL}|${discord}|g" \
      -e "s|\${ALERT_EMAIL_TO}|${ALERT_EMAIL:-alerts@example.com}|g" \
      -e "s|\${SMTP_HOST}|${SMTP_HOST:-smtp.example.com}|g" \
      -e "s|\${SMTP_USERNAME}|${SMTP_USERNAME:-}|g" \
      -e "s|\${SMTP_PASSWORD}|${smtp_pass}|g" "$cfg")" \
    --dry-run=client -o yaml | kubectl apply -f -
}

# ── Istio ─────────────────────────────────────────────────────────────────────
deploy_istio() {
  kubectl apply -f platform/gitops/argocd/projects/platform-project.yaml
  kubectl apply -f platform/gitops/argocd/platform-addons/istio-base-app.yaml
  for i in $(seq 1 24); do
    local c; c=$(kubectl get crd 2>/dev/null | grep -c "istio.io" || true)
    [ "$c" -ge 10 ] && break; sleep 15
  done
  kubectl apply -f platform/gitops/argocd/platform-addons/istiod-app.yaml
  kubectl rollout status deployment/istiod -n istio-system --timeout=5m || true
  kubectl apply -f platform/gitops/argocd/platform-addons/istio-gateway-app.yaml
  local ip=""
  for i in $(seq 1 36); do
    ip=$(kubectl get svc istio-ingressgateway -n istio-system \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    [ -n "$ip" ] && echo "istio_ip=$ip" >> "$GITHUB_OUTPUT" && break; sleep 10
  done
  kubectl apply -f platform/gitops/argocd/platform-addons/istio-networking-app.yaml
  echo "::notice::Istio deployed — gateway: ${ip:-pending}"
}

deploy_prometheus() {
  kubectl apply -f platform/gitops/argocd/platform-addons/prometheus-app.yaml
  echo "::notice::kube-prometheus-stack submitted to ArgoCD"
}

# ── Uninstall actions ─────────────────────────────────────────────────────────
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
echo "==> Azure bootstrap: ENV=$ENV ACTION=$ACTION DB_MODE=$DB_MODE"
fetch_platform_secrets
get_aks_credentials

case "$ACTION" in
  install|upgrade)
    [ "$ACTION" = "install" ] && get_acr_server && patch_kustomize_overlay && create_acr_pull_secret
    case "$DB_MODE" in
      helm-pg)                  deploy_helm_pg ;;
      azure-pg|azure-sql|"")    fetch_db_secrets_from_kv ;;
      *) echo "::error::Unknown db_mode: $DB_MODE"; exit 1 ;;
    esac
    seed_app_secrets; install_eso; apply_cluster_secret_store; add_argo_helm_repo
    [ "$ACTION" = "install" ] && install_argocd || upgrade_argocd
    wait_for_argocd_ip; register_gitops_repo; apply_apps ;;
  apply-apps)
    get_acr_server; apply_apps ;;
  apply-addons)
    kubectl apply -f platform/gitops/argocd/projects/platform-project.yaml
    case "$ADDONS" in all|prometheus) create_grafana_secret; create_alertmanager_secret ;; esac
    case "$ADDONS" in all|istio)      deploy_istio ;; esac
    case "$ADDONS" in all|prometheus) deploy_prometheus ;; esac ;;
  uninstall-apps)   uninstall_apps ;;
  uninstall-addons) uninstall_addons ;;
  uninstall)        uninstall_argocd ;;
  *) echo "::error::Unknown action: $ACTION"; exit 1 ;;
esac

echo "==> Azure bootstrap complete: $ACTION/$ENV"
