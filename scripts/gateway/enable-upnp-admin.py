#!/usr/bin/env python3
"""Enable UPnP on the LAN gateway via legitimate admin HTTPS forms.

This is NOT an exploit. It replays the same POST your browser sends after login.

Setup:
  1. cp scripts/gateway/gateway.env.example ~/.config/rohomieo/gateway.env
  2. Put GATEWAY_USER / GATEWAY_PASS in that file (chmod 600).
  3. In the router UI: enable UPnP once with DevTools Network open →
     right-click the save request → Copy as cURL.
  4. Paste into GATEWAY_APPLY_CURL=... replacing the password with __GATEWAY_PASS__.

Usage:
  ./scripts/enable-gateway-upnp.sh
  python3 scripts/gateway/enable-upnp-admin.py
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

CONFIG_PATHS = [
    Path(os.environ.get("ROHOMIEO_GATEWAY_ENV", "")),
    Path.home() / ".config" / "rohomieo" / "gateway.env",
    Path(__file__).resolve().parents[2] / "var" / "gateway.env",
]


def load_env(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip().strip("'").strip('"')
        data[key] = val
    return data


def find_config() -> Path:
    for p in CONFIG_PATHS:
        if p and p.is_file():
            return p
    example = Path(__file__).resolve().parent / "gateway.env.example"
    print(
        "No gateway.env found. Create one:\n"
        f"  mkdir -p ~/.config/rohomieo && cp {example} ~/.config/rohomieo/gateway.env\n"
        "  chmod 600 ~/.config/rohomieo/gateway.env\n"
        "Then set GATEWAY_PASS and GATEWAY_APPLY_CURL (Copy-as-cURL from DevTools).",
        file=sys.stderr,
    )
    sys.exit(2)


def main() -> int:
    cfg_path = find_config()
    cfg = load_env(cfg_path)
    password = cfg.get("GATEWAY_PASS", "") or os.environ.get("GATEWAY_PASS", "")
    curl_tpl = cfg.get("GATEWAY_APPLY_CURL", "").strip()
    if not curl_tpl:
        print(
            "GATEWAY_APPLY_CURL is empty.\n"
            "1) Log into the gateway, enable UPnP, save.\n"
            "2) DevTools → Network → Copy as cURL on the save request.\n"
            "3) Put it in gateway.env as GATEWAY_APPLY_CURL='...',\n"
            "   replacing the password with __GATEWAY_PASS__.",
            file=sys.stderr,
        )
        return 2
    if "__GATEWAY_PASS__" in curl_tpl and not password:
        print("GATEWAY_PASS is required (placeholder __GATEWAY_PASS__ in curl).", file=sys.stderr)
        return 2

    curl_cmd = curl_tpl.replace("__GATEWAY_PASS__", password)
    # Prefer array form when possible; fall back to shell for complex Copy-as-cURL.
    print(f"==> applying gateway UPnP via admin form ({cfg_path})")
    try:
        # Copy-as-cURL is meant for a shell; run under bash -c safely after substitution.
        completed = subprocess.run(
            ["bash", "-c", curl_cmd],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        print("gateway request timed out", file=sys.stderr)
        return 1

    if completed.stdout.strip():
        print(completed.stdout.strip()[:2000])
    if completed.returncode != 0:
        err = (completed.stderr or "").strip()[:1000]
        print(f"curl exit {completed.returncode}: {err}", file=sys.stderr)
        return 1

    print("==> admin form POST finished — re-check UPnP with ./scripts/enable-upnp.sh")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
