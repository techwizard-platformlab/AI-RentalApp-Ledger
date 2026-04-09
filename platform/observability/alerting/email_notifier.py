"""
email_notifier.py — HTML email notifications via SMTP (smtplib) or SendGrid free tier.
Used for deployment success/failure and QA reports.
"""

import os
import smtplib
from datetime import datetime, timezone
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from string import Template

SMTP_HOST     = os.environ.get("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT     = int(os.environ.get("SMTP_PORT", "587"))
SMTP_USER     = os.environ.get("SMTP_USERNAME", "")
SMTP_PASS     = os.environ.get("SMTP_PASSWORD", "")
EMAIL_FROM    = os.environ.get("MAIL_FROM", "noreply@rentalapp.io")
EMAIL_TO      = os.environ.get("MAIL_TO", "")

_HTML_TEMPLATE = Template("""<!DOCTYPE html>
<html>
<head><style>
  body { font-family: Arial, sans-serif; background: #f4f4f4; margin: 0; padding: 20px; }
  .card { background: #fff; border-radius: 8px; padding: 24px; max-width: 600px; margin: auto; }
  .header { background: $color; color: white; padding: 16px; border-radius: 6px 6px 0 0; }
  h1 { margin: 0; font-size: 20px; }
  table { width: 100%; border-collapse: collapse; margin-top: 16px; }
  th { background: #f0f0f0; text-align: left; padding: 8px; }
  td { padding: 8px; border-bottom: 1px solid #eee; }
  .footer { color: #888; font-size: 12px; margin-top: 20px; }
</style></head>
<body><div class="card">
  <div class="header"><h1>$emoji $title</h1></div>
  <table>$rows</table>
  $argocd_link
  <p class="footer">rentalAppLedger • $timestamp</p>
</div></body>
</html>""")


def _send_email(subject: str, html_body: str, to: str = EMAIL_TO) -> None:
    if not to or not SMTP_USER:
        return
    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"]    = EMAIL_FROM
    msg["To"]      = to
    msg.attach(MIMEText(html_body, "html"))
    try:
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as smtp:
            smtp.ehlo()
            smtp.starttls()
            smtp.login(SMTP_USER, SMTP_PASS)
            smtp.sendmail(EMAIL_FROM, to, msg.as_string())
    except Exception as e:
        print(f"[EmailNotifier] send failed: {e}")


def _rows(data: dict) -> str:
    return "".join(f"<tr><th>{k}</th><td>{v}</td></tr>" for k, v in data.items())


def send_deployment_email(app: str, env: str, status: str, git_sha: str, argocd_url: str = "") -> None:
    success = status.lower() in ("succeeded", "success", "synced")
    color   = "#27ae60" if success else "#e74c3c"
    emoji   = "✅" if success else "❌"
    link    = f'<p><a href="{argocd_url}">View in ArgoCD →</a></p>' if argocd_url else ""
    html = _HTML_TEMPLATE.substitute(
        color=color, emoji=emoji,
        title=f"Deployment {status.upper()} — {app}",
        rows=_rows({"Application": app, "Environment": env, "Status": status.upper(), "Git SHA": git_sha[:8]}),
        argocd_link=link,
        timestamp=datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
    )
    _send_email(f"[rentalApp] Deployment {status.upper()}: {app} → {env}", html)


def send_qa_report_email(env: str, cloud: str, passed: int, failed: int, report_url: str = "") -> None:
    success = failed == 0
    color   = "#27ae60" if success else "#e74c3c"
    emoji   = "✅" if success else "❌"
    link    = f'<p><a href="{report_url}">View Full Report →</a></p>' if report_url else ""
    html = _HTML_TEMPLATE.substitute(
        color=color, emoji=emoji,
        title=f"QA Validation {'PASSED' if success else 'FAILED'} — {env}/{cloud}",
        rows=_rows({"Environment": env, "Cloud": cloud, "Passed": str(passed), "Failed": str(failed)}),
        argocd_link=link,
        timestamp=datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
    )
    _send_email(f"[rentalApp] QA {'PASSED' if success else 'FAILED'}: {env}/{cloud}", html)
