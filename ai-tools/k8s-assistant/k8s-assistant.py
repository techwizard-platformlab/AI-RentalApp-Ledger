#!/usr/bin/env python3
"""
k8s-assistant.py — AI-powered Kubernetes pod log analyser and remediator.

LLM priority (free → paid):
  1. Ollama (local, free)  — ollama pull llama3.2
  2. Groq API (free tier) — https://console.groq.com
  3. Claude Haiku          — cheapest Anthropic model

Usage:
  python k8s-assistant.py --namespace rental-dev --watch
  python k8s-assistant.py --pod api-gateway-abc123 --analyse
  python k8s-assistant.py --namespace rental-dev --auto-fix --dry-run
"""

import argparse
import json
import os
import sys
import time
from dataclasses import dataclass, field
from typing import Optional

import requests
from kubernetes import client, config
from kubernetes.client.rest import ApiException
from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

console = Console()

# ─────────────────────────────────────────────────────────────────────────────
# Data models
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class PodAnalysis:
    pod_name: str
    namespace: str
    error_type: str = "Unknown"
    root_cause: str = ""
    severity: str = "info"           # critical | warning | info
    suggested_fixes: list[str] = field(default_factory=list)
    kubectl_commands: list[str] = field(default_factory=list)
    documentation_links: list[str] = field(default_factory=list)


# ─────────────────────────────────────────────────────────────────────────────
# Kubernetes helpers
# ─────────────────────────────────────────────────────────────────────────────

def load_k8s_config() -> None:
    """Load kubeconfig from in-cluster or local ~/.kube/config."""
    try:
        config.load_incluster_config()
    except config.ConfigException:
        config.load_kube_config()


def get_failing_pods(namespace: str) -> list[dict]:
    """Return all pods not in Running/Succeeded state."""
    v1 = client.CoreV1Api()
    pods = v1.list_namespaced_pod(namespace)
    failing = []
    for pod in pods.items:
        phase = pod.status.phase or "Unknown"
        if phase not in ("Running", "Succeeded"):
            failing.append({
                "name": pod.metadata.name,
                "namespace": namespace,
                "phase": phase,
                "reason": pod.status.reason or "",
                "conditions": [
                    {"type": c.type, "status": c.status, "reason": c.reason or "", "message": c.message or ""}
                    for c in (pod.status.conditions or [])
                ]
            })
            continue
        # Also check for CrashLoopBackOff in container statuses
        for cs in (pod.status.container_statuses or []):
            if cs.state and cs.state.waiting:
                if cs.state.waiting.reason in ("CrashLoopBackOff", "OOMKilled", "Error"):
                    failing.append({
                        "name": pod.metadata.name,
                        "namespace": namespace,
                        "phase": phase,
                        "reason": cs.state.waiting.reason,
                        "container": cs.name,
                        "restart_count": cs.restart_count,
                    })
                    break
    return failing


def get_pod_logs(pod_name: str, namespace: str, lines: int = 100) -> str:
    """Fetch the last N lines of pod logs."""
    v1 = client.CoreV1Api()
    try:
        logs = v1.read_namespaced_pod_log(
            name=pod_name,
            namespace=namespace,
            tail_lines=lines,
            timestamps=True,
        )
        return logs
    except ApiException as e:
        # Try previous container logs (useful for CrashLoopBackOff)
        try:
            logs = v1.read_namespaced_pod_log(
                name=pod_name,
                namespace=namespace,
                tail_lines=lines,
                previous=True,
                timestamps=True,
            )
            return f"[Previous container logs]\n{logs}"
        except ApiException:
            return f"Could not fetch logs: {e.reason}"


def get_pod_events(pod_name: str, namespace: str) -> list[dict]:
    """Fetch Kubernetes events for a specific pod."""
    v1 = client.CoreV1Api()
    events = v1.list_namespaced_event(
        namespace=namespace,
        field_selector=f"involvedObject.name={pod_name}"
    )
    return [
        {
            "type": e.type,
            "reason": e.reason,
            "message": e.message,
            "count": e.count,
            "last_timestamp": str(e.last_timestamp),
        }
        for e in events.items
    ]


def get_pod_status(pod_name: str, namespace: str) -> dict:
    """Get full pod status as a dict."""
    v1 = client.CoreV1Api()
    try:
        pod = v1.read_namespaced_pod(name=pod_name, namespace=namespace)
        return {
            "phase": pod.status.phase,
            "conditions": [
                {"type": c.type, "status": c.status, "reason": c.reason, "message": c.message}
                for c in (pod.status.conditions or [])
            ],
            "container_statuses": [
                {
                    "name": cs.name,
                    "ready": cs.ready,
                    "restart_count": cs.restart_count,
                    "state": {
                        "waiting": {"reason": cs.state.waiting.reason, "message": cs.state.waiting.message}
                        if cs.state and cs.state.waiting else None,
                        "running": {"started_at": str(cs.state.running.started_at)}
                        if cs.state and cs.state.running else None,
                        "terminated": {"exit_code": cs.state.terminated.exit_code, "reason": cs.state.terminated.reason}
                        if cs.state and cs.state.terminated else None,
                    }
                }
                for cs in (pod.status.container_statuses or [])
            ]
        }
    except ApiException as e:
        return {"error": str(e)}


# ─────────────────────────────────────────────────────────────────────────────
# LLM system prompt
# ─────────────────────────────────────────────────────────────────────────────

SYSTEM_PROMPT = """You are an expert Kubernetes Site Reliability Engineer.
Analyse the provided pod logs, events, and status to diagnose issues.

Always respond with valid JSON matching this schema:
{
  "error_type": "OOMKilled | CrashLoopBackOff | ImagePullError | ConfigError | NetworkError | Unknown",
  "root_cause": "concise plain English explanation (2-3 sentences)",
  "severity": "critical | warning | info",
  "suggested_fixes": ["fix 1", "fix 2", "fix 3"],
  "kubectl_commands": ["kubectl describe pod <name> -n <namespace>", "..."],
  "documentation_links": ["https://kubernetes.io/docs/..."]
}

Be specific. Reference actual error messages from the logs. Suggest concrete kubectl commands."""


def _build_user_message(pod_name: str, logs: str, events: list, status: dict) -> str:
    return f"""Analyse this Kubernetes pod issue:

POD NAME: {pod_name}
STATUS:
{json.dumps(status, indent=2)}

EVENTS (most recent):
{json.dumps(events[-5:] if len(events) > 5 else events, indent=2)}

LOGS (last 100 lines):
{logs[-3000:] if len(logs) > 3000 else logs}

Respond with JSON diagnosis only."""


# ─────────────────────────────────────────────────────────────────────────────
# LLM providers
# ─────────────────────────────────────────────────────────────────────────────

def _call_ollama(user_msg: str, model: str = "llama3.2") -> str:
    resp = requests.post(
        "http://localhost:11434/api/chat",
        json={
            "model": model,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_msg},
            ],
            "stream": False,
            "format": "json",
        },
        timeout=120,
    )
    resp.raise_for_status()
    return resp.json()["message"]["content"]


def _call_groq(user_msg: str, model: str = "llama3-8b-8192") -> str:
    api_key = os.environ.get("GROQ_API_KEY", "")
    resp = requests.post(
        "https://api.groq.com/openai/v1/chat/completions",
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        json={
            "model": model,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_msg},
            ],
            "response_format": {"type": "json_object"},
        },
        timeout=60,
    )
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"]


def _call_claude_haiku(user_msg: str) -> str:
    import anthropic
    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    c = anthropic.Anthropic(api_key=api_key)
    msg = c.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=1024,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": user_msg}],
    )
    return msg.content[0].text


def analyse_logs_with_llm(
    pod_name: str,
    logs: str,
    events: list,
    status: dict,
    llm_provider: str = "ollama",
) -> PodAnalysis:
    """Send pod context to LLM and return structured PodAnalysis."""
    user_msg = _build_user_message(pod_name, logs, events, status)

    try:
        if llm_provider == "ollama":
            raw = _call_ollama(user_msg)
        elif llm_provider == "groq":
            raw = _call_groq(user_msg)
        elif llm_provider == "claude":
            raw = _call_claude_haiku(user_msg)
        else:
            raise ValueError(f"Unknown LLM provider: {llm_provider}")

        data = json.loads(raw)
        return PodAnalysis(
            pod_name=pod_name,
            namespace=status.get("namespace", ""),
            error_type=data.get("error_type", "Unknown"),
            root_cause=data.get("root_cause", ""),
            severity=data.get("severity", "info"),
            suggested_fixes=data.get("suggested_fixes", []),
            kubectl_commands=data.get("kubectl_commands", []),
            documentation_links=data.get("documentation_links", []),
        )
    except Exception as e:
        console.print(f"[yellow]LLM call failed ({e}), falling back to basic analysis[/yellow]")
        return _basic_analysis(pod_name, status)


def _basic_analysis(pod_name: str, status: dict) -> PodAnalysis:
    """Rule-based fallback when LLM is unavailable."""
    for cs in status.get("container_statuses", []):
        waiting = cs.get("state", {}).get("waiting")
        if waiting:
            reason = waiting.get("reason", "Unknown")
            if reason == "CrashLoopBackOff":
                return PodAnalysis(
                    pod_name=pod_name, namespace="",
                    error_type="CrashLoopBackOff",
                    root_cause="Container is repeatedly crashing. Check logs for the root exception.",
                    severity="critical",
                    suggested_fixes=["Check application logs for startup errors", "Verify environment variables", "Check resource limits"],
                    kubectl_commands=[f"kubectl logs {pod_name} --previous", f"kubectl describe pod {pod_name}"],
                )
            if reason == "OOMKilled":
                return PodAnalysis(
                    pod_name=pod_name, namespace="",
                    error_type="OOMKilled",
                    root_cause="Container exceeded its memory limit and was killed.",
                    severity="critical",
                    suggested_fixes=["Increase memory limit in deployment.yaml", "Check for memory leaks in application code"],
                    kubectl_commands=[f"kubectl describe pod {pod_name}", f"kubectl top pod {pod_name}"],
                )
    return PodAnalysis(pod_name=pod_name, namespace="", error_type="Unknown", severity="warning",
                       root_cause="Could not determine root cause automatically.")


# ─────────────────────────────────────────────────────────────────────────────
# Auto-remediation
# ─────────────────────────────────────────────────────────────────────────────

def execute_remediation(analysis: PodAnalysis, namespace: str, dry_run: bool = False) -> None:
    """Offer remediation actions with user confirmation."""
    apps_v1 = client.AppsV1Api()

    # Infer deployment name from pod name (strip replica-set suffix)
    parts = analysis.pod_name.rsplit("-", 2)
    deployment_name = parts[0] if len(parts) >= 2 else analysis.pod_name

    actions = {
        "1": ("Restart deployment (rollout restart)", lambda: apps_v1.patch_namespaced_deployment(
            deployment_name, namespace,
            {"spec": {"template": {"metadata": {"annotations": {"kubectl.kubernetes.io/restartedAt": str(time.time())}}}}}
        )),
        "2": ("Rollback deployment (undo)", lambda: apps_v1.create_namespaced_deployment_rollback(
            deployment_name, namespace, client.AppsV1beta1DeploymentRollback()
        )),
        "3": ("Scale down to 0", lambda: apps_v1.patch_namespaced_deployment_scale(
            deployment_name, namespace, {"spec": {"replicas": 0}}
        )),
    }

    console.print("\n[bold]Available remediation actions:[/bold]")
    for key, (desc, _) in actions.items():
        console.print(f"  [{key}] {desc}")
    console.print("  [q] Skip / quit")

    choice = console.input("\nExecute fix? [1/2/3/q]: ").strip().lower()
    if choice not in actions:
        console.print("[dim]Skipped.[/dim]")
        return

    desc, action = actions[choice]
    if dry_run:
        console.print(f"[yellow][DRY RUN] Would execute: {desc}[/yellow]")
        return

    confirm = console.input(f"Confirm '{desc}' on deployment '{deployment_name}'? [y/N]: ").strip().lower()
    if confirm != "y":
        console.print("[dim]Cancelled.[/dim]")
        return

    try:
        action()
        console.print(f"[green]✓ Executed: {desc}[/green]")
    except ApiException as e:
        console.print(f"[red]Failed: {e.reason}[/red]")


# ─────────────────────────────────────────────────────────────────────────────
# Notifications
# ─────────────────────────────────────────────────────────────────────────────

def send_discord_notification(analysis: PodAnalysis, webhook_url: str) -> None:
    if not webhook_url:
        return
    color = 0xff0000 if analysis.severity == "critical" else 0xffa500
    fixes = "\n".join(f"• {f}" for f in analysis.suggested_fixes[:3])
    cmd = analysis.kubectl_commands[0] if analysis.kubectl_commands else "N/A"
    payload = {
        "embeds": [{
            "title": f"🚨 K8s Issue: {analysis.error_type} — {analysis.pod_name}",
            "description": analysis.root_cause,
            "color": color,
            "fields": [
                {"name": "Severity", "value": analysis.severity.upper(), "inline": True},
                {"name": "Namespace", "value": analysis.namespace, "inline": True},
                {"name": "Suggested Fixes", "value": fixes or "N/A", "inline": False},
                {"name": "kubectl Command", "value": f"`{cmd}`", "inline": False},
            ]
        }]
    }
    try:
        requests.post(webhook_url, json=payload, timeout=10)
    except Exception as e:
        console.print(f"[yellow]Discord notify failed: {e}[/yellow]")


# ─────────────────────────────────────────────────────────────────────────────
# Display
# ─────────────────────────────────────────────────────────────────────────────

def display_analysis(analysis: PodAnalysis) -> None:
    severity_color = {"critical": "red", "warning": "yellow", "info": "blue"}.get(analysis.severity, "white")

    panel = Panel(
        f"[bold]Error Type:[/bold] {analysis.error_type}\n"
        f"[bold]Severity:[/bold] [{severity_color}]{analysis.severity.upper()}[/{severity_color}]\n\n"
        f"[bold]Root Cause:[/bold]\n{analysis.root_cause}\n\n"
        f"[bold]Suggested Fixes:[/bold]\n" + "\n".join(f"  {i+1}. {f}" for i, f in enumerate(analysis.suggested_fixes)) + "\n\n"
        f"[bold]kubectl Commands:[/bold]\n" + "\n".join(f"  $ {c}" for c in analysis.kubectl_commands),
        title=f"[bold]Pod Analysis: {analysis.pod_name}[/bold]",
        border_style=severity_color,
    )
    console.print(panel)

    if analysis.documentation_links:
        console.print("\n[dim]Documentation:[/dim]")
        for link in analysis.documentation_links:
            console.print(f"  [dim]{link}[/dim]")


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="AI-powered Kubernetes pod analyser")
    parser.add_argument("--namespace", "-n", default="rental-dev", help="Kubernetes namespace")
    parser.add_argument("--pod", "-p", help="Specific pod name to analyse")
    parser.add_argument("--watch", "-w", action="store_true", help="Watch for failing pods continuously")
    parser.add_argument("--analyse", "-a", action="store_true", help="Analyse a specific pod")
    parser.add_argument("--auto-fix", action="store_true", help="Offer remediation actions (requires elevated RBAC)")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be done without executing")
    parser.add_argument("--llm", default="ollama", choices=["ollama", "groq", "claude"], help="LLM provider")
    parser.add_argument("--watch-interval", type=int, default=30, help="Watch interval in seconds")
    args = parser.parse_args()

    load_k8s_config()
    discord_webhook = os.environ.get("DISCORD_WEBHOOK_URL", "")

    if args.watch:
        console.print(f"[bold blue]Watching namespace '{args.namespace}' every {args.watch_interval}s...[/bold blue]")
        while True:
            failing = get_failing_pods(args.namespace)
            if failing:
                console.print(f"\n[red]Found {len(failing)} failing pod(s)[/red]")
                for pod_info in failing:
                    _analyse_pod(pod_info["name"], args.namespace, args.llm, args.auto_fix, args.dry_run, discord_webhook)
            else:
                console.print(f"[dim]{time.strftime('%H:%M:%S')} — No failing pods in {args.namespace}[/dim]")
            time.sleep(args.watch_interval)

    elif args.pod and args.analyse:
        _analyse_pod(args.pod, args.namespace, args.llm, args.auto_fix, args.dry_run, discord_webhook)

    else:
        # List failing pods
        failing = get_failing_pods(args.namespace)
        if not failing:
            console.print(f"[green]✓ No failing pods in namespace '{args.namespace}'[/green]")
            return

        table = Table(title=f"Failing Pods — {args.namespace}", show_header=True)
        table.add_column("Pod", style="red")
        table.add_column("Phase")
        table.add_column("Reason")
        table.add_column("Restarts")

        for pod in failing:
            table.add_row(
                pod["name"],
                pod.get("phase", ""),
                pod.get("reason", ""),
                str(pod.get("restart_count", "-")),
            )
        console.print(table)
        console.print("\nRun with [bold]--pod <name> --analyse[/bold] to diagnose a specific pod.")


def _analyse_pod(pod_name: str, namespace: str, llm: str, auto_fix: bool, dry_run: bool, discord_webhook: str) -> None:
    console.print(f"\n[bold]Analysing pod: {pod_name}[/bold]")

    with console.status("Fetching pod data..."):
        logs = get_pod_logs(pod_name, namespace)
        events = get_pod_events(pod_name, namespace)
        status = get_pod_status(pod_name, namespace)

    with console.status(f"Calling {llm} LLM..."):
        analysis = analyse_logs_with_llm(pod_name, logs, events, status, llm)
        analysis.namespace = namespace

    display_analysis(analysis)

    if analysis.severity == "critical":
        send_discord_notification(analysis, discord_webhook)

    if auto_fix:
        execute_remediation(analysis, namespace, dry_run)


if __name__ == "__main__":
    main()
