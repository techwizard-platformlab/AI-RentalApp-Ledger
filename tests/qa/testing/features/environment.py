import os
import requests

BASE_URL = os.getenv("BASE_URL", "http://localhost:8000").rstrip("/")


def before_all(context):
    context.base_url = BASE_URL
    context.session = requests.Session()
    context.session.headers.update({"Accept": "application/json"})


def after_all(context):
    context.session.close()


def before_feature(context, feature):
    context.response = None


def after_step(context, step):
    if step.status == "failed" and hasattr(context, "response") and context.response is not None:
        print(f"\nResponse status: {context.response.status_code}")
        try:
            print(f"Response body: {context.response.text[:500]}")
        except Exception:
            pass
