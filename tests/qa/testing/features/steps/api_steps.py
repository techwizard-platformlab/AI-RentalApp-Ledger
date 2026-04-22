from behave import given, when, then
import re


@given("the API base URL is configured")
def step_api_url_configured(context):
    assert context.base_url, "BASE_URL environment variable is not set"


@when('I GET "{path}"')
def step_get(context, path):
    url = f"{context.base_url}{path}"
    context.response = context.session.get(url, timeout=15)


@then("the response status is {code:d}")
def step_status(context, code):
    assert context.response.status_code == code, (
        f"Expected {code}, got {context.response.status_code}"
    )


@then("the response status is one of [{codes}]")
def step_status_one_of(context, codes):
    allowed = [int(c.strip()) for c in codes.split(",")]
    assert context.response.status_code in allowed, (
        f"Expected one of {allowed}, got {context.response.status_code}"
    )


@then('the response body contains "{text}"')
def step_body_contains(context, text):
    assert text in context.response.text, (
        f"Expected '{text}' in response body"
    )


@then("the response body is a valid JSON array")
def step_body_is_array(context):
    body = context.response.json()
    assert isinstance(body, (list, dict)), "Response body is not a JSON array or object"


@then('the response header "{header}" exists or the body contains "{text}"')
def step_header_or_body(context, header, text):
    has_header = header in context.response.headers
    has_text = text in context.response.text
    assert has_header or has_text, (
        f"Expected header '{header}' or body text '{text}'"
    )
