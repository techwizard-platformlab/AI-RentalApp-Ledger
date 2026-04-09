# Prompt 11.2 - Notification: ArgoCD Native Notifications Setup

```
Act as an ArgoCD expert. Generate complete ArgoCD Notifications setup.

CONTEXT:
- ArgoCD managing rentalAppLedger on AKS + GKE
- Notifications: Discord webhook + Email
- Events: Sync Started, Sync Succeeded, Sync Failed, App Health Degraded,
  App OutOfSync, Rollback Triggered

TASK:
Generate ArgoCD Notifications configuration:

### 1. argocd-notifications-cm ConfigMap
- Templates for each event type:
  * sync-succeeded: green embed "SUCCESS {app} deployed to {env} | SHA: {sha}"
  * sync-failed: red embed "FAILED {app} deploy on {env} | Error: {message}"
  * app-degraded: red embed "DEGRADED {app} on {env}"
  * out-of-sync: yellow embed "OUT OF SYNC {app} on {env}"
  * rollback: orange embed "ROLLBACK {app} to {revision} on {env}"

### 2. argocd-notifications-secret Secret
- discord-webhook-url: {your-webhook-url}
- email-password: {smtp-password}

### 3. Annotation-based subscription
- Add annotations to each Application CRD:
  notifications.argoproj.io/subscribe.on-sync-succeeded.discord: ""
  notifications.argoproj.io/subscribe.on-sync-failed.discord: ""
  notifications.argoproj.io/subscribe.on-sync-failed.email: "ramprasath@example.com"

### 4. Trigger Customisation
- Only notify for rental-dev and rental-qa apps (not system apps)
- Suppress repeated OutOfSync if already notified in last 10 minutes
- Always notify on failure regardless of repeat interval

INCLUDE:
- Complete ConfigMap + Secret YAML
- How to test: argocd admin notifications trigger run
- How to check notification logs

OUTPUT: ConfigMap + Secret + Application annotation examples + test command
```
