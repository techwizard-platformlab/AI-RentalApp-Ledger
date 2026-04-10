#!/usr/bin/env bash
# =============================================================================
# QA secrets — created by argocd-bootstrap.yml or run manually once.
# Same pattern as dev but targets rental-qa namespace.
# =============================================================================
set -euo pipefail

KV="${KEY_VAULT_NAME:-rental-shared-kv}"
NS="rental-qa"

kv_secret() { az keyvault secret show --vault-name "$KV" --name "$1" --query value -o tsv; }

DB_HOST=$(kv_secret db-host)
DB_NAME=$(kv_secret db-name)
DB_USER=$(kv_secret db-user)
DB_PASS=$(kv_secret db-password)
DB_PORT=$(kv_secret db-port)
DB_ENGINE=$(kv_secret db-engine)
DJANGO_SECRET=$(kv_secret django-secret-key)
DISCORD_URL=$(kv_secret discord-webhook-url 2>/dev/null || echo "")
SMTP_PASS=$(kv_secret smtp-password 2>/dev/null || echo "")
GROQ_KEY=$(kv_secret groq-api-key 2>/dev/null || echo "")
ANTHROPIC_KEY=$(kv_secret anthropic-api-key 2>/dev/null || echo "")

for svc in api-gateway rental-service ledger-service; do
  kubectl create secret generic "${svc}-secret" \
    --namespace "$NS" \
    --from-literal=DB_HOST="$DB_HOST" \
    --from-literal=DB_NAME="$DB_NAME" \
    --from-literal=DB_USER="$DB_USER" \
    --from-literal=DB_PASSWORD="$DB_PASS" \
    --from-literal=DB_PORT="$DB_PORT" \
    --from-literal=DB_ENGINE="$DB_ENGINE" \
    --from-literal=SECRET_KEY="$DJANGO_SECRET" \
    --save-config --dry-run=client -o yaml | kubectl apply -f -
done

kubectl create secret generic notification-service-secret \
  --namespace "$NS" \
  --from-literal=DB_HOST="$DB_HOST" \
  --from-literal=DB_NAME="$DB_NAME" \
  --from-literal=DB_USER="$DB_USER" \
  --from-literal=DB_PASSWORD="$DB_PASS" \
  --from-literal=DB_PORT="$DB_PORT" \
  --from-literal=DB_ENGINE="$DB_ENGINE" \
  --from-literal=SECRET_KEY="$DJANGO_SECRET" \
  --from-literal=DISCORD_WEBHOOK_URL="$DISCORD_URL" \
  --from-literal=EMAIL_HOST_PASSWORD="$SMTP_PASS" \
  --save-config --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic rag-api-secret \
  --namespace "$NS" \
  --from-literal=DB_HOST="$DB_HOST" \
  --from-literal=DB_NAME="$DB_NAME" \
  --from-literal=DB_USER="$DB_USER" \
  --from-literal=DB_PASSWORD="$DB_PASS" \
  --from-literal=DB_PORT="$DB_PORT" \
  --from-literal=GROQ_API_KEY="$GROQ_KEY" \
  --from-literal=ANTHROPIC_API_KEY="$ANTHROPIC_KEY" \
  --save-config --dry-run=client -o yaml | kubectl apply -f -

echo "Secrets applied to namespace: $NS"
