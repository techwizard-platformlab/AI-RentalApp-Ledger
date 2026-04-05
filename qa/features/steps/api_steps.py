"""api_steps.py — HTTP request and response validation step definitions."""

import time
import json as _json
from behave import given, when, then


@given('the base URL is "{url}"')
def step_set_base_url(context, url):
    context.base_url = url


@given('the API base URL is set from environment')
def step_api_base_from_env(context):
    pass   # already set in environment.py before_all


@when('I GET "{path}"')
def step_get(context, path):
    url = path if path.startswith("http") else f"{context.base_url}{path}"
    t0 = time.perf_counter()
    context.response = context.session.get(url, timeout=context.timeout)
    context.response_time_ms = (time.perf_counter() - t0) * 1000


@when('I POST to "{path}" with valid lease data')
def step_post_lease(context, path):
    payload = {
        "tenant_name": getattr(context, "tenant_name", "Test Tenant"),
        "property_address": getattr(context, "property_address", "1 Test St"),
        "monthly_rent": 1500,
        "start_date": "2026-01-01",
        "end_date": "2027-01-01",
    }
    context.response = context.session.post(
        f"{context.base_url}{path}", json=payload, timeout=context.timeout
    )
    if context.response.status_code == 201:
        context.lease_id = context.response.json().get("lease_id")
        context.cleanup_ids = getattr(context, "cleanup_ids", [])
        context.cleanup_ids.append(f"/api/v1/leases/{context.lease_id}")


@when('I POST to "{path}" with amount {amount:d} and status "{status}"')
def step_post_payment(context, path, amount, status):
    payload = {"lease_id": context.lease_id, "amount": amount, "status": status}
    context.response = context.session.post(
        f"{context.base_url}{path}", json=payload, timeout=context.timeout
    )


@then('response code should be {code:d}')
def step_status_code(context, code):
    actual = context.response.status_code
    assert actual == code, f"Expected {code}, got {actual}. Body: {context.response.text[:300]}"


@then('response code should be {code1:d} or {code2:d}')
def step_status_code_or(context, code1, code2):
    actual = context.response.status_code
    assert actual in (code1, code2), f"Expected {code1} or {code2}, got {actual}"


@then('response time should be under {ms:d}ms')
def step_response_time(context, ms):
    assert context.response_time_ms < ms, f"Response time {context.response_time_ms:.0f}ms > {ms}ms"


@then('response body should contain "{key}" equal to "{value}"')
def step_body_key_equals(context, key, value):
    data = context.response.json()
    assert key in data, f"Key '{key}' not in response: {data}"
    assert str(data[key]) == value, f"Expected {key}={value}, got {data[key]}"


@then('response body should contain a "{key}"')
def step_body_contains_key(context, key):
    data = context.response.json()
    assert key in data and data[key], f"Key '{key}' missing or empty in response: {data}"


@then('response body "{key}" should equal "{value}"')
def step_body_field_equals(context, key, value):
    data = context.response.json()
    assert data.get(key) == value, f"Expected {key}={value}, got {data.get(key)}"


@then('response body should be a list')
def step_body_is_list(context):
    data = context.response.json()
    assert isinstance(data, list), f"Expected list, got {type(data)}"


@then('each item should have field "{field}" equal to "{value}"')
def step_each_item_field(context, field, value):
    data = context.response.json()
    for item in data:
        assert item.get(field) == value, f"Item missing {field}={value}: {item}"


@then('response body should contain "{key}"')
def step_body_contains(context, key):
    data = context.response.json()
    assert key in data, f"Key '{key}' not found in: {data}"


@then('response body should contain a validation error')
def step_body_validation_error(context):
    data = context.response.json()
    assert "detail" in data or "error" in data, f"No validation error in: {data}"


@given('I have tenant data with name "{name}" and email "{email}"')
def step_tenant_data(context, name, email):
    context.tenant_name = name
    context.tenant_email = email


@given('I have property data at address "{address}"')
def step_property_data(context, address):
    context.property_address = address


@given('an existing lease with id stored from previous scenario')
def step_use_stored_lease(context):
    assert context.lease_id, "No lease_id stored from previous scenario"


@given('there are overdue payments in the system')
@given('the system has ledger entries')
def step_assume_data_exists(context):
    pass   # test data seeded by seed_test_data.py


@then('the lease status should be "{status}"')
def step_lease_status(context, status):
    data = context.response.json()
    assert data.get("status") == status, f"Expected status={status}, got {data.get('status')}"
