#!/usr/bin/env bash
set -euo pipefail

DAYS=3650
KEY_BITS=2048
OUT_DIR=""
ORG=""
OU=""
COUNTRY=""
STATE=""
LOCALITY=""
EMAIL=""
CN=""
EXTRA_SANS=""
PFX_PASS=""
ASSUME_YES=0
CONFIG_FILE=""

usage() {
  cat <<'EOF'
Usage: genssl.sh [options]

Options:
  -o, --out DIR      Output directory (default: certs)
  -n, --name NAME    Company / Organization name
  -c, --cn NAME      Common Name (default: detected IP)
  -s, --san LIST     Extra SANs, comma separated (e.g. 192.168.1.5,host.local)
  -d, --days N       Validity in days (default: 3650 = 10 years)
  -b, --bits N       RSA key size (default: 2048)
  -p, --pfx-pass P   Password for the IIS .pfx bundle (default: empty)
  -f, --config FILE  Company JSON file (default: company.json if present)
  -y, --yes          Accept defaults without prompting
  -h, --help         Show this help
EOF
}

if ! command -v openssl >/dev/null 2>&1; then
  echo "Error: openssl not found in PATH." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

json_value() {
  local key="$1" file="$2" line val
  line="$(grep -oE "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" 2>/dev/null | head -n1)"
  if [ -z "$line" ]; then
    line="$(grep -oE "\"${key}\"[[:space:]]*:[[:space:]]*[^,}[:space:]]+" "$file" 2>/dev/null | head -n1)"
  fi
  [ -n "$line" ] || return 0
  val="$(printf '%s' "$line" | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]]*$//')"
  case "$val" in
    \"*\")
      val="${val#\"}"
      val="${val%\"}"
      ;;
  esac
  printf '%s' "$val"
}

load_config() {
  local f="$1" v
  v="$(json_value organization "$f")";          if [ -n "$v" ]; then ORG="$v"; fi
  v="$(json_value organizational_unit "$f")";  if [ -n "$v" ]; then OU="$v"; fi
  v="$(json_value country "$f")";               if [ -n "$v" ]; then COUNTRY="$v"; fi
  v="$(json_value state "$f")";                 if [ -n "$v" ]; then STATE="$v"; fi
  v="$(json_value locality "$f")";              if [ -n "$v" ]; then LOCALITY="$v"; fi
  v="$(json_value email "$f")";                 if [ -n "$v" ]; then EMAIL="$v"; fi
  v="$(json_value common_name "$f")";           if [ -n "$v" ]; then CN="$v"; fi
  v="$(json_value san "$f")";                   if [ -n "$v" ]; then EXTRA_SANS="$v"; fi
  v="$(json_value days "$f")";                  if [ -n "$v" ]; then DAYS="$v"; fi
  v="$(json_value key_bits "$f")";              if [ -n "$v" ]; then KEY_BITS="$v"; fi
  v="$(json_value pfx_password "$f")";          if [ -n "$v" ]; then PFX_PASS="$v"; fi
  v="$(json_value out_dir "$f")";               if [ -n "$v" ]; then OUT_DIR="$v"; fi
}

_args=("$@")
_i=0
while [ "$_i" -lt "${#_args[@]}" ]; do
  case "${_args[$_i]}" in
    -f|--config) CONFIG_FILE="${_args[$((_i + 1))]:?}" ; _i=$((_i + 2)) ;;
    *) _i=$((_i + 1)) ;;
  esac
done
unset _args _i

if [ -n "$CONFIG_FILE" ]; then
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: config file not found: $CONFIG_FILE" >&2
    exit 1
  fi
elif [ -f "$SCRIPT_DIR/company.json" ]; then
  CONFIG_FILE="$SCRIPT_DIR/company.json"
fi

if [ -n "$CONFIG_FILE" ]; then
  load_config "$CONFIG_FILE"
  echo "Config: $CONFIG_FILE"
fi

while [ $# -gt 0 ]; do
  case "$1" in
    -o|--out) OUT_DIR="${2:?}"; shift 2 ;;
    -n|--name) ORG="${2:?}"; shift 2 ;;
    -c|--cn) CN="${2:?}"; shift 2 ;;
    -s|--san) EXTRA_SANS="${2:?}"; shift 2 ;;
    -d|--days) DAYS="${2:?}"; shift 2 ;;
    -b|--bits) KEY_BITS="${2:?}"; shift 2 ;;
    -p|--pfx-pass) PFX_PASS="${2-}"; shift 2 ;;
    -f|--config) shift 2 ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[ -n "$OUT_DIR" ] || OUT_DIR="certs"

ask() {
  local prompt="$1" def="$2" answer
  if [ "$ASSUME_YES" = 1 ]; then
    printf '%s\n' "$def"
    return
  fi
  if [ -n "$def" ]; then
    read -r -p "$prompt [$def]: " answer || true
    printf '%s\n' "${answer:-$def}"
  else
    read -r -p "$prompt: " answer || true
    printf '%s\n' "$answer"
  fi
}

is_ipv4() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

detect_ip() {
  local ip="" ps
  if command -v ip >/dev/null 2>&1; then
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
  fi
  if [ -z "$ip" ] && command -v powershell.exe >/dev/null 2>&1; then
    ps="$(powershell.exe -NoProfile -NonInteractive -Command \
      "\$r = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric,InterfaceMetric | Select-Object -First 1; if (\$r) { Get-NetIPAddress -InterfaceIndex \$r.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { \$_.IPAddress -notmatch '^(127\.|169\.254\.)' } | Select-Object -First 1 -ExpandProperty IPAddress }" \
      2>/dev/null | tr -d '\r')"
    if [ -z "$ps" ]; then
      ps="$(powershell.exe -NoProfile -NonInteractive -Command \
        "Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { \$_.IPAddress -notmatch '^(127\.|169\.254\.)' -and \$_.InterfaceAlias -notmatch 'vEthernet|Loopback|WSL|VirtualBox|VMware|Hyper-V|VPN' } | Select-Object -ExpandProperty IPAddress" \
        2>/dev/null | tr -d '\r')"
    fi
    ip="$(printf '%s\n' "$ps" | grep -E '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' | head -n1)"
    [ -n "$ip" ] || ip="$(printf '%s\n' "$ps" | grep -E '^[0-9.]+$' | grep -vE '^(127\.|169\.254\.|0\.)' | head -n1)"
  fi
  if [ -z "$ip" ] && command -v ipconfig >/dev/null 2>&1; then
    ip="$(ipconfig 2>/dev/null | tr -d '\r' | grep -iE 'IPv4|IPv4 Address' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -vE '^(127\.|169\.254\.|0\.|255\.)' | head -n1)"
  fi
  if [ -z "$ip" ] && command -v hostname >/dev/null 2>&1; then
    ip="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9.]+$' | grep -vE '^(127\.|169\.254\.)' | head -n1)"
  fi
  printf '%s\n' "${ip:-127.0.0.1}"
}

IP="$(detect_ip)"
HOSTNAME_SHORT="$(hostname 2>/dev/null | tr -d '\r' || true)"

echo "Detected IP: $IP"

ORG="$(ask 'Company / Organization' "$ORG")"
[ -n "$ORG" ] || ORG="Self-Signed"
OU="$(ask 'Department / OU' "${OU:-IT}")"
COUNTRY="$(ask 'Country code (2 letters)' "${COUNTRY:-US}")"
STATE="$(ask 'State / Province' "$STATE")"
LOCALITY="$(ask 'City / Locality' "$LOCALITY")"
EMAIL="$(ask 'Email address (optional)' "$EMAIL")"
CN="$(ask 'Common Name (CN)' "${CN:-$IP}")"
EXTRA_SANS="$(ask 'Extra SANs, comma separated (optional)' "$EXTRA_SANS")"
DAYS="$(ask 'Validity in days' "$DAYS")"
KEY_BITS="$(ask 'RSA key size' "$KEY_BITS")"
PFX_PASS="$(ask 'PFX password for IIS import (blank allowed)' "$PFX_PASS")"

SAN_ENTRIES=""
DNS_N=0
IP_N=0
add_san() {
  local v
  v="$(printf '%s' "$1" | tr -d '[:space:]')"
  [ -n "$v" ] || return 0
  if is_ipv4 "$v"; then
    IP_N=$((IP_N + 1))
    SAN_ENTRIES="${SAN_ENTRIES}IP.${IP_N} = ${v}"$'\n'
  else
    DNS_N=$((DNS_N + 1))
    SAN_ENTRIES="${SAN_ENTRIES}DNS.${DNS_N} = ${v}"$'\n'
  fi
}

add_san "$CN"
[ "$CN" = "$IP" ] || add_san "$IP"
add_san "localhost"
add_san "127.0.0.1"
[ -n "$HOSTNAME_SHORT" ] && add_san "$HOSTNAME_SHORT"
IFS=',' read -r -a _sans <<< "$EXTRA_SANS"
for s in ${_sans[@]+"${_sans[@]}"}; do
  add_san "$s"
done

mkdir -p "$OUT_DIR"
SAFE_CN="$(printf '%s' "$CN" | sed 's/[^A-Za-z0-9._-]/_/g')"
[ -n "$SAFE_CN" ] || SAFE_CN="cert"
KEY_FILE="$OUT_DIR/$SAFE_CN.key"
CRT_FILE="$OUT_DIR/$SAFE_CN.crt"
CFG_FILE="$OUT_DIR/$SAFE_CN.cnf"
PFX_FILE="$OUT_DIR/$SAFE_CN.pfx"
PEM_FILE="$OUT_DIR/$SAFE_CN-bundle.pem"

TMP_CFG="$(mktemp 2>/dev/null || echo "$OUT_DIR/.openssl.$$.cnf")"
trap 'rm -f "$TMP_CFG"' EXIT

{
  echo "[req]"
  echo "default_bits = $KEY_BITS"
  echo "prompt = no"
  echo "distinguished_name = dn"
  echo "x509_extensions = v3_req"
  echo "[dn]"
  echo "C = $COUNTRY"
  [ -n "$STATE" ] && echo "ST = $STATE"
  [ -n "$LOCALITY" ] && echo "L = $LOCALITY"
  echo "O = $ORG"
  [ -n "$OU" ] && echo "OU = $OU"
  echo "CN = $CN"
  [ -n "$EMAIL" ] && echo "emailAddress = $EMAIL"
  echo "[v3_req]"
  echo "basicConstraints = critical,CA:TRUE"
  echo "keyUsage = critical,digitalSignature,keyEncipherment,keyCertSign"
  echo "extendedKeyUsage = serverAuth"
  echo "subjectKeyIdentifier = hash"
  echo "authorityKeyIdentifier = keyid:always,issuer"
  echo "subjectAltName = @alt_names"
  echo "[alt_names]"
  printf '%s' "$SAN_ENTRIES"
} > "$TMP_CFG"

echo "Generating $DAYS-day self-signed certificate for CN=$CN ..."

openssl req -x509 -newkey "rsa:$KEY_BITS" -sha256 -nodes \
  -keyout "$KEY_FILE" -out "$CRT_FILE" \
  -days "$DAYS" -config "$TMP_CFG" -extensions v3_req 2>/dev/null

cp "$TMP_CFG" "$CFG_FILE"

cat "$CRT_FILE" "$KEY_FILE" > "$PEM_FILE"

rm -f "$PFX_FILE"
OPENSSL_PFX_PASS="$PFX_PASS" openssl pkcs12 -export \
  -inkey "$KEY_FILE" -in "$CRT_FILE" \
  -name "$CN" -out "$PFX_FILE" \
  -passout env:OPENSSL_PFX_PASS 2>/dev/null

chmod 600 "$KEY_FILE" "$PFX_FILE" "$PEM_FILE" 2>/dev/null || true
chmod 644 "$CRT_FILE" "$CFG_FILE" 2>/dev/null || true

echo
echo "Done."
echo "  Certificate: $CRT_FILE"
echo "  Private key: $KEY_FILE"
echo "  PEM bundle:  $PEM_FILE"
echo "  IIS PFX:     $PFX_FILE (password: ${PFX_PASS:-<blank>})"
echo "  Config:      $CFG_FILE"
echo
echo "IIS import: IIS Manager > Server Certificates > Import, or:"
echo "  certutil -f -p \"$PFX_PASS\" -importpfx \"$PFX_FILE\""
echo
openssl x509 -in "$CRT_FILE" -noout -subject -issuer -dates -ext subjectAltName
