# Sourced helper: best-effort automatic router port-forwarding via UPnP IGD
# (miniupnpc). No-op with a warning if the router doesn't support UPnP —
# falls back to whatever ports are already reachable.

upnp_local_ip() {
  if declare -F rohomieo_local_ip >/dev/null 2>&1; then
    rohomieo_local_ip
    return 0
  fi
  local _root
  _root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  # shellcheck disable=SC1091
  if [[ -f "$_root/scripts/lib-platform.sh" ]]; then
    # shellcheck source=lib-platform.sh
    source "$_root/scripts/lib-platform.sh"
    rohomieo_local_ip
    return 0
  fi
  hostname -I 2>/dev/null | awk '{print $1}'
}

# upnp_open <port> <tcp|udp> <description> [optional local IP]
upnp_open() {
  local port="$1" proto="$2" desc="$3" ip="${4:-}"
  command -v upnpc >/dev/null || { echo "upnpc not installed — skipping UPnP for $desc ($port/$proto)"; return 0; }
  if [[ -z "$ip" ]]; then
    ip="$(upnp_local_ip)"
  fi
  [[ -z "$ip" ]] && return 0
  if upnpc -e "rohomieo-$desc" -a "$ip" "$port" "$port" "$proto" >/tmp/rohomieo-upnp.log 2>&1; then
    echo "==> UPnP: opened $port/$proto on router → $ip ($desc)"
  else
    echo "==> UPnP: router didn't accept $port/$proto ($desc) — forward it manually if clients can't connect"
  fi
}

# upnp_close <port> <tcp|udp>
upnp_close() {
  local port="$1" proto="$2"
  command -v upnpc >/dev/null || return 0
  upnpc -d "$port" "$proto" >/dev/null 2>&1 || true
}
