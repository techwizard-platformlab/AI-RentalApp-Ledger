Feature: API Health and Regression Suite
  Full regression BDD tests for QA environment

  Background:
    Given the API base URL is configured

  @smoke @regression
  Scenario: API gateway health endpoint returns 200
    When I GET "/health"
    Then the response status is 200
    And the response body contains "status"

  @regression
  Scenario: Property listing endpoint returns valid response
    When I GET "/api/v1/properties/"
    Then the response status is 200
    And the response body is a valid JSON array

  @regression
  Scenario: Ledger endpoint returns 200 or 401
    When I GET "/api/v1/ledger/"
    Then the response status is one of [200, 401]

  @regression
  Scenario: Notification endpoint is reachable
    When I GET "/api/v1/notifications/"
    Then the response status is one of [200, 401, 403]

  @regression
  Scenario: API version header is present
    When I GET "/health"
    Then the response header "X-API-Version" exists or the body contains "version"
