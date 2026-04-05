# Prompt 10.1 - QA: Cucumber + Python BDD Tests for rentalAppLedger

```
Act as a Senior QA Engineer specialising in BDD with Python and Cucumber (behave).

CONTEXT:
- App: rentalAppLedger (FastAPI microservices on AKS/GKE)
- QA runs: after each deployment (triggered by ArgoCD sync)
- Clouds: Azure + GCP (same test suite, different base URLs)
- Goal: validate deployment health + business logic correctness

TASK:
Generate complete BDD test suite:

### Feature 1: api_health.feature
```gherkin
Feature: API Health Validation
  Scenario: All services are healthy after deployment
    Given the cluster is "rental-dev" on cloud "azure"
    When I check health endpoint for "api-gateway"
    Then response code should be 200
    And response time should be under 2000ms
    And response body should contain "status": "healthy"

  Scenario Outline: All microservices respond
    Given the base URL is "<base_url>"
    When I GET "<endpoint>"
    Then I should get HTTP <status>
    Examples:
      | base_url        | endpoint         | status |
      | http://gateway  | /health          | 200    |
      | http://rental   | /health          | 200    |
      | http://ledger   | /health          | 200    |
```

### Feature 2: rental_operations.feature
```gherkin
Feature: Rental Management
  Scenario: Create a new rental agreement
  Scenario: Update payment status
  Scenario: Query overdue payments
  Scenario: Generate ledger report
```

### Feature 3: rag_assistant.feature
```gherkin
Feature: RAG Assistant Validation
  Scenario: Query returns relevant results
  Scenario: Empty query handled gracefully
  Scenario: Prompt injection blocked
```

### Step Definitions (steps/):
- api_steps.py: HTTP request helpers, response validators
- k8s_steps.py: kubectl-based checks (pod count, deployment status)
- db_steps.py: PostgreSQL direct validation

### Test Runner Integration:
- GitHub Actions job: qa-validate (runs after ArgoCD sync)
- Pass/fail -> Discord notification
- HTML report (behave-html-formatter) as GitHub Actions artifact
- Results also sent to Prometheus (custom exporter)

### Environment Config (environment.py):
- Read base URL from env var: AZURE_BASE_URL / GCP_BASE_URL
- Configure per environment: dev vs qa timeouts

INCLUDE:
- requirements.txt (behave, requests, pytest, kubernetes, behave-html-formatter)
- GitHub Actions job YAML (qa-validate.yml)
- How to run locally: behave features/ --tags @smoke

OUTPUT: All feature files + step definitions + environment.py + GitHub Actions YAML
```
