#!/usr/bin/env bash
set -euo pipefail

CERT_DIR="${KAKEIBO_CERT_DIR:-${HOME}/.kakeibo/certs}"
REQUESTED_IP="${1:-${KAKEIBO_LAN_IP:-}}"
CA_KEY="${CERT_DIR}/kakeibo-local-ca.key"
CA_CERT="${CERT_DIR}/kakeibo-local-ca.crt"
CA_CERT_DER="${CERT_DIR}/kakeibo-local-ca.cer"
SERVER_KEY="${CERT_DIR}/kakeibo-server.key"
SERVER_CERT="${CERT_DIR}/kakeibo-server.crt"
SERVER_CSR="${CERT_DIR}/kakeibo-server.csr"
LAN_IP_FILE="${CERT_DIR}/lan-ip"

umask 077
mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR" 2>/dev/null || true

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl が見つかりません。" >&2
  exit 1
fi

valid_ipv4() {
  value="$1"
  case "$value" in
    ""|*[!0-9.]*) return 1 ;;
  esac

  old_ifs="$IFS"
  IFS=.
  set -- $value
  IFS="$old_ifs"

  [ "$#" -eq 4 ] || return 1
  for octet in "$@"; do
    case "$octet" in
      ""|*[!0-9]*) return 1 ;;
    esac
    [ "$octet" -ge 0 ] 2>/dev/null || return 1
    [ "$octet" -le 255 ] 2>/dev/null || return 1
  done
  return 0
}

is_private_ipv4() {
  value="$1"
  case "$value" in
    10.*|192.168.*) return 0 ;;
    172.*)
      second="$(printf '%s' "$value" | cut -d. -f2)"
      [ "$second" -ge 16 ] 2>/dev/null && [ "$second" -le 31 ] 2>/dev/null
      return $?
      ;;
  esac
  return 1
}

append_unique_ip() {
  candidate="$1"
  valid_ipv4 "$candidate" || return 0
  [ "$candidate" != "127.0.0.1" ] || return 0
  if ! printf '%s\n' "$DETECTED_IPS" | grep -qx "$candidate"; then
    if [ -n "$DETECTED_IPS" ]; then
      DETECTED_IPS="${DETECTED_IPS}
${candidate}"
    else
      DETECTED_IPS="$candidate"
    fi
  fi
}

DETECTED_IPS=""

if command -v ipconfig >/dev/null 2>&1; then
  for interface in en0 en1; do
    candidate="$(ipconfig getifaddr "$interface" 2>/dev/null || true)"
    append_unique_ip "$candidate"
  done
fi

if command -v ifconfig >/dev/null 2>&1; then
  while IFS= read -r candidate; do
    append_unique_ip "$candidate"
  done <<EOF
$(ifconfig 2>/dev/null | awk '$1 == "inet" && $2 !~ /^127\./ {print $2}')
EOF
fi

LAN_IP=""
if valid_ipv4 "$REQUESTED_IP" && printf '%s\n' "$DETECTED_IPS" | grep -qx "$REQUESTED_IP"; then
  LAN_IP="$REQUESTED_IP"
fi

if [ -z "$LAN_IP" ]; then
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    if is_private_ipv4 "$candidate"; then
      LAN_IP="$candidate"
      break
    fi
  done <<EOF
$DETECTED_IPS
EOF
fi

if [ -z "$LAN_IP" ]; then
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    LAN_IP="$candidate"
    break
  done <<EOF
$DETECTED_IPS
EOF
fi

if [ -z "$LAN_IP" ]; then
  echo "LAN用IPv4アドレスを検出できません。MacをWi-Fiまたは有線LANへ接続してください。" >&2
  exit 2
fi

if [ -n "$REQUESTED_IP" ] && [ "$REQUESTED_IP" != "$LAN_IP" ]; then
  echo "注意: 指定IP ${REQUESTED_IP} はこのMacに割り当てられていません。" >&2
  echo "検出したIP ${LAN_IP} を使用します。" >&2
fi

CA_CONFIG="$(mktemp)"
SERVER_CONFIG="$(mktemp)"
trap 'rm -f "$CA_CONFIG" "$SERVER_CONFIG" "$SERVER_CSR"' EXIT

cat > "$CA_CONFIG" <<'EOF'
[req]
prompt = no
distinguished_name = distinguished_name
x509_extensions = v3_ca

[distinguished_name]
CN = Kakeibo Local CA
O = Kakeibo Local Development

[v3_ca]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always, issuer
EOF

if [ ! -s "$CA_KEY" ] || [ ! -s "$CA_CERT" ]; then
  echo "[certificate] ローカルCAを作成します"
  openssl genrsa -out "$CA_KEY" 3072 >/dev/null 2>&1
  openssl req \
    -x509 \
    -new \
    -sha256 \
    -key "$CA_KEY" \
    -days 3650 \
    -config "$CA_CONFIG" \
    -out "$CA_CERT"
fi

chmod 600 "$CA_KEY" 2>/dev/null || true
chmod 644 "$CA_CERT" 2>/dev/null || true
openssl x509 -in "$CA_CERT" -outform DER -out "$CA_CERT_DER"
chmod 644 "$CA_CERT_DER" 2>/dev/null || true

{
  cat <<'EOF'
[req]
prompt = no
distinguished_name = distinguished_name
req_extensions = request_extensions

[distinguished_name]
CN = kakeibo.local
O = Kakeibo Local Development

[request_extensions]
subjectAltName = @alternate_names

[v3_server]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid, issuer
subjectAltName = @alternate_names

[alternate_names]
DNS.1 = localhost
DNS.2 = kakeibo.local
IP.1 = 127.0.0.1
EOF

  index=2
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    echo "IP.${index} = ${candidate}"
    index=$((index + 1))
  done <<EOF
$DETECTED_IPS
EOF

  if valid_ipv4 "$REQUESTED_IP" && ! printf '%s\n' "$DETECTED_IPS" | grep -qx "$REQUESTED_IP"; then
    echo "IP.${index} = ${REQUESTED_IP}"
  fi
} > "$SERVER_CONFIG"

echo "[certificate] サーバー証明書を更新します（LAN IP: ${LAN_IP}）"
openssl genrsa -out "$SERVER_KEY" 2048 >/dev/null 2>&1
openssl req \
  -new \
  -sha256 \
  -key "$SERVER_KEY" \
  -config "$SERVER_CONFIG" \
  -out "$SERVER_CSR"
openssl x509 \
  -req \
  -sha256 \
  -in "$SERVER_CSR" \
  -CA "$CA_CERT" \
  -CAkey "$CA_KEY" \
  -CAcreateserial \
  -days 365 \
  -extfile "$SERVER_CONFIG" \
  -extensions v3_server \
  -out "$SERVER_CERT" >/dev/null

chmod 600 "$SERVER_KEY" 2>/dev/null || true
chmod 644 "$SERVER_CERT" 2>/dev/null || true
openssl verify -CAfile "$CA_CERT" "$SERVER_CERT" >/dev/null
printf '%s\n' "$LAN_IP" > "$LAN_IP_FILE"
chmod 600 "$LAN_IP_FILE" 2>/dev/null || true

cat <<EOF

HTTPS証明書を準備しました。
  LAN IP       : ${LAN_IP}
  公開CA証明書 : ${CA_CERT_DER}
  サーバー証明書: ${SERVER_CERT}
  秘密鍵       : ${SERVER_KEY}

秘密鍵は共有しないでください。スマホへ渡すのは .cer の公開CA証明書だけです。
EOF
