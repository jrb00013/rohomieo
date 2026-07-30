#!/usr/bin/env bash
# Foreground host for scripts/run.sh. Preserves reachability overrides from run.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/lib-platform.sh"
export PATH="$(rohomieo_tool_path "${HOME:-}")${PATH:+:$PATH}"

_KEEP_MODE="${ROHOMIEO_MODE:-}"
_KEEP_SIGNALING="${ROHOMIEO_SIGNALING_URL:-${ROHOMIEO_SIGNALING:-}}"
_KEEP_PUBLIC_URL="${ROHOMIEO_PUBLIC_URL:-}"
_KEEP_TURN_URL="${ROHOMIEO_TURN_URL:-}"
_KEEP_TURN_USER="${ROHOMIEO_TURN_USER:-}"
_KEEP_TURN_PASS="${ROHOMIEO_TURN_PASS:-}"
# shellcheck disable=SC1091
[[ -f "$ROOT/.env.rohomieo" ]] && source "$ROOT/.env.rohomieo"
[[ -n "$_KEEP_MODE" ]] && ROHOMIEO_MODE="$_KEEP_MODE"
[[ -n "$_KEEP_SIGNALING" ]] && ROHOMIEO_SIGNALING_URL="$_KEEP_SIGNALING"
[[ -n "$_KEEP_PUBLIC_URL" ]] && ROHOMIEO_PUBLIC_URL="$_KEEP_PUBLIC_URL"
if [[ "$_KEEP_MODE" == "local" ]]; then
  unset ROHOMIEO_TURN_URL || true
elif [[ -n "$_KEEP_TURN_URL" ]]; then
  ROHOMIEO_TURN_URL="$_KEEP_TURN_URL"
fi
[[ -n "$_KEEP_TURN_USER" ]] && ROHOMIEO_TURN_USER="$_KEEP_TURN_USER"
[[ -n "$_KEEP_TURN_PASS" ]] && ROHOMIEO_TURN_PASS="$_KEEP_TURN_PASS"

BIN="${ROHOMIEO_HOST_BIN:-$ROOT/target/release/rohomieo-host}"
if [[ ! -x "$BIN" ]]; then
  if [[ -x "$ROOT/.local/bin/rohomieo-host" ]]; then
    BIN="$ROOT/.local/bin/rohomieo-host"
  else
    echo "==> building rohomieo-host (release)"
    (cd "$ROOT" && cargo build --release -p rohomieo-host)
    BIN="$ROOT/target/release/rohomieo-host"
  fi
fi

ARGS=(
  --signaling "${ROHOMIEO_SIGNALING_URL:-wss://127.0.0.1:8443/ws}"
)
[[ -n "${ROHOMIEO_PUBLIC_URL:-}" ]] && ARGS+=(--public-url "$ROHOMIEO_PUBLIC_URL")
[[ -n "${ROHOMIEO_TURN_URL:-}" ]] && ARGS+=(--turn-url "$ROHOMIEO_TURN_URL")
[[ -n "${ROHOMIEO_TURN_USER:-}" ]] && ARGS+=(--turn-user "$ROHOMIEO_TURN_USER")
[[ -n "${ROHOMIEO_TURN_PASS:-}" ]] && ARGS+=(--turn-pass "$ROHOMIEO_TURN_PASS")
[[ -n "${ROHOMIEO_SESSION:-}" ]] && ARGS+=(--session "$ROHOMIEO_SESSION")
[[ -n "${ROHOMIEO_PIN:-}" ]] && ARGS+=(--pin "$ROHOMIEO_PIN")

exec "$BIN" "${ARGS[@]}"
