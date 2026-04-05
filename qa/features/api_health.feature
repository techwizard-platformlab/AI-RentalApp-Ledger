@smoke
Feature: API Health Validation
  Validate all services are healthy after deployment on AKS or GKE.

  Scenario: All services are healthy after deployment
    Given the cluster is "rental-dev" on cloud "azure"
    When I check health endpoint for "api-gateway"
    Then response code should be 200
    And response time should be under 2000ms
    And response body should contain "status" equal to "healthy"

  Scenario Outline: All microservices respond to health checks
    Given the base URL is "<base_url>"
    When I GET "<endpoint>"
    Then I should get HTTP <status>

    Examples:
      | base_url                     | endpoint | status |
      | http://api-gateway:80        | /health  | 200    |
      | http://rental-service:8001   | /health  | 200    |
      | http://ledger-service:8002   | /health  | 200    |
      | http://notification-service:8003 | /health | 200 |

  @slow
  Scenario: ArgoCD sync does not leave pods in bad state
    Given the cluster is "rental-dev" on cloud "azure"
    When I check Kubernetes deployment status for namespace "rental-dev"
    Then all deployments should have desired replicas available
    And no pods should be in CrashLoopBackOff state
