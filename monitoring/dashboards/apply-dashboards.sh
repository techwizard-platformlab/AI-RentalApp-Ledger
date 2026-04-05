#!/usr/bin/env bash
# Loads Grafana dashboard JSON files as ConfigMaps in the monitoring namespace.
# Grafana sidecar auto-discovers and loads them via the grafana_dashboard=1 label.
set -euo pipefail

NAMESPACE=${1:-monitoring}
DASHBOARD_DIR="$(dirname "$0")"

for json_file in "$DASHBOARD_DIR"/*.json; do
  name=$(basename "$json_file" .json | tr '_' '-')
  echo "Applying dashboard ConfigMap: $name"
  kubectl create configmap "$name" \
    -n "$NAMESPACE" \
    --from-file="$(basename "$json_file")=$json_file" \
    --dry-run=client -o yaml \
    | kubectl label --local -f - grafana_dashboard=1 -o yaml \
    | kubectl apply -f -
  echo "  ✓ $name applied"
done

echo "All dashboards applied to namespace: $NAMESPACE"
