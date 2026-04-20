"""
environment.py — Behave hooks for QA environment.
Reads base URLs and timeouts from environment variables.
"""

import os
import requests


def before_all(context):
    cloud = os.environ.get("CLOUD", "azure").lower()
    env   = os.environ.get("ENV", "qa").lower()

    namespace = f"rental-{env}"
    default_url = f"http://api-gateway.{namespace}.svc.cluster.local:80"
    default_rag = f"http://rental-rag-api.{namespace}.svc.cluster.local:8080"

    context.base_url = os.environ.get("BASE_URL", os.environ.get("AZURE_BASE_URL", default_url))
    context.rag_url  = os.environ.get("RAG_BASE_URL", default_rag)
    context.cloud    = cloud
    context.env      = env
    context.timeout  = float(os.environ.get("REQUEST_TIMEOUT", "5.0"))

    context.session  = requests.Session()
    context.response = None

    print(f"\n[BDD] Cloud={cloud} Env={env} BaseURL={context.base_url}")


def before_scenario(context, scenario):
    context.response = None


def after_scenario(context, scenario):
    if hasattr(context, "cleanup_ids"):
        for url in context.cleanup_ids:
            try:
                context.session.delete(f"{context.base_url}{url}", timeout=3)
            except Exception:
                pass
        context.cleanup_ids = []


def after_all(context):
    context.session.close()
