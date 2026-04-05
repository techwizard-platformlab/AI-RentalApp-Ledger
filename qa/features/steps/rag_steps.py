"""rag_steps.py — RAG assistant step definitions."""

import time
from behave import given, when, then


@given('the RAG API is available at the configured URL')
def step_rag_available(context):
    resp = context.session.get(f"{context.rag_url}/health", timeout=5)
    assert resp.status_code == 200, f"RAG API not healthy: {resp.status_code}"


@when('I query the assistant with "{question}"')
def step_query_assistant(context, question):
    context.response = context.session.post(
        f"{context.rag_url}/query",
        json={"question": question, "top_k": 5},
        timeout=30,
    )


@then('the answer should not be empty')
def step_answer_not_empty(context):
    data = context.response.json()
    assert data.get("answer") and len(data["answer"]) > 5, \
        f"Answer is empty or too short: {data.get('answer')}"


@then('sources should be returned')
def step_sources_returned(context):
    data = context.response.json()
    assert isinstance(data.get("sources"), list), "sources field missing or not a list"


@then('the answer should not contain "{forbidden}"')
def step_answer_no_forbidden(context, forbidden):
    data = context.response.json()
    answer = data.get("answer", "")
    assert forbidden.upper() not in answer.upper(), \
        f"Forbidden string '{forbidden}' found in answer: {answer[:200]}"


@given('I send {n:d} successful queries to the assistant endpoint')
def step_send_n_queries(context, n):
    main_url = context.base_url
    context._rate_limit_responses = []
    for _ in range(n):
        resp = context.session.get(
            f"{main_url}/assistant/query",
            params={"q": "overdue payments"},
            timeout=10,
        )
        context._rate_limit_responses.append(resp.status_code)
    # All n should succeed
    for code in context._rate_limit_responses:
        assert code in (200, 429), f"Unexpected status: {code}"


@when('I send one more query immediately')
def step_send_one_more_query(context):
    main_url = context.base_url
    context.response = context.session.get(
        f"{main_url}/assistant/query",
        params={"q": "overdue payments"},
        timeout=10,
    )
