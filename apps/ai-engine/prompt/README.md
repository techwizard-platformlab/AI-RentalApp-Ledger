# Prompt Library — rentalAppLedger

Organised prompt files for building the AI-Powered DevSecOps Multi-Cloud Platform.
Each prompt is self-contained and ready to paste into an AI assistant (Claude, ChatGPT, Gemini, etc.).

## Structure

| Phase | Folder | What it builds |
|-------|--------|----------------|
| 00 | `00-bootstrap/` | Terraform state backend, Managed Identity, OIDC federated credentials |
| 01 | `01-terraform-azure/` | Azure infrastructure (AKS, VNet, PostgreSQL, ACR, Key Vault) |
| 02 | `02-terraform-gcp/` | GCP infrastructure (GKE, Cloud SQL, Artifact Registry, VPC) |
| 03 | `03-github-actions/` | CI/CD pipelines (terraform.yml, ci-build.yml, cost-check.yml) |
| 04 | `04-k8s-argocd/` | Kubernetes manifests and ArgoCD GitOps configuration |
| 05 | `05-istio-kyverno/` | Istio service mesh (mTLS) and Kyverno admission control |
| 06 | `06-opa/` | OPA Rego policies — cost guardrails, Terraform rules, Gatekeeper |
| 07 | `07-observability/` | Prometheus + Grafana — metrics, dashboards, alert rules |
| 08 | `08-ai-k8s-assistant/` | LLM-powered K8s pod diagnostics (Groq / Claude / Ollama) |
| 09 | `09-ai-rag/` | RAG API (FastAPI + ChromaDB) for natural language ledger queries |
| 10 | `10-qa/` | BDD tests (Behave), post-deploy validation scripts |
| 11 | `11-notifications/` | Discord + email alerting, ArgoCD notifications |

## Notes

- Prompts target a **personal Azure subscription** with Managed Identity + OIDC auth.
- Resource groups are pre-created manually or via bootstrap script — Terraform manages resources inside them.
- State backends are bootstrapped in Phase 0 before any Terraform work.
- Database engine is selectable per environment via `terraform.tfvars` (`db_engine = "postgresql"` or `"mssql"`).
- See `quick-reference/` for usage tips and cloud constraint notes.
