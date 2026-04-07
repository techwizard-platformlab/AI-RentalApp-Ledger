# rentalAppLedger — Architecture & Technical Reference

## Table of Contents

1. [Overview](#1-overview)
2. [Repository Structure](#2-repository-structure)
3. [Application Architecture](#3-application-architecture)
4. [Components](#4-components)
   - [4.1 RentalApp — Django REST API](#41-rentalapp--django-rest-api)
   - [4.2 API Gateway](#42-api-gateway)
   - [4.3 Rental Service](#43-rental-service)
   - [4.4 Ledger Service](#44-ledger-service)
   - [4.5 Notification Service](#45-notification-service)
   - [4.6 RAG AI Assistant](#46-rag-ai-assistant)
   - [4.7 K8s AI Assistant](#47-k8s-ai-assistant)
   - [4.8 Anomaly Detector](#48-anomaly-detector)
   - [4.9 Notification Watcher](#49-notification-watcher)
5. [Data Models](#5-data-models)
6. [Infrastructure (Azure)](#6-infrastructure-azure)
7. [GitOps & Deployment](#7-gitops--deployment)
8. [Observability](#8-observability)
9. [Security](#9-security)
10. [CI/CD Pipelines](#10-cicd-pipelines)
11. [Use Cases](#11-use-cases)
12. [Environment Variables Reference](#12-environment-variables-reference)
13. [Technology Stack](#13-technology-stack)

---

## 1. Overview

**rentalAppLedger** is a cloud-native, AI-augmented rental property management platform built for property owners, managers, and staff. It handles the full lifecycle of rental operations — from property onboarding and tenant management to rent collection, ledger tracking, and financial reporting.

### Key Capabilities

| Capability | Description |
|---|---|
| Multi-property management | Residential and commercial properties, units, tenants |
| Financial ledger | Rent, deposits, utilities, transactions with full audit trail |
| Document management | Agreements, KYC (Aadhar, PAN, GST), receipts, invoices |
| AI-powered assistance | Natural language Q&A over ledger data via RAG |
| Intelligent monitoring | Automatic anomaly detection, Discord/email alerting |
| GitOps deployment | ArgoCD-driven continuous delivery to AKS |
| Infrastructure as Code | Full Terraform automation for Azure (and GCP) |

---

## 2. Repository Structure

The project is split into two repositories with clearly separated concerns:

```
┌─────────────────────────────────┐    ┌─────────────────────────────────────┐
│  RentalApp-Build (App Repo)     │    │  AI-RentalApp-Ledger (Platform Repo) │
│                                 │    │                                      │
│  Django REST API                │    │  Terraform (Azure / GCP)             │
│  Business logic                 │    │  Kubernetes manifests (GitOps)       │
│  PostgreSQL models              │    │  ArgoCD configuration                │
│  CI: lint → test → Docker push  │    │  AI tools (RAG, anomaly, K8s-assist) │
│                                 │    │  Monitoring (Prometheus / Grafana)   │
│  Pushes image → ACR / DockerHub │    │  Notification system (Discord)       │
│  / Google AR (selectable)       │    │                                      │
└─────────────────────────────────┘    │  BDD/QA tests                        │
                                       │  OPA + Kyverno policies              │
                                       └─────────────────────────────────────┘
```

### AI-RentalApp-Ledger Directory Layout

```
AI-RentalApp-Ledger/
├── .github/workflows/       # CI/CD pipelines (Terraform, ArgoCD, QA, notify)
├── ai-tools/
│   ├── k8s-assistant/       # AI-powered pod diagnostics (Ollama / Groq / Claude)
│   └── anomaly-detector/    # Statistical anomaly detection (Z-score, IQR)
├── bootstrap/               # One-time cloud setup scripts + secrets management
├── gatekeeper/              # OPA Gatekeeper constraint templates
├── gitops/
│   ├── apps/                # ArgoCD Application + AppProject CRDs
│   ├── argocd/              # ArgoCD Helm install values
│   └── notifications/       # ArgoCD notification triggers & templates
├── istio/                   # Service mesh (mTLS, traffic policies, gateway)
├── k8s/
│   ├── base/                # Kustomize base manifests per service
│   └── overlays/            # Environment overlays (dev, qa)
├── kyverno/                 # Admission control policies + exceptions
├── monitoring/              # Prometheus Helm values, alert rules, dashboards
├── notify/                  # Discord notifier + K8s event watcher
├── policy/                  # OPA/Rego cost and security policies
├── qa/                      # BDD tests (Behave + pytest)
├── rag/                     # RAG API and ChromaDB integration
└── terraform/
    ├── azure/               # Azure modules + dev/qa environments
    └── gcp/                 # GCP modules (GKE)
```

---

## 3. Application Architecture

```
                           ┌─────────────────────────────────────────────────┐
                           │              Azure Kubernetes Service (AKS)      │
                           │  Namespace: rental-dev                           │
                           │                                                  │
  Browser / Mobile  ──────►│  LoadBalancer                                   │
                           │       │                                          │
                           │       ▼                                          │
                           │  ┌──────────────┐                               │
                           │  │  API Gateway │  :80 → :8000                  │
                           │  │  (Django)    │                               │
                           │  └──────┬───────┘                               │
                           │         │  ClusterIP calls                       │
                           │    ┌────┴──────────────────┐                    │
                           │    ▼                        ▼                    │
                           │  ┌──────────────┐  ┌──────────────────┐        │
                           │  │Rental Service│  │  Ledger Service   │        │
                           │  │   :8001      │  │     :8002         │        │
                           │  └──────────────┘  └──────────────────┘        │
                           │                                                  │
                           │  ┌──────────────────┐  ┌──────────────────┐    │
                           │  │Notification Svc  │  │   RAG API        │    │
                           │  │   :8003          │  │   :8004          │    │
                           │  └──────────────────┘  └──────────────────┘    │
                           │                                                  │
                           │  ┌───────────────────────────────────────────┐  │
                           │  │  Istio Service Mesh (mTLS between all svcs)│  │
                           │  └───────────────────────────────────────────┘  │
                           └─────────────────────────────────────────────────┘
                                         │
                           ┌─────────────┴──────────────────────┐
                           │         Azure Resources             │
                           │  ┌─────────┐  ┌──────────────────┐ │
                           │  │   ACR   │  │   Key Vault       │ │
                           │  │ (images)│  │   (secrets)       │ │
                           │  └─────────┘  └──────────────────┘ │
                           │  ┌─────────┐  ┌──────────────────┐ │
                           │  │Postgres │  │ Storage Account  │ │
                           │  │  (DB)   │  │ (uploads/backups)│ │
                           │  └─────────┘  └──────────────────┘ │
                           └────────────────────────────────────┘

                    ┌─────────────────────────────────────┐
                    │       GitOps & CI/CD Flow            │
                    │                                      │
                    │  Developer → GitHub Push             │
                    │       → CI: lint/test/build          │
                    │       → Docker image → ACR           │
                    │       → ArgoCD detects new image     │
                    │       → Auto-sync → AKS deploy       │
                    └─────────────────────────────────────┘
```

---

## 4. Components

### 4.1 RentalApp — Django REST API

The core business logic service. Built with Django 5.2 + Django REST Framework.

**Repository:** `RentalApp-Build`
**Runtime:** Python 3.12, Gunicorn, Alpine Linux
**Port:** 8000

#### API Endpoints

| Prefix | Module | Description |
|---|---|---|
| `GET /healthz` | — | Kubernetes liveness / readiness probe |
| `/admin/` | Django Admin | Management UI |
| `/api/v1/` | common | Auth, users, tenants, transactions, documents, ledger |
| `/api/v1/residential/` | residential | Residential tenant profiles |
| `/api/v1/commercial/` | commercial | Commercial tenant profiles |
| `/api/v1/owner/` | owner | Owner dashboard, reports |

#### Authentication & Security

- **Token Authentication** — DRF `TokenAuthentication` (Bearer token in header)
- **Rate Limiting** — 60 req/min anonymous, 1000 req/day users, 5 req/min auth endpoints
- **CORS** — Driven by `CORS_ALLOWED_ORIGINS` env var in production
- **HTTPS** — SSL termination at AKS load balancer; `SESSION_COOKIE_SECURE=True` in prod
- **HSTS** — Configurable via `SECURE_HSTS_SECONDS` env var

---

### 4.2 API Gateway

The external-facing entry point. Proxies requests to downstream services.

**Type:** LoadBalancer (external IP)
**Port:** 80 → 8000
**Probes:** `GET /health`, `GET /ready`
**Resources:** CPU 100m–500m, Memory 128Mi–512Mi

Routes:
- `/api/v1/rentals/*` → Rental Service (:8001)
- `/api/v1/ledger/*` → Ledger Service (:8002)
- `/metrics` → Prometheus scrape endpoint

---

### 4.3 Rental Service

Manages rental agreements, unit availability, and tenancy lifecycle.

**Type:** ClusterIP (internal only)
**Port:** 8001
**Responsibilities:**
- Create / update / terminate lease agreements
- Track unit occupancy status (vacant, occupied, maintenance)
- Manage rent amounts, billing cycles, deposit tracking

---

### 4.4 Ledger Service

Financial record-keeping and reporting engine.

**Type:** ClusterIP (internal only)
**Port:** 8002
**Responsibilities:**
- Rent ledger entries (monthly, due vs paid)
- Deposit ledger (received, adjusted, refunded)
- Transaction history (income, expenses, categories)
- Receipt generation
- Financial reports (profit/loss, tax, occupancy)

---

### 4.5 Notification Service

Handles outbound communication — email receipts, payment reminders, alerts.

**Type:** ClusterIP (internal only)
**Port:** 8003
**Channels:** Email (SMTP/Gmail/Outlook), Discord webhook

---

### 4.6 RAG AI Assistant

Natural language query interface over ledger data. Allows users to ask plain-English questions about their rental portfolio.

**Type:** ClusterIP (internal only)
**Port:** 8004
**Stack:** FastAPI + ChromaDB (vector store) + sentence-transformers

#### LLM Provider Priority (cost-optimized)
```
1. Ollama (local, free)       — preferred in cluster
2. Groq API (free tier)       — fallback
3. Claude Haiku (Anthropic)   — final fallback
```

#### Example Queries
- *"Which tenants have overdue payments this month?"*
- *"Show me all transactions for Unit 2B in February"*
- *"What is the total unpaid rent across all properties?"*
- *"Which properties have the highest vacancy rate?"*

#### API
```
POST /query          { "question": "...", "user_id": "..." }
GET  /health
GET  /stats          # Documents indexed, query count, avg latency
```

**Rate Limiting:** 10 queries/minute per user
**Security:** Prompt injection detection (blocks SQL/system commands in responses)

---

### 4.7 K8s AI Assistant

AI-powered Kubernetes diagnostics tool. Analyzes pod logs, identifies root causes, and suggests remediation commands.

**Execution:** CLI tool + K8s CronJob
**File:** `ai-tools/k8s-assistant/k8s-assistant.py`

#### Capabilities

| Command | Description |
|---|---|
| `--namespace rental-dev --watch` | Stream and analyze pod events in real-time |
| `--pod <name> --analyse` | Deep-dive analysis of a specific pod's logs |
| `--namespace rental-dev --auto-fix --dry-run` | Suggest kubectl remediation commands |

#### Analysis Output (per pod)
```
pod_name          → which pod
error_type        → CrashLoopBackOff / OOMKilled / ImagePullBackOff / etc.
root_cause        → human-readable diagnosis
severity          → critical / warning / info
suggested_fixes   → list of recommended actions
kubectl_commands  → copy-paste ready commands
```

---

### 4.8 Anomaly Detector

Statistical time-series anomaly detection over Prometheus metrics. Runs every 5 minutes as a Kubernetes CronJob.

**File:** `ai-tools/anomaly-detector/anomaly_detector.py`
**Data Source:** Prometheus (`kube-prometheus-stack-prometheus.monitoring:9090`)

#### Detection Methods

| Method | Detects | Threshold |
|---|---|---|
| Z-score | Point anomalies (sudden spikes) | 3.0 standard deviations |
| IQR | Distribution anomalies (outliers) | 1.5× interquartile range |
| Rolling window | Trend anomalies (gradual drift) | Window size 10 |

#### Monitored Metrics

| Metric | Alert Threshold |
|---|---|
| CPU usage % | Z-score > 3.0 |
| Memory usage % | > 90% |
| HTTP error rate | > 10% |
| Request latency | IQR outlier |
| Memory leak trend | Sustained rolling increase |

**Alert Output:** Discord webhook with severity, metric, value, affected pod

---

### 4.9 Notification Watcher

Always-on Kubernetes event listener. Watches for pod failure events in `rental-dev` and `rental-qa` namespaces and sends instant Discord notifications.

**File:** `notify/k8s_event_watcher.py`
**Execution:** Kubernetes Deployment (always running)

#### Watched Event Reasons
- `BackOff` — container restart loop
- `OOMKilling` — out of memory kill
- `Failed` — pod failed to start
- `FailedScheduling` — no node available
- `Killing` — pod being terminated

#### Discord Notification Format
- Pod restart: pod name, namespace, restart count, reason
- OOM kill: pod name, memory limit, requested memory
- Deployment status: desired vs ready vs updated replicas

---

## 5. Data Models

### Core Models (common app)

```
User (CustomUser)
 └── role: owner | manager | staff
 └── email (unique login)

Property
 ├── type: commercial | residential | mixed
 ├── owner (FK → User)
 └── address, city, state, pincode

Unit
 ├── property (FK → Property)
 ├── unit_code (unique per property)
 └── status: vacant | occupied | maintenance

Tenant
 ├── unit (FK → Unit)
 ├── type: business | individual
 ├── rent_amount, deposit_amount
 ├── billing_cycle: monthly | quarterly | annual
 └── status: active | inactive | vacated

Transaction
 ├── property / unit / tenant (FK)
 ├── type: income | expense
 ├── category: rent | deposit | maintenance | tax | utility | ...
 └── payment_method, payment_date, status

RentLedger
 ├── tenant (FK → Tenant)
 ├── period (month + year, unique per tenant)
 ├── due_amount, paid_amount
 └── status: pending | partial | paid | overdue

DepositLedger
 ├── tenant (FK → Tenant)
 ├── entry_type: received | adjusted | refunded
 └── linked_transaction (FK → Transaction)

UtilityRecord
 ├── property / unit (FK)
 ├── type: electricity | water | gas | common_area
 ├── billing_model: metered | fixed | shared
 └── meter readings, payment status

Document
 ├── property / unit / tenant (FK)
 ├── document_type: agreement | aadhar | pan | gst | receipt | invoice | tax | bill
 └── file (upload)

Receipt
 └── transaction (OneToOne)
 └── receipt_number (unique)

ActivityLog
 ├── user (FK → User)
 ├── action: login | logout | create | update | delete | view | payment | export
 └── resource, IP address, timestamp
```

### Extended Profiles

```
ResidentialTenantProfile (OneToOne → Tenant)
 └── aadhar_number, pan_number, occupation, family_size, emergency_contact

CommercialTenantProfile (OneToOne → Tenant)
 └── legal_name, gst_number, business_license, contact_person, registered_address

ReportExport (owner app)
 └── report_type: profit_loss | tax | occupancy
 └── date_range, generation_status, file
```

---

## 6. Infrastructure (Azure)

All infrastructure is managed via Terraform and deployed to Azure using the KodeKloud lab environment.

### Azure Resources

| Resource | Module | Purpose |
|---|---|---|
| AKS Cluster | `modules/aks` | Kubernetes cluster (Standard_D2s_v3 nodes) |
| ACR | `modules/acr` | Container registry for Docker images |
| Virtual Network | `modules/vnet` | Private networking (10.0.0.0/16) |
| Subnet | `modules/subnet` | AKS node subnet |
| Key Vault | `modules/keyvault` | Secrets management (RBAC-enabled) |
| Storage Account | `modules/storage_account` | Uploads, backups, Terraform state |
| Load Balancer | `modules/load_balancer` | Public IP for external traffic |
| Security Group | `modules/security_group` | Network access control |

### Network Design

```
VNet: 10.0.0.0/16
  └── AKS Subnet: 10.0.1.0/24  (nodes)

K8s Service CIDR: 10.1.0.0/16  (pods, separate from VNet)
K8s DNS:          10.1.0.10
```

### Terraform Environments

```
terraform/azure/environments/
├── dev/   ← KodeKloud lab (1-node AKS, Basic ACR, Standard KeyVault)
└── qa/    ← QA environment (higher resources)
```

### KodeKloud Constraints

> These are hard platform limits in the KodeKloud lab environment:

- No `Microsoft.Authorization/roleAssignments` (403 forbidden)
- No new resource groups (use pre-assigned RG)
- Only allowed VM sizes: `Standard_D2s_v3`, `Standard_K8S2_v1`, `Standard_K8S_v1`
- No WAF policies, no container insights
- Service Principal client secret expires each lab session — must regenerate
- `resource_provider_registrations = "none"` required (cannot register providers)

---

## 7. GitOps & Deployment

### Deployment Flow

```
Developer commits code
        │
        ▼
RentalApp-Build CI (GitHub Actions)
  1. Pylint + Bandit + Django checks
  2. pytest + coverage
  3. SonarQube scan
  4. Docker build → push to selected registry (ACR / DockerHub / Google AR)
        │
        ▼
ArgoCD Image Updater (polls ACR)
  Detects new image tag
  Writes updated tag back to git (AI-RentalApp-Ledger/k8s/overlays/dev/)
        │
        ▼
ArgoCD Auto-Sync
  Compares git state vs cluster state
  Applies diff to AKS (prune=true, selfHeal=true)
        │
        ▼
Pods rolling-updated on AKS
  Readiness probe passes → traffic routed to new pods
  Old pods terminated
        │
        ▼
Discord notification → #deployments
```

### ArgoCD Configuration

**AppProject `rental-ledger`:**
- Allowed source: `github.com/Ramprasath26/AI-RentalApp-Ledger`
- Allowed destinations: `rental-dev`, `rental-qa` namespaces (AKS + GKE)
- Allowed resources: Namespace, Deployment, Service, Ingress, HPA, ConfigMap

**Application `rental-ledger-dev`:**
- Source path: `k8s/overlays/dev`
- Auto-sync: enabled (prune + self-heal)
- Retry: 3 attempts, exponential backoff (5s → 1m)
- Revision history: 5 (for rollback)

### Kustomize Overlays

```
k8s/base/              ← shared across all environments
  api-gateway/
  rental-service/
  ledger-service/
  notification-service/

k8s/overlays/
  dev/    ← replicas=1, dev labels
  qa/     ← replicas=2, qa labels
```

---

## 8. Observability

### Metrics (Prometheus + Grafana)

| Component | Scrape Port | Metrics Path |
|---|---|---|
| api-gateway | 8000 | /metrics |
| rental-service | 8001 | /metrics |
| ledger-service | 8002 | /metrics |
| notification-service | 8003 | /metrics |
| RAG API | 8004 | /metrics |

**Custom RAG Metrics:**
- `rag_query_total` — query count by status (success/error)
- `rag_query_duration_seconds` — latency histogram (0.1s → 10s buckets)
- `rag_context_retrieved` — documents retrieved per query
- `rag_llm_tokens_used_total` — estimated token consumption

**Prometheus Config (dev):**
- Retention: 24 hours
- Scrape interval: 30s
- Evaluation interval: 30s

### Alerts

| Alert | Condition | Severity |
|---|---|---|
| PodCrashLooping | restarts > 5 in 5 min | Critical |
| PodOOMKilled | OOM event | Critical |
| HighErrorRate | HTTP 5xx > 10% | Warning |
| HighLatency | p99 > 2s | Warning |
| HighMemoryUsage | > 90% limit | Warning |
| NodeNotReady | node unavailable | Critical |

### Notification Channels

- **Discord** — real-time pod events, anomalies, deployments
- **Email** — payment receipts, overdue reminders (SMTP)
- **GitHub Actions Summary** — CI/CD results after each workflow run

---

## 9. Security

### Layers of Security

```
Internet
  └── Azure Load Balancer (TLS termination)
        └── AKS Ingress Controller
              └── Istio Gateway (mTLS between services)
                    └── Kyverno (admission policies)
                          └── OPA Gatekeeper (constraint enforcement)
                                └── Pod Security Context
                                      └── Django (token auth + rate limiting)
```

### Istio Service Mesh
- **mTLS** — all service-to-service traffic encrypted and mutually authenticated
- **Authorization Policies** — allowlist-based (default deny, explicit allow)
- **Destination Rules** — circuit breaker, retries, load balancing per service
- **Virtual Services** — traffic routing, canary releases, fault injection for testing

### Kyverno Policies
- `disallow-privileged` — no privileged containers
- `require-resource-limits` — CPU and memory limits mandatory
- `restrict-registries` — only ACR images allowed
- `require-labels` — all pods must have `app` and `environment` labels
- `disallow-latest-tag` — image tag `latest` blocked in QA/prod
- `generate-networkpolicy` — auto-create NetworkPolicy on namespace creation
- `pod-security` — enforce restricted pod security standards

### OPA/Rego Policies (Terraform)
- Cost guardrails — alert on infra changes above budget threshold
- Region restrictions — Azure eastus only for KodeKloud
- VM size allowlist — only approved sizes can be used

### Application Security
- **Token Authentication** — stateless Bearer tokens
- **Rate Limiting** — per-user/per-endpoint throttling
- **CORS** — explicit origin allowlist
- **HTTPS** — enforced via load balancer, `SESSION_COOKIE_SECURE=True`
- **Input Validation** — DRF serializers on all endpoints
- **SQL Injection** — Django ORM prevents raw SQL by default
- **SAST** — Bandit scans every CI run (medium+ severity)
- **Container CVE Scan** — Trivy on every Docker image push
- **Dependency Review** — GitHub Dependabot on both repos

### Secrets Management
- **Azure Key Vault** — production secrets (RBAC-enabled, soft delete)
- **GitHub Actions Secrets** — CI/CD credentials (encrypted via PyNaCl SealedBox)
- **bootstrap/.env** — gitignored, never committed

---

## 10. CI/CD Pipelines

### RentalApp-Build Workflows

```
ci.yml (workflow_dispatch)
  Input: registry = dockerhub (default) | acr | gcr | all

  Job 1: lint-and-security
    ├── actions/checkout
    ├── actions/setup-python@3.12
    ├── pip install requirements + dev tools
    ├── pylint (--fail-under=7.0)
    ├── bandit (SAST, medium+ severity)
    ├── python manage.py check --deploy --fail-level ERROR
    └── pytest --cov (coverage.xml)

  Job 2: sonarqube (needs: lint-and-security)
    └── SonarSource/sonarqube-scan-action@v6 (non-blocking)

  Job 3: image-meta (needs: sonarqube)
    └── compute short_sha (8 chars) + tags_suffix (branch-sha)

  Job 4: push-dockerhub  [if registry == dockerhub | all]
    ├── docker/build-push-action@v6 (linux/amd64 + linux/arm64)
    └── Push: :latest  :branch-sha

  Job 5: push-acr  [if registry == acr | all]
    ├── az login --service-principal → az acr login
    ├── docker/build-push-action@v6
    ├── Push: :latest  :sha  :branch-sha
    ├── cosign sign (keyless OIDC — id-token: write)
    └── acr purge — keep last 5 versioned tags + prune untagged

  Job 6: push-gcr  [if registry == gcr | all]
    ├── google-github-actions/auth (OIDC)
    ├── gcloud auth configure-docker <region>-docker.pkg.dev
    ├── docker/build-push-action@v6 (linux/amd64 + linux/arm64)
    ├── Push: :latest  :sha  :branch-sha
    └── cosign sign (keyless OIDC — id-token: write)

  Job 7: summary (always)
    └── Print per-registry status table to GitHub Step Summary
```

**Tag lifecycle (ACR):**

| Tag type | Pattern | Max kept |
|----------|---------|----------|
| Short-SHA | `[0-9a-f]{8}` | 5 |
| Branch-SHA | `.*-[0-9a-f]{8}` | 5 |
| `latest` | exact | always (never purged) |
| `buildcache` | exact | always (build layer cache) |
| Untagged (cosign sigs, etc.) | — | purged after 1 day |

### AI-RentalApp-Ledger Workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| `ci-build.yml` | manual | Terraform fmt, OPA lint, K8s manifest validation, Trivy FS scan |
| `terraform.yml` | manual | Plan / apply / destroy on Azure or GCP |
| `argocd-bootstrap.yml` | manual | Install ArgoCD on AKS, apply AppProject + Application |
| `cost-check.yml` | manual | Infracost estimate + OPA cost guardrail |
| `qa-validate.yml` | manual | BDD tests against live cluster |
| `terraform-schedule.yml` | manual | Scheduled destroy/recreate for KodeKloud sessions |
| `notify.yml` | workflow_call | Reusable Discord + email notification |

> All auto-triggers (push, pull_request, schedule) are currently commented out during testing.

---

## 11. Use Cases

### UC-01: Owner Onboards a New Property
1. Owner logs in → POST `/api/v1/` creates Property record
2. Owner adds Units → POST `/api/v1/` creates Unit records (status: vacant)
3. Owner uploads property documents (title deed, tax certificate)
4. Vacancy visible in owner dashboard

### UC-02: Tenant Moves In
1. Manager creates Tenant record linked to Unit
2. Unit status changes: `vacant → occupied`
3. ResidentialTenantProfile or CommercialTenantProfile created
4. Agreement document uploaded (PDF)
5. DepositLedger entry created (received)
6. Receipt generated and emailed to tenant

### UC-03: Monthly Rent Collection
1. Scheduled job creates RentLedger entry (status: pending) on 1st of month
2. Tenant pays → Transaction recorded (type: income, category: rent)
3. RentLedger updated (status: paid, paid_amount set)
4. Receipt auto-generated → emailed to tenant
5. ActivityLog entry created for audit trail

### UC-04: Overdue Rent Detection
1. Anomaly Detector / scheduled job checks RentLedger for `overdue` status
2. Discord alert sent to property manager
3. Email reminder sent to tenant (via Notification Service)
4. Manager can query AI Assistant: *"Which tenants are overdue this month?"*

### UC-05: AI Assistant Query
1. User types question in UI: *"What was the total income from Block A in Q1?"*
2. Query hits RAG API → ChromaDB semantic search retrieves relevant ledger docs
3. LLM (Ollama/Groq/Claude) generates answer using ONLY retrieved context
4. Response returned with source references
5. Rate limiter prevents abuse (10 QPM per user)

### UC-06: Developer Deploys New Feature
1. Developer pushes to `main` branch of RentalApp-Build
2. CI runs: pylint → bandit → Django check → pytest → SonarQube
3. Docker image built, pushed to ACR + DockerHub, signed with cosign
4. ArgoCD Image Updater detects new image tag in ACR
5. Updates `k8s/overlays/dev/kustomization.yaml` with new tag (git commit)
6. ArgoCD detects git change → triggers sync
7. Rolling update deployed to AKS `rental-dev` namespace
8. Discord `#deployments` channel notified

### UC-07: Infrastructure Lifecycle (KodeKloud)
1. Weekend session starts → run `terraform-schedule.yml` (action: recreate)
2. Terraform provisions AKS, ACR, VNet, KeyVault, Storage Account
3. Run `argocd-bootstrap.yml` → ArgoCD installed, apps registered
4. CI runs to push latest image → ArgoCD syncs → app live
5. Sunday evening → run `terraform-schedule.yml` (action: destroy) before session expires

### UC-08: Anomaly Alert Flow
1. Anomaly Detector CronJob runs every 5 minutes
2. Queries Prometheus for CPU/memory/error-rate/latency metrics
3. Z-score / IQR / rolling-window analysis detects outlier
4. Discord alert: severity, metric name, current value, affected pod
5. K8s AI Assistant invoked: diagnoses root cause from pod logs
6. Suggested kubectl commands posted to Discord thread

---

## 12. Environment Variables Reference

### RentalApp (Django)

| Variable | Required | Default | Description |
|---|---|---|---|
| `SECRET_KEY` | Yes (prod) | — | Django secret key (50+ chars) |
| `DEBUG` | No | `False` | Debug mode |
| `ALLOWED_HOSTS` | No | `127.0.0.1,localhost` | Comma-separated hostnames |
| `DB_NAME` | No | — | PostgreSQL database name |
| `DB_USER` | No | `postgres` | PostgreSQL user |
| `DB_PASSWORD` | No | — | PostgreSQL password |
| `DB_HOST` | No | `localhost` | PostgreSQL host |
| `DB_PORT` | No | `5432` | PostgreSQL port |
| `DB_SSLMODE` | No | `require` | SSL mode (disable for local tunnel) |
| `RUN_MIGRATIONS` | No | `false` | Auto-migrate on startup |
| `CORS_ALLOWED_ORIGINS` | No | — | Comma-separated origin URLs |
| `GUNICORN_WORKERS` | No | `4` | Worker process count |
| `GUNICORN_TIMEOUT` | No | `120` | Worker timeout in seconds |
| `PORT` | No | `8000` | Listening port |
| `SECURE_HSTS_SECONDS` | No | `0` | HSTS max-age (set to 31536000 in prod) |
| `SECURE_SSL_REDIRECT` | No | `False` | Redirect HTTP → HTTPS |
| `EMAIL_BACKEND` | No | `console` | Django email backend |
| `EMAIL_HOST_USER` | No | — | SMTP username |
| `EMAIL_HOST_PASSWORD` | No | — | SMTP password |

### GitHub Actions Secrets

| Secret | Repo | Description |
|---|---|---|
| `AZURE_CLIENT_ID` | Both | Azure SP app (client) ID |
| `AZURE_CLIENT_SECRET` | Both | Azure SP client secret |
| `AZURE_TENANT_ID` | Both | Azure tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Both | Azure subscription UUID |
| `TF_BACKEND_RG` | Platform | Terraform state resource group |
| `TF_BACKEND_SA` | Platform | Terraform state storage account |
| `ACR_NAME` | App | ACR short name (e.g. `deveusacrabc123`) |
| `ACR_LOGIN_SERVER` | App | ACR full URL (e.g. `deveusacrabc123.azurecr.io`) |
| `DOCKERHUB_USERNAME` | App | Docker Hub username |
| `DOCKERHUB_TOKEN` | App | Docker Hub access token |
| `SONAR_TOKEN` | App | SonarCloud project token |
| `SONAR_HOST_URL` | App | `https://sonarcloud.io` |
| `GCP_PROJECT_ID` | App | GCP project ID (for Google AR pushes) |
| `GCP_SERVICE_ACCOUNT` | App | GCP service account email (OIDC) |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | App | GCP workload identity provider resource name |
| `GCR_REGION` | App | GAR region (e.g. `us-central1`) |
| `DISCORD_WEBHOOK_URL` | Platform | Discord channel webhook |

---

## 13. Technology Stack

### Application Layer
| Technology | Version | Purpose |
|---|---|---|
| Python | 3.12 | Application runtime |
| Django | 5.2.1 | Web framework |
| Django REST Framework | 3.16.0 | REST API |
| django-cors-headers | 4.7.0 | CORS handling |
| Gunicorn | 23.0.0 | WSGI server |
| WhiteNoise | 6.9.0 | Static file serving |
| psycopg | 3.2.6 | PostgreSQL driver |
| Pillow | 11.1.0 | Image processing |

### AI / ML Layer
| Technology | Purpose |
|---|---|
| ChromaDB | Vector store for RAG |
| sentence-transformers | Text embeddings (all-MiniLM-L6-v2) |
| Ollama | Local LLM inference |
| Groq API | Fast free-tier LLM inference |
| Claude Haiku | Fallback LLM (Anthropic) |
| FastAPI | RAG API server |
| Prometheus client | Metrics instrumentation |

### Infrastructure Layer
| Technology | Purpose |
|---|---|
| Terraform | Infrastructure as Code (Azure + GCP) |
| Azure AKS | Managed Kubernetes |
| Azure ACR | Container registry (primary, AKS pulls) |
| Google Artifact Registry | Container registry (optional, GKE pulls) |
| Docker Hub | Container registry (public backup / default CI push) |
| Azure Key Vault | Secrets management |
| Azure Storage | Blob storage, Terraform state |
| ArgoCD | GitOps continuous delivery |
| Kustomize | K8s manifest templating |
| Helm | Package manager (ArgoCD, Prometheus) |

### Observability Layer
| Technology | Purpose |
|---|---|
| Prometheus | Metrics collection |
| Grafana | Dashboards and visualization |
| kube-prometheus-stack | Full monitoring stack via Helm |
| Discord | Real-time operational alerts |

### Security Layer
| Technology | Purpose |
|---|---|
| Istio | Service mesh, mTLS |
| Kyverno | Kubernetes admission control |
| OPA / Rego | Policy as code (Terraform guardrails) |
| cosign | Container image signing |
| Trivy | CVE scanning (images + filesystem) |
| Bandit | Python SAST |
| SonarCloud | Code quality and security gate |

### CI/CD Layer
| Technology | Purpose |
|---|---|
| GitHub Actions | CI/CD orchestration |
| Docker Buildx | Multi-arch image builds |
| PyNaCl | GitHub secrets encryption |
| Infracost | Terraform cost estimation |
| kubeconform | K8s manifest validation |
| Behave | BDD test framework |

---

*Last updated: April 2026*
