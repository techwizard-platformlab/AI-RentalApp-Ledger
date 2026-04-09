# Istio Service Mesh — rentalAppLedger

## Install (minimal profile for dev constraints)

```bash
# Download istioctl
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.20.0 sh -
export PATH=$PWD/istio-1.20.0/bin:$PATH

# Install minimal profile (istiod + ingress-gateway only, no egress)
istioctl install --set profile=minimal -y

# Enable sidecar injection for rental-dev namespace
kubectl label namespace rental-dev istio-injection=enabled
```

## Directory Structure

```
istio/
├── peer-auth.yaml              # STRICT mTLS namespace-wide + health check exceptions
├── gateway.yaml                # Ingress Gateway + rate limiting EnvoyFilter
├── destination-rules/
│   ├── api-gateway-dr.yaml
│   ├── rental-service-dr.yaml
│   ├── ledger-service-dr.yaml
│   └── notification-service-dr.yaml
├── virtual-services/
│   ├── api-gateway-vs.yaml     # External routing + canary placeholder
│   ├── rental-service-vs.yaml  # Retries, timeout, fault injection placeholder
│   └── ledger-service-vs.yaml
├── authorization-policies/
│   ├── default-deny.yaml       # Deny all by default
│   └── allow-policies.yaml     # Explicit allow rules per service
└── README.md
```

## Apply All Manifests

```bash
kubectl apply -f istio/peer-auth.yaml
kubectl apply -f istio/gateway.yaml
kubectl apply -f istio/destination-rules/
kubectl apply -f istio/virtual-services/
kubectl apply -f istio/authorization-policies/
```

## Observability

- **Prometheus**: Sidecar metrics auto-scraped via `prometheus.io/scrape` annotations
- **Jaeger tracing**: 10% sampling rate (dev cost saving)
  ```bash
  kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/jaeger.yaml
  ```
- **Kiali**: Service topology dashboard
  ```bash
  kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml
  ```

## Canary Deployment

To split traffic 90/10 between v1 and v2 of rental-service:
1. Deploy v2 Deployment with label `version: "2.0.0"`
2. Uncomment the `v2` block in `virtual-services/rental-service-vs.yaml`
3. `kubectl apply -f istio/virtual-services/rental-service-vs.yaml`
