"""
discord_notifier.py — Unified Discord embed notifier for rentalAppLedger.
All events use coloured embeds: green=success, red=critical, yellow=warning.
"""

import os
from datetime import datetime, timezone
from typing import Optional

import requests

DISCORD_WEBHOOK_URL = os.environ.get("DISCORD_WEBHOOK_URL", "")


class DiscordNotifier:
    def __init__(self, webhook_url: str = DISCORD_WEBHOOK_URL):
        self.webhook_url = webhook_url

    # ── Core send method ───────────────────────────────────────────────────────
    def _send(self, embed: dict, mention: bool = False) -> None:
        if not self.webhook_url:
            return
        payload: dict = {"embeds": [embed]}
        if mention:
            payload["content"] = "@here"
        try:
            resp = requests.post(self.webhook_url, json=payload, timeout=10)
            resp.raise_for_status()
        except Exception as e:
            print(f"[DiscordNotifier] send failed: {e}")

    def _ts(self) -> str:
        return datetime.now(timezone.utc).isoformat()

    # ── Event methods ──────────────────────────────────────────────────────────

    def send_pod_restart(self, pod_name: str, namespace: str, restart_count: int, reason: str) -> None:
        severity = "critical" if restart_count >= 5 else "warning"
        color = 0xFF0000 if severity == "critical" else 0xFFA500
        self._send({
            "title": f"{'🚨' if severity == 'critical' else '⚠️'} Pod Restart — {pod_name}",
            "color": color,
            "fields": [
                {"name": "Namespace",      "value": namespace,           "inline": True},
                {"name": "Restart Count",  "value": str(restart_count),  "inline": True},
                {"name": "Reason",         "value": reason or "Unknown", "inline": True},
            ],
            "footer": {"text": f"rentalAppLedger • {self._ts()}"},
        }, mention=(severity == "critical"))

    def send_deployment_status(
        self, app: str, env: str, status: str,
        git_sha: str, argocd_url: Optional[str] = None
    ) -> None:
        success = status.lower() in ("succeeded", "success", "synced")
        color = 0x00FF00 if success else 0xFF0000
        emoji = "✅" if success else "❌"
        fields = [
            {"name": "Environment", "value": env,               "inline": True},
            {"name": "Status",      "value": status.upper(),    "inline": True},
            {"name": "Git SHA",     "value": f"`{git_sha[:8]}`","inline": True},
        ]
        if argocd_url:
            fields.append({"name": "ArgoCD", "value": f"[View]({argocd_url})", "inline": False})
        self._send({
            "title": f"{emoji} Deployment {status.upper()} — {app}",
            "color": color,
            "fields": fields,
            "footer": {"text": f"rentalAppLedger • {self._ts()}"},
        }, mention=not success)

    def send_pr_failure(self, pr_number: int, pr_url: str, failed_checks: list[str]) -> None:
        checks_str = "\n".join(f"• {c}" for c in failed_checks) or "Unknown"
        self._send({
            "title": f"❌ PR #{pr_number} — CI Checks Failed",
            "url": pr_url,
            "color": 0xFF0000,
            "fields": [
                {"name": "Failed Checks", "value": checks_str, "inline": False},
                {"name": "PR URL",        "value": pr_url,     "inline": False},
            ],
            "footer": {"text": f"rentalAppLedger • {self._ts()}"},
        })

    def send_opa_violation(self, policy_name: str, resource: str, violation_message: str) -> None:
        self._send({
            "title": f"🔒 OPA Policy Violation — {policy_name}",
            "color": 0xFFA500,
            "fields": [
                {"name": "Resource",   "value": resource,           "inline": True},
                {"name": "Policy",     "value": policy_name,        "inline": True},
                {"name": "Violation",  "value": violation_message[:1000], "inline": False},
            ],
            "footer": {"text": f"rentalAppLedger • {self._ts()}"},
        })

    def send_resource_alert(
        self, alert_name: str, severity: str,
        labels: dict, value: float
    ) -> None:
        color = 0xFF0000 if severity == "critical" else 0xFFA500
        emoji = "🚨" if severity == "critical" else "⚠️"
        fields = [{"name": k, "value": str(v), "inline": True} for k, v in labels.items()]
        fields.append({"name": "Value", "value": str(round(value, 4)), "inline": True})
        self._send({
            "title": f"{emoji} [{severity.upper()}] {alert_name}",
            "color": color,
            "fields": fields,
            "footer": {"text": f"Prometheus AlertManager • {self._ts()}"},
        }, mention=(severity == "critical"))

    def send_qa_result(
        self, env: str, cloud: str,
        passed: int, failed: int, report_url: Optional[str] = None
    ) -> None:
        success = failed == 0
        color = 0x00FF00 if success else 0xFF0000
        emoji = "✅" if success else "❌"
        fields = [
            {"name": "Environment", "value": env,         "inline": True},
            {"name": "Cloud",       "value": cloud,       "inline": True},
            {"name": "Passed",      "value": str(passed), "inline": True},
            {"name": "Failed",      "value": str(failed), "inline": True},
        ]
        if report_url:
            fields.append({"name": "Report", "value": f"[HTML Report]({report_url})", "inline": False})
        self._send({
            "title": f"{emoji} QA Validation {'PASSED' if success else 'FAILED'} — {env}/{cloud}",
            "color": color,
            "fields": fields,
            "footer": {"text": f"rentalAppLedger BDD • {self._ts()}"},
        }, mention=not success)
