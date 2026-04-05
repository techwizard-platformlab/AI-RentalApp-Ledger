"""
k8s_event_watcher.py — Watch Kubernetes events for pod restarts and OOM kills.
Triggers Discord notifications immediately on BackOff or OOMKilling events.
Runs as a Kubernetes Deployment (always-on).
"""

import logging
import os
import sys
import time

from kubernetes import client, config, watch

from discord_notifier import DiscordNotifier

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", stream=sys.stdout)
log = logging.getLogger(__name__)

TARGET_NAMESPACES = os.environ.get("TARGET_NAMESPACES", "rental-dev,rental-qa").split(",")
WATCH_REASONS     = {"BackOff", "OOMKilling", "Failed", "FailedScheduling", "Killing"}
notifier          = DiscordNotifier()


def load_k8s():
    try:
        config.load_incluster_config()
    except config.ConfigException:
        config.load_kube_config()


def watch_namespace(namespace: str) -> None:
    v1 = client.CoreV1Api()
    w  = watch.Watch()
    log.info("Watching events in namespace: %s", namespace)
    for event in w.stream(v1.list_namespaced_event, namespace=namespace, timeout_seconds=0):
        obj    = event["object"]
        reason = obj.reason or ""
        if reason not in WATCH_REASONS:
            continue

        pod_name = obj.involved_object.name or "unknown"
        count    = obj.count or 1
        message  = obj.message or ""

        log.warning("Event [%s] pod=%s count=%d msg=%s", reason, pod_name, count, message[:100])

        if reason == "BackOff":
            notifier.send_pod_restart(
                pod_name=pod_name,
                namespace=namespace,
                restart_count=count,
                reason=message[:200],
            )
        elif reason == "OOMKilling":
            notifier.send_resource_alert(
                alert_name="PodOOMKilled",
                severity="critical",
                labels={"pod": pod_name, "namespace": namespace},
                value=float(count),
            )


def main() -> None:
    load_k8s()
    log.info("K8s Event Watcher starting. Namespaces: %s", TARGET_NAMESPACES)

    # Watch each namespace in a thread for simplicity
    import threading
    threads = []
    for ns in TARGET_NAMESPACES:
        ns = ns.strip()
        t = threading.Thread(target=_watch_with_retry, args=(ns,), daemon=True)
        t.start()
        threads.append(t)

    for t in threads:
        t.join()


def _watch_with_retry(namespace: str) -> None:
    while True:
        try:
            watch_namespace(namespace)
        except Exception as e:
            log.error("Watch error in %s: %s — retrying in 10s", namespace, e)
            time.sleep(10)


if __name__ == "__main__":
    main()
