"""k8s_steps.py — Kubernetes health check step definitions using kubectl."""

import subprocess
import json
from behave import given, when, then


def _kubectl(args: list[str]) -> dict | list:
    cmd = ["kubectl"] + args + ["-o", "json"]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        raise AssertionError(f"kubectl failed: {result.stderr}")
    return json.loads(result.stdout)


@given('the cluster is "{env}" on cloud "{cloud}"')
def step_set_cluster(context, env, cloud):
    context.k8s_namespace = env
    context.cloud = cloud


@when('I check health endpoint for "{service}"')
def step_check_health(context, service):
    import time, requests
    url = f"{context.base_url}/health"
    t0 = time.perf_counter()
    context.response = requests.get(url, timeout=context.timeout)
    context.response_time_ms = (time.perf_counter() - t0) * 1000


@when('I check Kubernetes deployment status for namespace "{namespace}"')
def step_check_k8s(context, namespace):
    context.k8s_data = _kubectl(["get", "deployments", "-n", namespace])


@then('all deployments should have desired replicas available')
def step_all_replicas_available(context):
    items = context.k8s_data.get("items", [])
    for dep in items:
        name = dep["metadata"]["name"]
        desired = dep["spec"]["replicas"]
        available = dep["status"].get("availableReplicas", 0)
        assert desired == available, \
            f"Deployment '{name}': desired={desired}, available={available}"


@then('no pods should be in CrashLoopBackOff state')
def step_no_crashloop(context):
    ns = context.k8s_namespace
    pods = _kubectl(["get", "pods", "-n", ns])
    for pod in pods.get("items", []):
        pod_name = pod["metadata"]["name"]
        for cs in pod.get("status", {}).get("containerStatuses", []):
            waiting = cs.get("state", {}).get("waiting", {})
            reason = waiting.get("reason", "")
            assert reason != "CrashLoopBackOff", \
                f"Pod '{pod_name}' container '{cs['name']}' is in CrashLoopBackOff"
