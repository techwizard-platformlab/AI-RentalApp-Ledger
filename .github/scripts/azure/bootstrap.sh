#!/usr/bin/env bash
# .github/scripts/azure/bootstrap.sh
# Azure-specific bootstrap logic called by argocd-bootstrap.yml
#
# Required env vars (set by workflow):
#   ENV, ACTION, DB_MODE, ADDONS
#   AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID
#   ARGOCD_GITHUB_PAT, GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_REF_NAME
#   DISCORD_WEBHOOK_URL (optional)
#   OPENAI_API_KEY, SMTP_PASSWORD (optional — seeded into KV)
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

# ── Helpers ──────────────────────────────────────────────────────────────────
env_rg() { echo "rental-app-${ENV}"; }           # e.g. rental-app-dev
env_rg_title() {                                  # e.g. Rental-App-Dev (for display)
  local e="${ENV^}"
  echo "rental-app-${e}"
}

kv_name() {
  az keyvault list \
    --resource-group "$(env_rg)" \
    --query "[0].name" -o tsv
}

fetch_kv() {
  local kv="$1" secret="$2"
  az keyvault secret show --vault-name "$kv" --name "$secret" --query value -o tsv
}

set_kv() {
  local kv="$1" name="$2" value="$3"
  if [ -n "$value" ]; then
    echo "::add-mask::$value"
    az keyvault secret set --vault-name "$kv" --name "$name" --value "$value" --output none
    echo "Set $name in $kv"
  else
    echo "Skipping $name — value not set"
  fi
}

# ── Platform Key Vault (shared — holds ArgoCD PAT, discord webhook) ───────────
fetch_platform_secrets() {
  local plt_kv="${PLATFORM_KV_NAME:-}"

  # Try env var first, then discover by tag
  if [ -z "$plt_kv" ]; then
    plt_kv=$(az keyvault list --query "[?tags.role=='platform'].name | [0]" -o tsv 2>/dev/null || true)
  fi

  if [ -z "$plt_kv" ]; then
    echo "PLATFORM_KV_NAME not set and no platform keyvault found via tag — skipping platform secrets"
    return 0
  fi

  local pat
  pat=$(az keyvault secret show --vault-name "$plt_kv" --name "argocd-github-pat" --query value -o tsv 2>/dev/null || true)
  if [ -n "$pat" ]; then
    echo "::add-mask::$pat"
    echo "ARGOCD_GITHUB_PAT=$pat" >> "$GITHUB_ENV"
  fi

  local discord
  discord=$(az keyvault secret show --vault-name "$plt_kv" --name "discord-webhook-url" --query value -o tsv 2>/dev/null || true)
  if [ -n "$discord" ]; then
    echo "::add-mask::$discord"
    echo "DISCORD_WEBHOOK_URL=$discord" >> "$GITHUB_ENV"
  fi
}

# ── Get AKS credentials ───────────────────────────────────────────────────────
get_aks_credentials() {
  local aks_name="${AKS_NAME:-${ENV}-aks}"
  az aks get-credentials \
    --resource-group "$(env_rg)" \
    --name "$aks_name" \
    --overwrite-existing
  kubectl get nodes
}

# ── ACR login server ─────────────────────────────────────────────────────────
get_acr_server() {
  local kv
  kv=$(kv_name)

  local server
  server=$(az keyvault secret show --vault-name "$kv" --name "acr-login-server" --query value -o tsv 2>/dev/null || \
    az acr list --resource-group "$(env_rg)" --query "[0].loginServer" -o tsv)

  echo "acr_login_server=$server" >> "$GITHUB_OUTPUT"
  echo "ACR login server: $server"
}

# ── Patch kustomize overlay ──────────────────────────────────────────────────
patch_kustomize_overlay() {
  local acr_server
  acr_server=$(grep "acr_login_server" "$GITHUB_OUTPUT" | tail -1 | cut -d= -f2)

  sed -i -E "s#(ACR_LOGIN_SERVER|[a-z0-9]+\.azurecr\.io)#${acr_server}#g" \
    "platform/kubernetes/overlays/${ENV}/kustomization.yaml"

  git config user.email "argocd-bootstrap@github-actions"
  git config user.name "ArgoCD Bootstrap"
  git add "platform/kubernetes/overlays/${ENV}/kustomization.yaml"
  git diff --cached --quiet && echo "No ACR change needed" && return 0
  git commit -m "ci: patch ACR server ${acr_server} in ${ENV} overlay [skip ci]"
  git push \
    "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" \
    "HEAD:${GITHUB_REF_NAME}"
}

# ── ACR imagePullSecret ──────────────────────────────────────────────────────
create_acr_pull_secret() {
  local acr_server
  acr_server=$(grep "acr_login_server" "$GITHUB_OUTPUT" | tail -1 | cut -d= -f2)
  local acr_name
  acr_name=$(echo "$acr_server" | cut -d'.' -f1)

  kubectl create namespace "$NAMESPACE_APP" --dry-run=client -o yaml | kubectl apply -f -

  az acr update --name "$acr_name" --admin-enabled true --output none
  local acr_password
  acr_password=$(az acr credential show --name "$acr_name" --query "passwords[0].value" -o tsv)

  kubectl create secret docker-registry acr-pull-secret \
    --namespace "$NAMESPACE_APP" \
    --docker-server="$acr_server" \
    --docker-username="$acr_name" \
    --docker-password="$acr_password" \
    --dry-run=client -o yaml | kubectl apply -f -
}

# ── DB: helm-pg ──────────────────────────────────────────────────────────────
deploy_helm_pg() {
  local kv
  kv=$(kv_name)

  local db_password django_secret_key
  db_password=$(openssl rand -base64 32 | tr -d '/+=')
  django_secret_key=$(openssl rand -base64 64 | tr -d '/+=')

  az keyvault secret set --vault-name "$kv" --name "db-password"       --value "$db_password"       --output none
  az keyvault secret set --vault-name "$kv" --name "django-secret-key" --value "$django_secret_key" --output none

  helm repo add bitnami https://charts.bitnami.com/bitnami
  helm repo update

  local helm_values="platform/gitops/argocd/helm/postgresql/values-${ENV}.yaml"
  [ -f "$helm_values" ] || helm_values="platform/gitops/argocd/helm/postgresql/values-dev.yaml"

  helm upgrade --install postgresql bitnami/postgresql \
    --namespace "$NAMESPACE_APP" \
    --values "$helm_values" \
    --set auth.password="$db_password" \
    --set auth.postgresPassword="$db_password" \
    --timeout 5m \
    --wait

  {
    echo "db_host=postgresql.${NAMESPACE_APP}.svc.cluster.local"
    echo "db_name=rental_db"
    echo "db_user=rentaladmin"
    echo "db_port=5432"
  } >> "$GITHUB_OUTPUT"
}

# ── DB: azure-pg / azure-sql ─────────────────────────────────────────────────
fetch_db_secrets_from_kv() {
  local kv
  kv=$(kv_name)

  fetch_kv_out() { fetch_kv "$kv" "$1"; }

  {
    echo "db_host=$(fetch_kv_out db-host)"
    echo "db_name=$(fetch_kv_out db-name)"
    echo "db_user=$(fetch_kv_out db-user)"
    echo "db_port=$(fetch_kv_out db-port)"
  } >> "$GITHUB_OUTPUT"
}

# ── Seed app secrets ─────────────────────────────────────────────────────────
seed_app_secrets() {
  local kv
  kv=$(kv_name)

  set_kv "$kv" "discord-webhook-url" "${DISCORD_WEBHOOK_URL:-}"
  set_kv "$kv" "openai-api-key"      "${OPENAI_API_KEY:-}"
  set_kv "$kv" "smtp-password"       "${SMTP_PASSWORD:-}"
}

# ── ESO install ──────────────────────────────────────────────────────────────
install_eso() {
  local location_short="${LOCATION_SHORT:-eus2}"
  local eso_client_id
  eso_client_id=$(az identity show \
    --name "${ENV}-${location_short}-eso-identity" \
    --resource-group "$(env_rg)" \
    --query clientId -o tsv)

  echo "ESO client ID: $eso_client_id"

  sed "s/REPLACE_AFTER_TERRAFORM_APPLY/${eso_client_id}/" \
    platform/gitops/argocd/apps/external-secrets-app.yaml \
    | kubectl apply -f -

  kubectl rollout status deployment/external-secrets -n external-secrets --timeout=5m || true
}

# ── ClusterSecretStore ───────────────────────────────────────────────────────
apply_cluster_secret_store() {
  local store_file="platform/kubernetes/overlays/${ENV}/secrets/cluster-secret-store.yaml"
  if [ -f "$store_file" ]; then
    kubectl apply -f "$store_file"
    sleep 10
    kubectl get clustersecretstore azure-keyvault \
      -o jsonpath='{.status.conditions[0].message}' 2>/dev/null || true
    echo ""
  else
    echo "ClusterSecretStore manifest not found at $store_file — skipping"
  fi
}

# ── ArgoCD: add Helm repo ────────────────────────────────────────────────────
add_argo_helm_repo() {
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo update
}

# ── ArgoCD: install ──────────────────────────────────────────────────────────
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

# ── ArgoCD: upgrade ──────────────────────────────────────────────────────────
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

# ── ArgoCD: wait for LB IP ───────────────────────────────────────────────────
wait_for_argocd_ip() {
  echo "Waiting for argocd-server deployment..."
  kubectl rollout status deployment/argocd-server -n "$NAMESPACE_ARGOCD" --timeout=8m

  echo "Waiting for LoadBalancer external IP..."
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
    echo "Attempt $i/36 — waiting 10s..."
    sleep 10
  done
  echo "::error::ArgoCD LoadBalancer did not get an IP after 6 minutes"
  exit 1
}

# ── Register GitOps repo ─────────────────────────────────────────────────────
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

# ── Apply AppProject + Application ───────────────────────────────────────────
apply_apps() {
  local acr_server
  acr_server=$(grep "acr_login_server" "$GITHUB_OUTPUT" 2>/dev/null | tail -1 | cut -d= -f2 || echo "")

  kubectl apply -f platform/gitops/argocd/apps/appproject.yaml

  if [ -n "$acr_server" ]; then
    sed "s|ACR_LOGIN_SERVER|${acr_server}|g" \
      "platform/gitops/argocd/apps/app-${ENV}.yaml" \
      | kubectl apply -f -
  else
    kubectl apply -f "platform/gitops/argocd/apps/app-${ENV}.yaml"
  fi
}

# ── Grafana admin secret ─────────────────────────────────────────────────────
create_grafana_secret() {
  local kv
  kv=$(kv_name)

  local pass
  pass=$(az keyvault secret show --vault-name "$kv" --name "grafana-admin-password" \
    --query value -o tsv 2>/dev/null || echo "")

  if [ -z "$pass" ]; then
    pass=$(openssl rand -base64 24 | tr -d '/+=')
    az keyvault secret set --vault-name "$kv" --name "grafana-admin-password" \
      --value "$pass" --output none
    echo "Generated new Grafana admin password"
  fi

  kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic grafana-admin-secret \
    --namespace monitoring \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$pass" \
    --dry-run=client -o yaml | kubectl apply -f -
}

# ── Alertmanager secret ──────────────────────────────────────────────────────
create_alertmanager_secret() {
  local kv discord_url smtp_pass alert_email smtp_host smtp_user
  kv=$(kv_name)

  discord_url="${DISCORD_WEBHOOK_URL:-$(az keyvault secret show --vault-name "$kv" --name "discord-webhook-url" --query value -o tsv 2>/dev/null || echo "")}"
  smtp_pass="${SMTP_PASSWORD:-$(az keyvault secret show --vault-name "$kv" --name "smtp-password" --query value -o tsv 2>/dev/null || echo "")}"
  alert_email="${ALERT_EMAIL:-alerts@example.com}"
  smtp_host="${SMTP_HOST:-smtp.example.com}"
  smtp_user="${SMTP_USERNAME:-$alert_email}"

  local config_file="platform/observability/monitoring/alertmanager-config.yaml"
  if [ ! -f "$config_file" ]; then
    echo "Alertmanager config file not found at $config_file — skipping"
    return 0
  fi

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

# ── Deploy Istio via ArgoCD ──────────────────────────────────────────────────
deploy_istio() {
  kubectl apply -f platform/gitops/argocd/apps/platform-project.yaml

  # Wave 0 — CRDs
  kubectl apply -f platform/gitops/argocd/apps/istio-base-app.yaml
  echo "Waiting for Istio CRDs..."
  for i in $(seq 1 24); do
    local count
    count=$(kubectl get crd 2>/dev/null | grep -c "istio.io" || true)
    [ "$count" -ge 10 ] && echo "Istio CRDs ready ($count)" && break
    echo "Attempt $i/24 — $count CRDs, waiting 15s..."
    sleep 15
  done

  # Wave 1 — control plane
  kubectl apply -f platform/gitops/argocd/apps/istiod-app.yaml
  kubectl rollout status deployment/istiod -n istio-system --timeout=5m || true

  # Wave 2 — ingress gateway
  kubectl apply -f platform/gitops/argocd/apps/istio-gateway-app.yaml

  echo "Waiting for Istio ingress gateway IP..."
  local istio_ip=""
  for i in $(seq 1 36); do
    istio_ip=$(kubectl get svc istio-ingressgateway -n istio-system \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    [ -z "$istio_ip" ] && istio_ip=$(kubectl get svc istio-ingressgateway -n istio-system \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    [ -n "$istio_ip" ] && echo "istio_ip=$istio_ip" >> "$GITHUB_OUTPUT" && break
    sleep 10
  done

  # Wave 3 — networking resources
  kubectl apply -f platform/gitops/argocd/apps/istio-networking-app.yaml
  echo "::notice::Istio deployed — gateway IP: ${istio_ip:-pending}"
}

# ── Deploy Prometheus ────────────────────────────────────────────────────────
deploy_prometheus() {
  kubectl apply -f platform/gitops/argocd/apps/prometheus-app.yaml
  echo "::notice::kube-prometheus-stack submitted to ArgoCD"
}

# ── Uninstall apps only ──────────────────────────────────────────────────────
uninstall_apps() {
  echo "Removing ArgoCD Application and AppProject for ${ENV}..."
  kubectl delete application "rental-ledger-${ENV}" -n "$NAMESPACE_ARGOCD" --ignore-not-found
  kubectl delete appproject "rental-ledger" -n "$NAMESPACE_ARGOCD" --ignore-not-found
  echo "Apps removed. ArgoCD and add-ons remain running."
}

# ── Uninstall addons only ────────────────────────────────────────────────────
uninstall_addons() {
  echo "Removing platform add-ons (Istio, Prometheus)..."
  for app in istio-networking istio-gateway istiod istio-base kube-prometheus-stack; do
    kubectl delete application "$app" -n "$NAMESPACE_ARGOCD" --ignore-not-found || true
  done
  kubectl delete namespace istio-system monitoring --ignore-not-found || true
  echo "Add-ons removed. ArgoCD and app remain running."
}

# ── Uninstall ArgoCD entirely ────────────────────────────────────────────────
uninstall_argocd() {
  helm uninstall argocd --namespace "$NAMESPACE_ARGOCD" || true
  kubectl delete namespace "$NAMESPACE_ARGOCD" --ignore-not-found
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
echo "==> Azure bootstrap: ENV=$ENV ACTION=$ACTION DB_MODE=$DB_MODE ADDONS=$ADDONS"

fetch_platform_secrets
get_aks_credentials

case "$ACTION" in

  install|upgrade)
    [ "$ACTION" = "install" ] && get_acr_server && patch_kustomize_overlay && create_acr_pull_secret

    case "$DB_MODE" in
      helm-pg)                     deploy_helm_pg ;;
      azure-pg|azure-sql|"")       fetch_db_secrets_from_kv ;;
      *)
        echo "::error::Unknown db_mode: $DB_MODE"
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
    get_acr_server
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

  uninstall-apps)
    uninstall_apps
    ;;

  uninstall-addons)
    uninstall_addons
    ;;

  uninstall)
    uninstall_argocd
    ;;

  *)
    echo "::error::Unknown action: $ACTION"
    exit 1
    ;;
esac

echo "==> Azure bootstrap complete: $ACTION/$ENV"
