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
curl -fsS "$BASE/metrics" | head -5
echo "ok"
