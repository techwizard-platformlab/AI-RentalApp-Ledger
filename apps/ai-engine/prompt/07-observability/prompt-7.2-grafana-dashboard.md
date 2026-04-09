# Prompt 7.2 - Grafana: Custom Dashboard JSON for rentalAppLedger

```
Act as a Grafana expert. Generate dashboard JSON for rentalAppLedger.

CONTEXT:
- Data source: Prometheus (kube-prometheus-stack)
- App: FastAPI microservices (api-gateway, rental-service, ledger-service)
- Metrics: exposed via prometheus_fastapi_instrumentator
- Node: NodeExporter metrics available

TASK:
Generate Grafana dashboard JSON (importable via ConfigMap):

### Dashboard: rentalapp-slo-dashboard.json

#### Row 1: Service Health
- Stat panel: API Gateway up/down (green/red)
- Stat panel: Current RPS (requests per second)
- Stat panel: Error rate % (last 5 min)
- Gauge: P95 latency (0-2000ms range)

#### Row 2: Request Volume
- Time series: HTTP requests/second by service (stacked)
- Time series: HTTP 5xx errors/second by service
- Bar chart: Top 5 slowest endpoints (p95)

#### Row 3: Pod Health
- Table: Pod name | Restarts | Status | CPU | Memory
- Time series: Pod restart count over 1 hour
- Stat: Total pod count per namespace

#### Row 4: Resource Usage
- Time series: CPU usage % per service
- Time series: Memory usage % per service
- Gauge: Node CPU utilisation (all nodes)
- Gauge: Node memory utilisation (all nodes)

#### Variables (template):
- $namespace: rental-dev / rental-qa
- $service: all / api-gateway / rental-service / ledger-service
- $interval: 1m / 5m / 15m

ALSO INCLUDE:
- How to load dashboard via ConfigMap in Grafana sidecar
- Annotation: ArgoCD deployment markers on all time series panels

OUTPUT: Complete dashboard JSON + ConfigMap YAML wrapper
```
