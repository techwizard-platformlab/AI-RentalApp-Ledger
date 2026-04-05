# Prompt 7.1 - Prometheus + Grafana: Full Stack Setup

```
Act as a Senior SRE specialising in Kubernetes observability.

CONTEXT:
- Kubernetes: AKS + GKE (install on both)
- App: rentalAppLedger (FastAPI microservices)
- Resources: constrained (KodeKloud B2s nodes, 2 vCPUs per node)
- Stack: kube-prometheus-stack (Helm)

TASK:
Generate complete observability setup:

### 1. kube-prometheus-stack Helm Values (helm/prometheus-values.yaml)
- Prometheus:
  * retention: 24h (dev cost saving - no persistent volume cost)
  * resources: requests cpu:100m memory:256Mi, limits cpu:500m memory:512Mi
  * scrapeInterval: 30s
  * ruleSelector: matchLabels app=rentalapp
- Grafana:
  * resources: requests cpu:50m memory:128Mi
  * persistence: disabled (dev)
  * admin password: from Kubernetes secret
  * dashboards: sidecar enabled (load from ConfigMaps)
- NodeExporter: enabled (all nodes)
- AlertManager: enabled (send to Discord webhook)
- Prometheus Operator: enabled

### 2. ServiceMonitors for rentalAppLedger
- One ServiceMonitor per microservice
- Scrape: /metrics endpoint, port 8000
- Labels: release=kube-prometheus-stack
- Interval: 30s

### 3. Alert Rules (PrometheusRule CRD)
#### alerts/pod-alerts.yaml
- HighCPU: pod cpu > 80% for 5 minutes -> Warning
- PodCrashLooping: kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} > 0 -> Critical
- PodRestartHigh: pod restarts > 3 in 10 minutes -> Warning
- PodOOMKilled: container killed by OOM -> Critical
- DeploymentReplicasMismatch: desired != available for 5 min -> Warning

#### alerts/api-alerts.yaml
- HighAPILatency: p95 > 2s for 5 min -> Warning
- HighErrorRate: 5xx/total > 5% for 2 min -> Critical
- APIDown: absent(up{job="api-gateway"}) for 1 min -> Critical

#### alerts/node-alerts.yaml
- NodeHighCPU: node_cpu_seconds > 85% for 5 min -> Warning
- NodeMemoryPressure: node_memory_MemAvailable < 10% -> Critical
- NodeDiskPressure: node_filesystem_avail < 15% -> Warning

### 4. Grafana Dashboard ConfigMaps
- Dashboard 1: rentalapp-overview
  * Pod count, restart count, CPU/memory per service
  * API request rate, error rate, p50/p95 latency
- Dashboard 2: node-overview
  * Node CPU, memory, disk, network per node
  * Pod scheduling pressure
- Dashboard 3: argocd-sync
  * Sync status per app, last sync time, health status

### 5. AlertManager Config (Discord + Email)
- Route: Critical -> Discord + Email
- Route: Warning -> Discord only
- Group wait: 30s, group interval: 5m, repeat interval: 4h

ALSO INCLUDE:
- FastAPI metrics instrumentation (prometheus_fastapi_instrumentator - 5 lines of code)
- How to port-forward Grafana for local access
- Prometheus query examples for each alert rule (use instrumentator metric names)

OUTPUT: All Helm values + YAML files:
monitoring/
|-- helm/
|   |-- prometheus-values.yaml
|-- servicemonitors/
|-- alerts/
|-- dashboards/
|-- alertmanager-config.yaml
```
