# Prompt 5.1 - Istio: mTLS, Traffic Routing, Ingress Gateway

```
Act as a Senior Platform Engineer specialising in Istio Service Mesh.

CONTEXT:
- Kubernetes clusters: AKS + GKE
- Services: api-gateway, rental-service, ledger-service, notification-service
- Namespace: rental-dev (Istio injection enabled)
- Goal: mTLS between all services, traffic management, observability

TASK:
Generate complete Istio configuration:

### 1. Installation (minimal for dev constraints)
- Istio profile: minimal (reduced resource usage for KodeKloud)
- Components: istiod, ingress-gateway only (no egress-gateway - cost saving)
- Enable sidecar injection: namespace label only

### 2. PeerAuthentication (mTLS)
- Namespace-wide STRICT mTLS for rental-dev
- If health checks require PERMISSIVE, use workload-level PeerAuthentication

### 3. DestinationRule for each service
- TLS mode: ISTIO_MUTUAL
- Connection pool: max 10 connections (dev constraint)
- Outlier detection: 1 consecutive error -> eject for 30s

### 4. VirtualService for traffic routing
- api-gateway -> rental-service (weight 100 in dev)
- Canary ready: split traffic 90/10 (add new version subset)
- Retry: 3 retries, 2s timeout on rental-service calls
- Fault injection placeholder (for chaos testing)

### 5. Ingress Gateway
- External LoadBalancer
- TLS termination at gateway (cert-manager TLS secret)
- Route: /api/* -> api-gateway VirtualService
- Rate limiting: 100 req/min per source IP (EnvoyFilter placeholder)

### 6. AuthorizationPolicy
- Default: deny all in rental-dev namespace
- Allow: api-gateway -> rental-service (specific paths only)
- Allow: api-gateway -> ledger-service (specific paths only)
- Allow: any -> notification-service (internal notification calls)

### 7. Observability Integration
- Enable Prometheus metrics scraping (annotations)
- Jaeger tracing: sampling rate 10% (dev cost saving)
- Kiali dashboard: ServiceMonitor for ArgoCD to manage

OUTPUT: All Istio YAML files with folder structure:
istio/
|-- peer-auth.yaml
|-- destination-rules/
|-- virtual-services/
|-- gateway.yaml
|-- authorization-policies/
|-- README.md
```
