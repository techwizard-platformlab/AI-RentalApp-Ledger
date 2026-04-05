# Prompt 2.2 - Terraform GCP: Core Resources (VPC, GKE, Cloud Armor, Secret Manager)

```
Act as a Senior Cloud Architect for GCP Terraform.

CONTEXT - KodeKloud GCP limits:
- E2/N2 VM series only; max 5 VMs, 7 vCPUs
- GKE Standard mode only (Autopilot blocked)
- Max 8 External IPs
- US regions only, default project

TASK:
Generate Terraform for these GCP modules:

### Module 1: VPC + Subnets
- VPC: custom mode (not auto)
- Subnet: app-subnet 10.1.1.0/24 (us-central1)
- Subnet: db-subnet  10.1.2.0/24 (us-central1)
- Enable Private Google Access on both subnets
- Cloud NAT for private GKE nodes (note: cost tradeoff)

### Module 2: Cloud Armor (WAF equivalent)
- Security policy: OWASP preconfigured rules
- Default rule: allow
- Custom rule: rate limiting (100 req/min per IP)
- Attach to backend service (placeholder)

### Module 3: Artifact Registry (GCR legacy avoided)
- Repository format: DOCKER
- Location: us-central1
- Cleanup policy: keep last 10 images (use terraform cleanup rules; note if not supported)

### Module 4: GKE Cluster
- Mode: Standard (not Autopilot - KodeKloud restriction)
- Node pool: 1 node, e2-standard-2
- Workload Identity: enabled
- Private cluster: enabled (no public node IPs)
- Master authorised networks: restrict to known CIDR
- Output: kubeconfig command, cluster_name, endpoint

### Module 5: Secret Manager
- Enable API
- Create secrets: db_password, acr_token, discord_webhook
- IAM: GKE service account gets secretAccessor role
- Rotation: manual (free tier)

### Module 6: Cloud Storage Bucket
- Storage class: STANDARD
- Location: US (multi-region for tfstate)
- Versioning: enabled
- Lifecycle: delete versions older than 30 days

FOR EACH MODULE: main.tf + variables.tf + outputs.tf + cost comments
USE: google provider ~>5.x, Terraform ~>1.5
```
