#!/usr/bin/env python3
"""
anomaly_detector.py — Statistical anomaly detection for rentalAppLedger.

Methods (no GPU, CPU-only, free):
  - Z-score  → point anomalies (CPU/memory spikes)
  - IQR      → distribution anomalies (latency outliers)
  - Rolling  → trend anomalies (memory leaks)

Runs as a Kubernetes CronJob every 5 minutes.
"""

import json
import logging
import os
import subprocess
import sys
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from typing import Optional

import numpy as np
import pandas as pd
import requests
from prometheus_api_client import PrometheusConnect
from scipy import stats

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger(__name__)

# ─────────────────────────────────────────────────────────────────────────────
# Config (from environment / ConfigMap)
# ─────────────────────────────────────────────────────────────────────────────
PROMETHEUS_URL    = os.environ.get("PROMETHEUS_URL", "http://kube-prometheus-stack-prometheus.monitoring:9090")
DISCORD_WEBHOOK   = os.environ.get("DISCORD_WEBHOOK_URL", "")
NAMESPACE         = os.environ.get("TARGET_NAMESPACE", "rental-dev")
ZSCORE_THRESHOLD  = float(os.environ.get("ZSCORE_THRESHOLD", "3.0"))
IQR_MULTIPLIER    = float(os.environ.get("IQR_MULTIPLIER", "1.5"))
ROLLING_WINDOW    = int(os.environ.get("ROLLING_WINDOW", "10"))
MEMORY_WARN_PCT   = float(os.environ.get("MEMORY_WARN_PCT", "90.0"))
ERROR_RATE_CRIT   = float(os.environ.get("ERROR_RATE_CRIT", "0.10"))   # 10%


# ─────────────────────────────────────────────────────────────────────────────
# Data model
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class Anomaly:
    metric: str
    pod: str
    namespace: str
    method: str          # zscore | iqr | trend
    value: float
    threshold: float
    severity: str        # critical | warning
    description: str
    timestamp: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    remediation_hint: str = ""


# ─────────────────────────────────────────────────────────────────────────────
# Prometheus client
# ─────────────────────────────────────────────────────────────────────────────

class PrometheusClient:
    def __init__(self, url: str):
        self.pc = PrometheusConnect(url=url, disable_ssl=True)

    def query_range(self, query: str, duration: str = "1h") -> pd.DataFrame:
        """Query Prometheus range data and return a tidy DataFrame."""
        try:
            result = self.pc.custom_query_range(
                query=query,
                start_time=datetime.now(timezone.utc) - pd.Timedelta(duration),
                end_time=datetime.now(timezone.utc),
                step="30s",
            )
            rows = []
            for series in result:
                pod = series["metric"].get("pod", series["metric"].get("container", "unknown"))
                for ts, val in series["values"]:
                    rows.append({"timestamp": float(ts), "pod": pod, "value": float(val)})
            if not rows:
                return pd.DataFrame(columns=["timestamp", "pod", "value"])
            df = pd.DataFrame(rows)
            df["timestamp"] = pd.to_datetime(df["timestamp"], unit="s", utc=True)
            return df
        except Exception as e:
            log.warning("Prometheus query failed (%s): %s", query[:60], e)
            return pd.DataFrame(columns=["timestamp", "pod", "value"])

    def query_instant(self, query: str) -> dict:
        try:
            result = self.pc.custom_query(query=query)
            return {r["metric"].get("pod", "unknown"): float(r["value"][1]) for r in result}
        except Exception as e:
            log.warning("Instant query failed: %s", e)
            return {}


# ─────────────────────────────────────────────────────────────────────────────
# Detection methods
# ─────────────────────────────────────────────────────────────────────────────

class AnomalyDetector:
    def detect_zscore(self, series: pd.Series, threshold: float = ZSCORE_THRESHOLD) -> list[float]:
        """Return indices of anomalous values (|z| > threshold)."""
        if len(series) < 3:
            return []
        z = np.abs(stats.zscore(series.dropna()))
        return list(series.index[z > threshold])

    def detect_iqr(self, series: pd.Series, multiplier: float = IQR_MULTIPLIER) -> list[float]:
        """Return indices of outliers outside [Q1 - m*IQR, Q3 + m*IQR]."""
        if len(series) < 4:
            return []
        q1, q3 = series.quantile(0.25), series.quantile(0.75)
        iqr = q3 - q1
        lower, upper = q1 - multiplier * iqr, q3 + multiplier * iqr
        outliers = series[(series < lower) | (series > upper)]
        return list(outliers.index)

    def detect_trend(self, series: pd.Series, window: int = ROLLING_WINDOW) -> list[float]:
        """Detect monotonically increasing trend (gradual memory leak pattern)."""
        if len(series) < window:
            return []
        rolling_mean = series.rolling(window).mean().dropna()
        # Anomaly: rolling mean increases > 20% over the window
        anomalies = []
        for i in range(1, len(rolling_mean)):
            prev = rolling_mean.iloc[i - 1]
            curr = rolling_mean.iloc[i]
            if prev > 0 and (curr - prev) / prev > 0.20:
                anomalies.append(rolling_mean.index[i])
        return anomalies


# ─────────────────────────────────────────────────────────────────────────────
# Reporting
# ─────────────────────────────────────────────────────────────────────────────

class AnomalyReporter:
    def format_discord_alert(self, anomaly: Anomaly) -> dict:
        color = 0xff0000 if anomaly.severity == "critical" else 0xffa500
        return {
            "embeds": [{
                "title": f"{'🚨' if anomaly.severity == 'critical' else '⚠️'} Anomaly: {anomaly.metric} — {anomaly.pod}",
                "description": anomaly.description,
                "color": color,
                "fields": [
                    {"name": "Method", "value": anomaly.method.upper(), "inline": True},
                    {"name": "Severity", "value": anomaly.severity.upper(), "inline": True},
                    {"name": "Namespace", "value": anomaly.namespace, "inline": True},
                    {"name": "Value", "value": f"{anomaly.value:.3f}", "inline": True},
                    {"name": "Threshold", "value": f"{anomaly.threshold:.3f}", "inline": True},
                    {"name": "Hint", "value": anomaly.remediation_hint or "N/A", "inline": False},
                ],
                "footer": {"text": f"Detected at {anomaly.timestamp}"}
            }]
        }

    def send_discord(self, webhook_url: str, anomaly: Anomaly) -> None:
        if not webhook_url:
            return
        payload = self.format_discord_alert(anomaly)
        try:
            resp = requests.post(webhook_url, json=payload, timeout=10)
            resp.raise_for_status()
            log.info("Discord alert sent for %s/%s", anomaly.metric, anomaly.pod)
        except Exception as e:
            log.warning("Discord send failed: %s", e)

    def log_to_prometheus(self, anomaly: Anomaly) -> None:
        """
        Expose anomaly as a custom metric via pushgateway or textfile collector.
        Simple textfile approach (works with node-exporter textfile collector):
        """
        metric_name = "rentalapp_anomaly_detected"
        labels = f'metric="{anomaly.metric}",pod="{anomaly.pod}",severity="{anomaly.severity}",method="{anomaly.method}"'
        line = f'{metric_name}{{{labels}}} 1\n'
        try:
            path = os.environ.get("TEXTFILE_PATH", "/tmp/anomalies.prom")
            with open(path, "a") as f:
                f.write(line)
        except Exception as e:
            log.debug("Could not write prometheus textfile: %s", e)


# ─────────────────────────────────────────────────────────────────────────────
# Main detection loop
# ─────────────────────────────────────────────────────────────────────────────

def run_detection() -> list[Anomaly]:
    prom = PrometheusClient(PROMETHEUS_URL)
    detector = AnomalyDetector()
    reporter = AnomalyReporter()
    anomalies: list[Anomaly] = []

    log.info("Starting anomaly detection for namespace: %s", NAMESPACE)

    # 1. CPU usage per pod (Z-score)
    cpu_df = prom.query_range(
        f'sum by (pod) (rate(container_cpu_usage_seconds_total{{namespace="{NAMESPACE}",container!=""}}[5m]))',
        duration="1h"
    )
    for pod, group in cpu_df.groupby("pod"):
        series = group.set_index("timestamp")["value"]
        anomalous_idx = detector.detect_zscore(series, ZSCORE_THRESHOLD)
        if anomalous_idx:
            peak = series.loc[anomalous_idx].max()
            a = Anomaly(
                metric="cpu_usage", pod=pod, namespace=NAMESPACE,
                method="zscore", value=peak, threshold=ZSCORE_THRESHOLD,
                severity="warning" if peak < 0.9 else "critical",
                description=f"CPU spike detected on pod {pod}: {peak:.3f} cores (z-score > {ZSCORE_THRESHOLD})",
                remediation_hint="Check for runaway processes. Consider increasing CPU limit or optimising code.",
            )
            anomalies.append(a)
            reporter.send_discord(DISCORD_WEBHOOK, a)
            reporter.log_to_prometheus(a)

    # 2. Memory usage per pod (trend / rolling mean)
    mem_df = prom.query_range(
        f'container_memory_working_set_bytes{{namespace="{NAMESPACE}",container!=""}}',
        duration="1h"
    )
    for pod, group in mem_df.groupby("pod"):
        series = group.set_index("timestamp")["value"]

        # Trend detection (gradual leak)
        trend_anomalies = detector.detect_trend(series, ROLLING_WINDOW)
        if trend_anomalies:
            peak = series.max()
            a = Anomaly(
                metric="memory_trend", pod=pod, namespace=NAMESPACE,
                method="trend", value=peak, threshold=0.20,
                severity="warning",
                description=f"Memory creep detected on pod {pod}: rolling mean increased >20% over {ROLLING_WINDOW} data points.",
                remediation_hint="Possible memory leak. Profile the application or restart the pod.",
            )
            anomalies.append(a)
            reporter.send_discord(DISCORD_WEBHOOK, a)

        # High memory absolute check
        instant_mem = prom.query_instant(
            f'container_memory_working_set_bytes{{namespace="{NAMESPACE}",pod="{pod}",container!=""}}'
            f' / container_spec_memory_limit_bytes{{namespace="{NAMESPACE}",pod="{pod}",container!=""}} * 100'
        )
        for p, pct in instant_mem.items():
            if pct > MEMORY_WARN_PCT:
                a = Anomaly(
                    metric="memory_pct", pod=p, namespace=NAMESPACE,
                    method="threshold", value=pct, threshold=MEMORY_WARN_PCT,
                    severity="critical" if pct > 95 else "warning",
                    description=f"Pod {p} memory usage at {pct:.1f}% of limit.",
                    remediation_hint="Scale horizontally or increase memory limit. Check for leaks.",
                )
                anomalies.append(a)
                reporter.send_discord(DISCORD_WEBHOOK, a)

    # 3. HTTP error rate (IQR)
    err_df = prom.query_range(
        f'sum by (job) (rate(http_requests_total{{namespace="{NAMESPACE}",status_code=~"5.."}}[5m]))'
        f' / sum by (job) (rate(http_requests_total{{namespace="{NAMESPACE}"}}[5m]))',
        duration="1h"
    )
    for job, group in err_df.groupby("pod"):
        series = group.set_index("timestamp")["value"].fillna(0)
        outlier_idx = detector.detect_iqr(series, IQR_MULTIPLIER)
        if outlier_idx:
            peak = series.loc[outlier_idx].max()
            if peak > ERROR_RATE_CRIT:
                a = Anomaly(
                    metric="http_error_rate", pod=job, namespace=NAMESPACE,
                    method="iqr", value=peak, threshold=ERROR_RATE_CRIT,
                    severity="critical",
                    description=f"HTTP 5xx error rate for {job} spiked to {peak*100:.1f}% (IQR outlier, threshold {ERROR_RATE_CRIT*100:.0f}%).",
                    remediation_hint="Check application logs. Verify downstream services. Consider circuit breaker.",
                )
                anomalies.append(a)
                reporter.send_discord(DISCORD_WEBHOOK, a)

    # 4. API latency p95 (Z-score)
    lat_df = prom.query_range(
        f'histogram_quantile(0.95, sum by (job, le) (rate(http_request_duration_seconds_bucket{{namespace="{NAMESPACE}"}}[5m])))',
        duration="1h"
    )
    for job, group in lat_df.groupby("pod"):
        series = group.set_index("timestamp")["value"].dropna()
        anomalous_idx = detector.detect_zscore(series, ZSCORE_THRESHOLD)
        if anomalous_idx:
            peak = series.loc[anomalous_idx].max()
            if peak > 2.0:   # 2 second SLO
                a = Anomaly(
                    metric="latency_p95", pod=job, namespace=NAMESPACE,
                    method="zscore", value=peak, threshold=2.0,
                    severity="warning",
                    description=f"P95 latency for {job} at {peak:.2f}s (SLO: 2s). Z-score anomaly detected.",
                    remediation_hint="Check slow endpoints. Review database query times. Consider caching.",
                )
                anomalies.append(a)
                reporter.send_discord(DISCORD_WEBHOOK, a)

    # 5. Pod restart count (threshold)
    restart_instant = prom.query_instant(
        f'kube_pod_container_status_restarts_total{{namespace="{NAMESPACE}"}}'
    )
    for pod, restarts in restart_instant.items():
        if restarts >= 3:
            a = Anomaly(
                metric="pod_restarts", pod=pod, namespace=NAMESPACE,
                method="threshold", value=restarts, threshold=3,
                severity="critical" if restarts >= 5 else "warning",
                description=f"Pod {pod} has restarted {int(restarts)} times.",
                remediation_hint="Run k8s-assistant.py to diagnose. Consider: kubectl rollout undo or resource limit adjustment.",
            )
            anomalies.append(a)
            reporter.send_discord(DISCORD_WEBHOOK, a)

            # Trigger k8s-assistant for CrashLoopBackOff diagnosis
            if restarts >= 5:
                log.info("High restart count on %s — triggering k8s-assistant", pod)
                _trigger_k8s_assistant(pod, NAMESPACE)

    log.info("Detection complete. %d anomaly(ies) found.", len(anomalies))

    # Write JSON output for external consumption
    output_path = os.environ.get("ANOMALY_OUTPUT_PATH", "/tmp/anomalies.json")
    with open(output_path, "w") as f:
        json.dump([asdict(a) for a in anomalies], f, indent=2)

    return anomalies


def _trigger_k8s_assistant(pod: str, namespace: str) -> None:
    """Call k8s-assistant.py for deep diagnosis of a specific pod."""
    script = os.environ.get("K8S_ASSISTANT_PATH", "/app/k8s-assistant.py")
    if not os.path.exists(script):
        log.debug("k8s-assistant not found at %s, skipping", script)
        return
    try:
        subprocess.Popen(
            [sys.executable, script, "--pod", pod, "--namespace", namespace, "--analyse", "--llm", "ollama"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
    except Exception as e:
        log.warning("Could not trigger k8s-assistant: %s", e)


if __name__ == "__main__":
    run_detection()
