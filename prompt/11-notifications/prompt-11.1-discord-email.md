# Prompt 11.1 - Discord + Email Notifications: Full Setup

```
Act as a DevSecOps engineer specialising in alerting and notification systems.

CONTEXT:
- Platform: rentalAppLedger on AKS/GKE
- Notification channels: Discord webhook + Email (SMTP / SendGrid free)
- Events to notify:
  1. Pod restart (any pod in rental-dev/rental-qa)
  2. Deployment failure or success (ArgoCD)
  3. GitHub Actions PR failure
  4. Terraform OPA policy violation
  5. Node/Pod resource alerts (Prometheus AlertManager)
  6. QA validation result (pass/fail)

TASK:
Generate complete notification system:

### 1. Discord Webhook Python Helper (notify/discord_notifier.py)
```python
class DiscordNotifier:
    def send_pod_restart(self, pod_name, namespace, restart_count, reason)
    def send_deployment_status(self, app, env, status, git_sha, argocd_url)
    def send_pr_failure(self, pr_number, pr_url, failed_checks)
    def send_opa_violation(self, policy_name, resource, violation_message)
    def send_resource_alert(self, alert_name, severity, labels, value)
    def send_qa_result(self, env, cloud, passed, failed, report_url)

# Embed format: coloured (green/red/yellow) Discord embed
# Critical: red embed @here mention
# Warning: yellow embed, no mention
# Success: green embed
```

### 2. AlertManager Discord Config (alertmanager-config.yaml)
- Receiver: discord-critical (all Critical alerts)
- Receiver: discord-warnings (all Warning alerts)
- Route: group by alertname + namespace
- Inhibit: if critical firing, suppress warnings for same service

### 3. Kubernetes Event Watcher (notify/k8s_event_watcher.py)
```python
# Watch K8s events for pod restarts
# Use kubernetes.watch.Watch() on Events API
# Filter: reason=BackOff OR reason=OOMKilling
# Trigger Discord notification immediately
# Run as: Kubernetes Deployment (always-on)
```

### 4. GitHub Actions Notification Steps
- Reusable workflow: .github/workflows/notify.yml
  Input: event_type, status, message, environment
  Steps: curl Discord webhook + optional email

### 5. Email Notification (using Python smtplib / SendGrid free)
- Send HTML email for: Deployment success/failure, QA report
- Template: clean HTML table with status, environment, timestamp, ArgoCD link
- Recipient: configurable via env variable

INCLUDE:
- Kubernetes manifests for k8s_event_watcher Deployment
- RBAC for event watcher (read-only Events)
- secrets.yaml template (Discord webhook URL, email credentials)
- How to store secrets in KeyVault (Azure) / Secret Manager (GCP)

OUTPUT: All Python files + Kubernetes manifests + GitHub Actions YAML + email template
```
