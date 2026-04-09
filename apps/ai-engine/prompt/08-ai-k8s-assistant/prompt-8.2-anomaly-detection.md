# Prompt 8.2 - AI Anomaly Detection: Prometheus Metrics + Python

```
Act as a Python ML engineer specialising in time-series anomaly detection.

CONTEXT:
- Metrics: Prometheus (kube-prometheus-stack)
- App: rentalAppLedger microservices
- Goal: detect anomalies in real-time without GPU, using CPU-only free methods
- Deploy as: Kubernetes CronJob (runs every 5 minutes)

TASK:
Build anomaly_detector.py - Python-based anomaly detection:

### Method: Statistical (no ML model needed - free and fast)
- Use Z-score for point anomalies (CPU spikes, memory spikes)
- Use IQR for distribution anomalies (latency outliers)
- Use rolling average comparison for trend anomalies (gradual memory leak)

### Metrics to Monitor:
1. CPU usage per pod (container_cpu_usage_seconds_total)
2. Memory usage per pod (container_memory_working_set_bytes)
3. HTTP error rate (http_requests_total by status_code)
4. API latency p95 (http_request_duration_seconds)
5. Pod restart count (kube_pod_container_status_restarts_total)

### Code Structure:

```python
class PrometheusClient:
    def query_range(self, query: str, duration: str = "1h") -> pd.DataFrame
    def query_instant(self, query: str) -> dict

class AnomalyDetector:
    def detect_zscore(self, series: pd.Series, threshold: float = 3.0) -> list[Anomaly]
    def detect_iqr(self, series: pd.Series, multiplier: float = 1.5) -> list[Anomaly]
    def detect_trend(self, series: pd.Series, window: int = 10) -> list[Anomaly]

class AnomalyReporter:
    def format_discord_alert(self, anomaly: Anomaly) -> dict
    def send_discord(self, webhook_url: str, message: dict) -> None
    def log_to_prometheus(self, anomaly: Anomaly) -> None  # expose as custom metric
```

### Auto-Remediation Triggers:
- CrashLoopBackOff detected -> trigger k8s-assistant.py analyse
- Memory usage > 90% for 3 consecutive checks -> Discord alert + scale suggestion
- Error rate > 10% sustained 5 min -> Discord critical alert

### Kubernetes Deployment:
- CronJob: every 5 minutes
- ConfigMap: Prometheus URL, thresholds
- Secret: Discord webhook URL
- ServiceAccount: read-only Prometheus access

INCLUDE:
- requirements.txt (prometheus-api-client, pandas, scipy, requests)
- Kubernetes CronJob YAML
- Dockerfile (Python slim, non-root)
- Sample anomaly output JSON

OUTPUT: anomaly_detector.py (full) + k8s/ manifests + Dockerfile + README
```
