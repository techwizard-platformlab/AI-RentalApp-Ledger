"""
environment.py — Behave hooks: setup/teardown and environment configuration.
Reads base URLs and timeouts from environment variables per cloud/env.
"""

import os
import requests


def before_all(context):
    cloud = os.environ.get("CLOUD", "azure").lower()
    env   = os.environ.get("ENV", "dev").lower()

    # Base URLs per cloud
    azure_url = os.environ.get("AZURE_BASE_URL", "http://api-gateway.rental-dev.svc.cluster.local:80")
    gcp_url   = os.environ.get("GCP_BASE_URL",   "http://api-gateway.rental-dev.svc.cluster.local:80")
    rag_url   = os.environ.get("RAG_BASE_URL",    "http://rag-api.rental-dev.svc.cluster.local:8080")

    context.base_url = azure_url if cloud == "azure" else gcp_url
    context.rag_url  = rag_url
    context.cloud    = cloud
    context.env      = env

    # Timeout: more lenient in dev, tighter in qa
    context.timeout = 5.0 if env == "dev" else 3.0

    context.session  = requests.Session()
    context.response = None
    context.lease_id = None

    print(f"\n[BDD] Cloud={cloud} Env={env} BaseURL={context.base_url}")


def before_scenario(context, scenario):
    context.response = None


def after_scenario(context, scenario):
    # Clean up test data created during scenario (best-effort)
    if hasattr(context, "cleanup_ids"):
        for url in context.cleanup_ids:
            try:
                context.session.delete(f"{context.base_url}{url}", timeout=3)
            except Exception:
                pass
        context.cleanup_ids = []


def after_all(context):
    context.session.close()
