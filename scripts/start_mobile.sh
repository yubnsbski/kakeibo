#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_DIR="${KAKEIBO_CERT_DIR:-${HOME}/.kakeibo/certs}"

bash "$ROOT_DIR/scripts/setup_mobile_https.sh" "${KAKEIBO_LAN_IP:-}"

LAN_IP="$(cat "$CERT_DIR/lan-ip")"
export KAKEIBO_LAN_IP="$LAN_IP"
export KAKEIBO_HTTPS_KEY="$CERT_DIR/kakeibo-server.key"
export KAKEIBO_HTTPS_CERT="$CERT_DIR/kakeibo-server.crt"
export KAKEIBO_CA_CERT_FILE="$CERT_DIR/kakeibo-local-ca.cer"
export KAKEIBO_CERT_SERVER="1"
export KAKEIBO_CERT_PORT="${KAKEIBO_CERT_PORT:-5174}"
export KAKEIBO_NO_OPEN="1"

exec bash "$ROOT_DIR/scripts/start.sh"
