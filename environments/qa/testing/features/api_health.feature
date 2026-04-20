Feature: API Health Checks — QA
  As a QA engineer
  I want to verify all services are healthy after deployment to the QA environment

  Background:
    Given the API gateway is accessible at port 8000
    And the environment is "qa"

  Scenario: API gateway returns 200 OK
    When I request GET /health
    Then the response status should be 200
    And the response time should be under 2000 ms

  Scenario: All microservice health endpoints respond
    When I request GET /api/v1/health/rental
    Then the response status should be 200
    When I request GET /api/v1/health/ledger
    Then the response status should be 200
    When I request GET /api/v1/health/notification
    Then the response status should be 200

  Scenario: Authenticated endpoints require a valid token
    When I request GET /api/v1/rentals without auth
    Then the response status should be 401

  Scenario: Metrics endpoint is available
    When I request GET /metrics
    Then the response status should be 200
