# Prompt 3.2 - GitHub Actions: Application CI Pipeline (Build, Test, Push to ACR/GCR)

```
Act as a Senior DevSecOps Engineer.

CONTEXT:
- App repo: rentalAppLedger (Python microservice, FastAPI)
- Registries: Azure ACR (dev) and GCP Artifact Registry (dev) - push to BOTH
- Auth: OIDC for both clouds
- Docker: multi-stage build for minimal image size

TASK:
Generate GitHub Actions CI workflow: ci-build.yml

### Trigger:
- push to main
- pull_request to main

### Jobs:

#### Job 1: lint-and-test
- Python 3.11
- pip install, run pytest
- Upload coverage report as artifact

#### Job 2: security-scan (runs parallel with test)
- Trivy filesystem scan before build
- If CRITICAL CVE found: fail the build
- Upload SARIF to GitHub Security tab

#### Job 3: build-and-push (needs: lint-and-test, security-scan)
- Docker multi-stage build
- Tag strategy: {git_sha}, latest, {branch}-{date}
- Push to Azure ACR (OIDC)
- Push to GCP Artifact Registry (OIDC)
- Sign image with cosign (keyless signing)

#### Job 4: notify
- On success: Discord webhook message with image tag
- On failure: Discord + email notification

ALSO INCLUDE:
- Dockerfile example (Python FastAPI, multi-stage, non-root user)
- .dockerignore
- GitHub branch protection rules recommendation (PR required, status checks required)
- How to pass image tag to ArgoCD (image updater or git commit)

OUTPUT: Complete ci-build.yml + Dockerfile + .dockerignore
```
