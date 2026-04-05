# Prompt Library for rentalAppLedger

This folder contains organized prompt files for the AI-Powered DevSecOps Multi-Cloud Platform playbook.
Each prompt is self-contained and ready to paste into an AI assistant.

## Structure
- 00-bootstrap: one-time prerequisites for state backends and identity
- 01-terraform-azure: Azure infrastructure prompts
- 02-terraform-gcp: GCP infrastructure prompts
- 03-github-actions: CI/CD and policy pipeline prompts
- 04-k8s-argocd: Kubernetes manifests and ArgoCD GitOps prompts
- 05-istio-kyverno: service mesh and policy prompts
- 06-opa: OPA policies for Terraform and Kubernetes
- 07-observability: Prometheus and Grafana prompts
- 08-ai-k8s-assistant: LLM K8s assistant prompts
- 09-ai-rag: RAG prompts
- 10-qa: QA prompts
- 11-notifications: notification prompts
- quick-reference: KodeKloud constraints and usage tips

## Notes
- Prompts assume KodeKloud Playground constraints.
- Resource groups/projects are pre-created; prompts avoid creating them.
- State backends are bootstrapped in Phase 0.
