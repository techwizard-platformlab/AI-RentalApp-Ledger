# Testing — Shared Base

Generic smoke validation and BDD test infrastructure, reusable across all
environments (dev / qa / uat / prod) and both clouds (Azure / GCP).

## Structure

```
environments/
  shared/testing/               ← base scripts and templates (this directory)
    validate_deployment.sh      ← generic smoke validation (all clouds/envs)
    argocd-postsync-hook.yaml   ← ArgoCD PostSync hook template
    README.md
  dev/testing/                  ← dev-specific BDD tests + env config
  qa/testing/                   ← qa-specific BDD tests
  uat/testing/                  ← uat-specific BDD tests
  prod/testing/                 ← prod-specific BDD tests (lighter, readonly)
```

## validate_deployment.sh

Generic smoke validator. Checks:

1. All pods Running / no CrashLoopBackOff
2. API health endpoints (200 OK)
3. TLS certificate validity (>14 days remaining)
4. Memory thresholds (warn if >450 Mi)
5. Istio sidecar presence

```bash
# Usage
./environments/shared/testing/validate_deployment.sh \
  --cloud azure \
  --env   dev \
  --notify discord    # optional: posts result to Discord
```

Env vars (all optional — sensible defaults):
- `GATEWAY_URL` — override default cluster-local URL
- `DISCORD_WEBHOOK_URL` — for `--notify discord`
- `TLS_DOMAIN` — domain to check TLS cert on

## ArgoCD PostSync hook

The hook template in `argocd-postsync-hook.yaml` runs `validate_deployment.sh`
automatically after each ArgoCD sync. To wire it up:

1. Copy the template into your overlay:
   ```bash
   cp environments/shared/testing/argocd-postsync-hook.yaml \
      platform/kubernetes/overlays/dev/post-deploy-validate.yaml
   ```
2. Replace `ENV_VALUE` and `CLOUD_VALUE` in the copied file
3. Create the ConfigMap that mounts the script:
   ```bash
   kubectl create configmap validate-script-cm \
     --from-file=validate_deployment.sh=environments/shared/testing/validate_deployment.sh \
     -n rental-dev --dry-run=client -o yaml | kubectl apply -f -
   ```
4. Create the ServiceAccount:
   ```bash
   kubectl create serviceaccount validation-sa -n rental-dev --dry-run=client -o yaml | kubectl apply -f -
   # Bind read-only ClusterRole to it
   kubectl create clusterrolebinding validation-sa-view \
     --clusterrole=view --serviceaccount=rental-dev:validation-sa \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

## BDD tests (per-environment)

BDD tests use the [Behave](https://behave.readthedocs.io/) framework and live
in each environment's `testing/` subdirectory:

```
environments/dev/testing/
  features/
    api_health.feature
    rag_assistant.feature
    rental_operations.feature
    steps/
      api_steps.py
      k8s_steps.py
      rag_steps.py
    environment.py
  requirements.txt
```

Run locally (requires port-forward to the cluster):
```bash
# Port-forward services
kubectl port-forward -n rental-dev svc/api-gateway 8000:80 &
kubectl port-forward -n rental-dev svc/rental-rag-api 8080:8080 &

pip install -r environments/dev/testing/requirements.txt
cd environments/dev/testing
behave
```

In CI, the `qa-validate.yml` workflow handles port-forwarding automatically.
