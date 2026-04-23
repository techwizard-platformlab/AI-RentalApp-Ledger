# Shared Testing Utilities

Reusable validation scripts and ArgoCD hooks shared across all environments and clouds.

## Files

| File | Purpose |
|---|---|
| `validate_deployment.sh` | Post-deploy health check (pods, services, ArgoCD sync, API gateway) |
| `argocd-postsync-hook.yaml` | ArgoCD PostSync Job — runs after every sync |

## Usage

### Manual validation

```bash
bash tests/shared/testing/validate_deployment.sh \
  --cloud azure \
  --env dev \
  --notify discord
```

Options:

| Flag | Values | Default |
|---|---|---|
| `--cloud` | azure / gcp | azure |
| `--env` | dev / qa / uat / prod | dev |
| `--notify` | discord | (none) |
| `--namespace` | custom namespace | rental-<env> |

Set `DISCORD_WEBHOOK_URL` in environment to enable Discord notifications.

### ArgoCD PostSync hook

Copy `argocd-postsync-hook.yaml` into the Kustomize overlay for the target environment:

```bash
cp tests/shared/testing/argocd-postsync-hook.yaml \
   platform/kubernetes/overlays/dev/
```

Then add it to `kustomization.yaml`:

```yaml
resources:
  - argocd-postsync-hook.yaml
```

## Environment-specific tests

- `tests/dev/testing/` — BDD smoke tests, dev-only validation
- `tests/qa/testing/`  — Full regression BDD suite
