#!/usr/bin/env bash
# Shared platform helpers for run.sh / start-*.sh
# Source only — do not execute.

# Prints: linux | wsl | macos | windows | unknown
rohomieo_detect_platform() {
  case "$(uname -s 2>/dev/null)" in
    Darwin) echo macos ;;
    Linux)
      if [[ -n "${WSL_DISTRO_NAME:-}" ]] \
        || [[ -n "${WSL_INTEROP:-}" ]] \
        || grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
        echo wsl
      else
        echo linux
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *) echo unknown ;;
  esac
}

rohomieo_brew_bin() {
  if command -v brew >/dev/null 2>&1; then
    command -v brew
    return 0
  fi
  local cand
  for cand in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$cand" ]]; then
      echo "$cand"
      return 0
    fi
  done
  return 1
}

rohomieo_tool_path() {
  local home="${1:-$HOME}"
  local parts=()
  parts+=("$home/.cargo/bin" "$home/.local/bin")
  local brew
  if brew="$(rohomieo_brew_bin)"; then
    parts+=("$(dirname "$brew")")
    local prefix
    prefix="$("$brew" --prefix 2>/dev/null || true)"
    if [[ -n "$prefix" ]]; then
      parts+=("$prefix/bin")
    fi
  else
    parts+=(/opt/homebrew/bin /usr/local/bin)
  fi
  parts+=(/usr/bin /bin /usr/sbin /sbin)
  local out="" p
  for p in "${parts[@]}"; do
    [[ -n "$p" ]] || continue
    case ":$out:" in
      *":$p:"*) ;;
      *) out="${out:+$out:}$p" ;;
    esac
  done
  echo "$out"
}

# Best-effort LAN IPv4 for join URLs (Linux + macOS).
rohomieo_local_ip() {
  local ip=""
  if command -v ip >/dev/null 2>&1; then
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  fi
  if [[ -z "$ip" ]]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  if [[ -z "$ip" ]]; then
    local iface
    for iface in en0 en1 en2 en3; do
      ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
      [[ -n "$ip" ]] && break
    done
  fi
  if [[ -z "$ip" ]]; then
    ip="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}' | {
      read -r iface
      [[ -n "$iface" ]] && ipconfig getifaddr "$iface" 2>/dev/null
    })"
  fi
  echo "${ip:-}"
}
