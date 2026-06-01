#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)/infra/certs"
mkdir -p "$DIR"
openssl req -x509 -newkey rsa:4096 -sha256 -days 825 \
  -nodes -keyout "$DIR/key.pem" -out "$DIR/cert.pem" \
  -subj "/CN=rohomieo.local" \
  -addext "subjectAltName=DNS:rohomieo.local,IP:10.8.0.20,IP:127.0.0.1"
echo "Wrote $DIR/cert.pem and $DIR/key.pem"
