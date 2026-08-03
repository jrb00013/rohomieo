#!/usr/bin/env bash
# Probe Rohomieo signaling health endpoints.
set -euo pipefail
BASE="${1:-http://127.0.0.1:8443}"

echo "==> GET $BASE/health"
curl -fsS "$BASE/health"
echo

echo "==> GET $BASE/api/status"
curl -fsS "$BASE/api/status" | python3 -m json.tool
echo

echo "==> GET $BASE/metrics (first 5 lines)"
code="$(curl -sS -o /tmp/rohomieo-metrics.txt -w "%{http_code}" "$BASE/metrics" || true)"
if [[ "$code" == "200" ]]; then
  head -5 /tmp/rohomieo-metrics.txt
elif [[ "$code" == "401" ]]; then
  echo "(admin API requires Authorization: Bearer \$ROHOMIEO_ADMIN_TOKEN)"
elif [[ "$code" == "404" ]]; then
  echo "(admin API disabled — pass --expose-admin-api or --admin-token to enable)"
else
  echo "(unexpected HTTP $code)"
fi
echo "ok"
