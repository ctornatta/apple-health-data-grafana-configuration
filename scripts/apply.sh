#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

for cmd in curl jq envsubst; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: '$cmd' is required but not installed." >&2
    exit 1
  fi
done

if [ -f "$ROOT_DIR/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.env"
  set +a
fi

: "${GRAFANA_URL:?GRAFANA_URL is not set}"
: "${GRAFANA_USER:?GRAFANA_USER is not set}"
: "${GRAFANA_PASSWORD:?GRAFANA_PASSWORD is not set}"
: "${INFLUXDB_TOKEN:?INFLUXDB_TOKEN is not set}"
: "${INFLUXDB_URL:?INFLUXDB_URL is not set}"
: "${INFLUXDB_ORG:?INFLUXDB_ORG is not set}"

DATASOURCE_UID="apple-health-influxdb"
AUTH="$GRAFANA_USER:$GRAFANA_PASSWORD"

echo "==> Applying datasource..."

DATASOURCE_JSON=$(envsubst < "$ROOT_DIR/grafana/datasources/influxdb.json")

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u "$AUTH" \
  "$GRAFANA_URL/api/datasources/uid/$DATASOURCE_UID")

if [ "$HTTP_STATUS" = "200" ]; then
  echo "    Updating datasource..."
  curl -sf -X PUT -u "$AUTH" \
    -H "Content-Type: application/json" \
    -d "$DATASOURCE_JSON" \
    "$GRAFANA_URL/api/datasources/uid/$DATASOURCE_UID" | jq -r '.message // "ok"'
else
  echo "    Creating datasource..."
  curl -sf -X POST -u "$AUTH" \
    -H "Content-Type: application/json" \
    -d "$DATASOURCE_JSON" \
    "$GRAFANA_URL/api/datasources" | jq -r '.message // "ok"'
fi

echo ""
echo "==> Applying dashboards..."

for dashboard_file in "$ROOT_DIR/grafana/dashboards"/*.json; do
  name=$(basename "$dashboard_file" .json)
  echo "    Pushing $name..."
  PAYLOAD=$(jq -n --argjson dash "$(cat "$dashboard_file")" \
    '{"dashboard": $dash, "overwrite": true, "folderId": 0}')
  curl -sf -X POST -u "$AUTH" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$GRAFANA_URL/api/dashboards/db" | jq -r '"\(.status): \(.url // "")"'
done

echo ""
echo "Done."
