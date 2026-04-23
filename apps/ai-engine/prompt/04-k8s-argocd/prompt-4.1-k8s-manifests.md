# Prompt 4.1 - Kubernetes: Manifests for rentalAppLedger Microservices

```
Act as a Senior Platform Engineer specialising in Kubernetes.

CONTEXT:
- App: rentalAppLedger (Python FastAPI microservices)
- Services: api-gateway, rental-service, ledger-service, notification-service
- Cluster: AKS (Azure) and GKE (GCP) - same manifests work on both
- Resource budget: low (KodeKloud limits - B2s nodes, 2 vCPUs, 4 GB RAM per node)
- Images from ACR / GCP Artifact Registry

TASK:
Generate Kubernetes manifests for all 4 services:

### For EACH service generate:

#### deployment.yaml
- replicas: 1 (dev), 2 (qa)
- image: placeholder ({registry}/{service}:{tag})
- Resources:
  * requests: cpu: 100m, memory: 128Mi
  * limits:   cpu: 500m, memory: 512Mi
- Readiness probe: HTTP /health, initialDelaySeconds: 10, periodSeconds: 5
- Liveness probe:  HTTP /health, initialDelaySeconds: 30, periodSeconds: 10
- Environment variables from ConfigMap + Secrets
- SecurityContext: runAsNonRoot: true, readOnlyRootFilesystem: true

#### service.yaml
- api-gateway: type: LoadBalancer (external)
- Others: type: ClusterIP (internal only)

#### ingress.yaml (api-gateway only)
- Annotations for nginx ingress (if using nginx; otherwise adapt to your controller)
- TLS: cert-manager placeholder
- Path-based routing: /api/rental/* -> rental-service, /api/ledger/* -> ledger-service

#### configmap.yaml
- App config: LOG_LEVEL, DB_HOST, ENVIRONMENT

#### horizontalpodautoscaler.yaml
- Min: 1, Max: 3 (dev)
- QA overlay should patch min to 2

#### namespace.yaml
- Namespace: rental-dev, rental-qa
- Labels: environment, project

ALSO GENERATE:
- kustomization.yaml for dev overlay and qa overlay
- Directory structure:
  platform/kubernetes/
  |-- base/
  |   |-- api-gateway/
  |   |-- rental-service/
  |   |-- ledger-service/
  |   |-- notification-service/
  |-- overlays/
      |-- dev/
      |-- qa/

OUTPUT: All YAML files, production-ready with comments
```
