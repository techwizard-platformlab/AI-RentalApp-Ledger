# Architecture — rentalAppLedger Platform

## System overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        GitHub Repository                            │
│  Infra (Terraform) + GitOps (ArgoCD) + App manifests (Kustomize)   │
└────────────────┬─────────────────────────────────────────┬──────────┘
                 │ GitHub Actions                           │ ArgoCD sync
                 ▼                                         ▼
┌────────────────────────────┐           ┌────────────────────────────┐
│       Azure Stack          │           │       GCP Stack             │
│  AKS + ACR + Key Vault     │           │  GKE + Artifact Registry   │
│  PostgreSQL Flexible       │           │  Cloud SQL + Secret Manager │
└──────────────┬─────────────┘           └──────────────┬─────────────┘
               │                                         │
               ▼                                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster (AKS / GKE)                    │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  Istio Service Mesh (istio-system)                          │    │
│  │  Ingress Gateway → VirtualServices → DestinationRules       │    │
│  └────────────────────────────┬────────────────────────────────┘    │
│                               │                                      │
│  ┌────────────────────────────▼───────────────────────────────┐     │
│  │  rental-{env} namespace                                     │     │
│  │  ┌───────────┐  ┌───────────────┐  ┌───────────────────┐  │     │
│  │  │ API       │  │ Rental        │  │ Ledger            │  │     │
│  │  │ Gateway   │  │ Service       │  │ Service           │  │     │
│  │  │ :80       │  │ :8001         │  │ :8002             │  │     │
│  │  └───────────┘  └───────────────┘  └───────────────────┘  │     │
│  │  ┌───────────────────┐  ┌──────────────────────────────┐  │     │
│  │  │ Notification      │  │ RAG API (FastAPI)             │  │     │
│  │  │ Service :8003     │  │ :8080  ChromaDB  OpenAI       │  │     │
│  │  └───────────────────┘  └──────────────────────────────┘  │     │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────┐    │
│  │ ArgoCD (argocd)  │  │ Monitoring       │  │ External       │    │
│  │ GitOps operator  │  │ Prometheus       │  │ Secrets (ESO)  │    │
│  │                  │  │ Grafana          │  │ Key Vault /    │    │
│  │                  │  │ Alertmanager     │  │ Secret Manager │    │
│  └──────────────────┘  └──────────────────┘  └────────────────┘    │
└──────────────────────────────────────────────────────────────────────┘
```

## CI/CD pipeline flow

```
Developer push / PR
        │
        ├─► k8s-validate.yml    ─► kubeconform schema validation
        ├─► ci-build.yml        ─► OPA policy lint + Trivy scan
        ├─► cost-check.yml      ─► Infracost budget check ($22/month)
        └─► terraform.yml       ─► Plan preview + PR comment
                │
                │ (manual workflow_dispatch: action=apply)
                ▼
        terraform apply
                │
                ▼
        argocd-bootstrap.yml   ─► ArgoCD install / upgrade
                │
                ▼
        ci-rag-api.yml         ─► Build + push RAG API image
                │
                ▼
        ArgoCD auto-sync       ─► kustomize overlay deployed to cluster
                │
                ▼
        ArgoCD PostSync hook   ─► validate_deployment.sh
                │
                ▼
        qa-validate.yml        ─► BDD tests (Behave)
```

## GitOps deployment model

```
Git commit
    │
    ▼
ArgoCD detects change
    │
    ├─► App source: platform/kubernetes/overlays/{env}/
    │   (kustomize — Deployment, Service, ConfigMap, ExternalSecret)
    │
    ├─► Add-ons source: Helm charts from upstream registries
    │   ├── istio/base, istio/istiod, istio/gateway  (istio-release storage)
    │   └── kube-prometheus-stack  (prometheus-community)
    │
    └─► Sync → cluster state matches git state
```

## Security model

```
GitHub Actions
    │ OIDC token (short-lived, per-run)
    ▼
Azure AD / GCP Workload Identity
    │ exchange for cloud credential
    ▼
Managed Identity / Service Account
    │ reads secrets
    ▼
Key Vault / Secret Manager
    │ ESO syncs secrets to cluster
    ▼
Kubernetes Secrets (in-cluster)
    │ mounted as env vars / files
    ▼
Application pods
```

No long-lived credentials anywhere. All access is OIDC-federated and expires at run end.

## Environments

| Environment | Purpose | Auto-sync | Approval required |
|------------|---------|-----------|-------------------|
| dev | Local development + feature testing | Yes | No |
| qa | Integration testing + stakeholder review | No | No |
| uat | User acceptance testing | No | Yes |
| prod | Production | No | Yes (multi-reviewer) |

## Cost management

The **deploy-destroy** pattern minimizes cloud costs:

```
Session start:
  .github/scripts/deploy-compute.sh azure dev   ← creates AKS + VNet

Work session (3–4 hrs/day)

Session end:
  .github/scripts/destroy-compute.sh azure dev  ← destroys AKS + VNet
                                                    keeps: ACR, SQL, KV

Monthly estimate: ~$22 (88 hrs × compute rate)
OPA enforcement: deny > $22/month | warn > $15/month
```

## Network topology

```
Internet
    │
    ▼
Istio IngressGateway (LoadBalancer)
    │  routes via VirtualService rules
    ├─► /           → frontend (static)
    ├─► /api/v1/    → api-gateway
    └─► /rag/       → rental-rag-api

Within cluster (mTLS via Istio):
  api-gateway → rental-service   :8001
              → ledger-service   :8002
              → notification-service :8003
              → rental-rag-api   :8080
```

## Observability stack

```
Cluster metrics ──► Prometheus ──► Alertmanager ──► Discord / Email
                         │
                         ▼
                    Grafana (dashboards)
                         │
                    Custom dashboards:
                    - Rental operations
                    - RAG query latency
                    - Istio mesh metrics
                    - Cost tracking
```
