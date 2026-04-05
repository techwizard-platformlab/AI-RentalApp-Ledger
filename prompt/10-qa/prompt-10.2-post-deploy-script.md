# Prompt 10.2 - QA: Post-Deployment Validation Shell Script

```
Act as a Senior DevOps engineer. Generate shell scripts for post-deployment validation.

CONTEXT:
- After Terraform apply OR ArgoCD sync on AKS/GKE
- Run basic smoke tests before triggering full Cucumber suite
- Shell-based (no extra dependencies needed in pipeline)

TASK:
Generate validate_deployment.sh:

### Checks to perform:

#### 1. Kubernetes Health Checks
- All pods in rental-dev/rental-qa are Running (not Pending/Error)
- No pods in CrashLoopBackOff
- All deployments: desired == available replicas
- Services have endpoints (not empty)

#### 2. API Smoke Tests (curl-based)
- GET /health on all services -> expect 200
- GET /api/v1/rentals -> expect 200 or 401 (auth required = OK)
- Response time < 3 seconds

#### 3. Certificate + TLS Checks
- TLS cert not expired (openssl s_client)
- Cert valid for expected hostname

#### 4. Resource Threshold Checks
- No pod using > 90% of its memory limit
- No node CPU > 85% average

#### 5. Istio Health (if installed)
- All sidecars injected in rental-dev namespace
- Prometheus scraping Istio metrics

### Script Output:
- Colour-coded results (green OK / red FAIL)
- JSON summary: {passed: N, failed: N, warnings: N}
- Exit code 0 if all critical checks pass, 1 if any critical fails
- Send Discord notification with JSON summary

ALSO INCLUDE:
- Usage: ./validate_deployment.sh --cloud azure --env dev --notify discord
- How to trigger from GitHub Actions post-deploy job
- How to trigger from ArgoCD PostSync hook

OUTPUT: Complete shell script + ArgoCD resource hook YAML + GitHub Actions step
```
