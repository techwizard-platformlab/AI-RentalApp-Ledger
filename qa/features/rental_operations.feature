@smoke @business
Feature: Rental Management Operations
  Validate core rental business logic after deployment.

  Background:
    Given the API base URL is set from environment

  Scenario: Create a new rental agreement
    Given I have tenant data with name "Test Tenant BDD" and email "bdd@test.com"
    And I have property data at address "1 BDD Test Street"
    When I POST to "/api/v1/leases" with valid lease data
    Then response code should be 201
    And response body should contain a "lease_id"
    And the lease status should be "active"

  Scenario: Update payment status to paid
    Given an existing lease with id stored from previous scenario
    When I POST to "/api/v1/payments" with amount 1500 and status "paid"
    Then response code should be 201
    And response body "status" should equal "paid"

  Scenario: Query overdue payments
    Given there are overdue payments in the system
    When I GET "/api/v1/payments?status=overdue"
    Then response code should be 200
    And response body should be a list
    And each item should have field "status" equal to "overdue"

  Scenario: Generate ledger report
    Given the system has ledger entries
    When I GET "/api/v1/ledger/report?month=current"
    Then response code should be 200
    And response body should contain "total_credits"
    And response body should contain "total_debits"
