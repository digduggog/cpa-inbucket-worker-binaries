#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="${REPO_OWNER:-digduggog}"
REPO_NAME="${REPO_NAME:-cpa-inbucket-worker-binaries}"

COMPONENT="dist-register-inbucket"
ASSET_NAME="dist-register-inbucket-linux-amd64"
VERSION="latest"
INSTALL_DIR="$PWD/cpa-worker-runtime"
THREADS="20"
BACKGROUND="0"
SYSTEMD="0"
SERVICE_NAME="dist-register-inbucket"
PROXY=""
CPA_BASE_URL=""
CPA_TOKEN=""
MAIL_API_URL="https://mail.example.com/"
MAIL_API_KEY="replace-me"
MAIL_API_AUTH_MODE="bearer"
DOMAINS_API_URL=""

usage() {
  cat <<'EOF'
Usage:
  install.sh [options]

Options:
  --install-dir DIR
  --version latest|vX.Y.Z
  --background
  --systemd
  --service-name NAME
  --threads N
  --proxy URL
  --cpa-base-url URL
  --cpa-token TOKEN
  --mail-api-url URL
  --mail-api-key KEY
  --mail-api-auth-mode bearer|x-api-key|dual|none
  --domains-api-url URL
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --version) VERSION="${2:-}"; shift 2 ;;
    --background) BACKGROUND="1"; shift ;;
    --systemd) SYSTEMD="1"; shift ;;
    --service-name) SERVICE_NAME="${2:-}"; shift 2 ;;
    --threads) THREADS="${2:-}"; shift 2 ;;
    --proxy) PROXY="${2:-}"; shift 2 ;;
    --cpa-base-url) CPA_BASE_URL="${2:-}"; shift 2 ;;
    --cpa-token) CPA_TOKEN="${2:-}"; shift 2 ;;
    --mail-api-url) MAIL_API_URL="${2:-}"; shift 2 ;;
    --mail-api-key) MAIL_API_KEY="${2:-}"; shift 2 ;;
    --mail-api-auth-mode) MAIL_API_AUTH_MODE="${2:-}"; shift 2 ;;
    --domains-api-url) DOMAINS_API_URL="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd curl

if [[ "$SYSTEMD" == "1" && "$BACKGROUND" == "1" ]]; then
  echo "--systemd and --background cannot be used together." >&2
  exit 1
fi

if [[ -z "$CPA_BASE_URL" || -z "$CPA_TOKEN" ]]; then
  echo "--cpa-base-url and --cpa-token are required." >&2
  exit 1
fi

if [[ -z "$DOMAINS_API_URL" ]]; then
  DOMAINS_API_URL="${CPA_BASE_URL%/}/v0/management/domains"
fi

build_release_base() {
  if [[ "$VERSION" == "latest" ]]; then
    printf 'https://github.com/%s/%s/releases/latest/download' "$REPO_OWNER" "$REPO_NAME"
  else
    printf 'https://github.com/%s/%s/releases/download/%s' "$REPO_OWNER" "$REPO_NAME" "$VERSION"
  fi
}

json_escape() {
  local value="${1-}"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

RELEASE_BASE="$(build_release_base)"
BINARY_URL="${RELEASE_BASE}/${ASSET_NAME}"
CHECKSUM_URL="${RELEASE_BASE}/SHA256SUMS.txt"

mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/codex_tokens"

TMP_BINARY="$INSTALL_DIR/.${COMPONENT}.download.$$"
cleanup() {
  rm -f "$TMP_BINARY" "$INSTALL_DIR/SHA256SUMS.txt" "$INSTALL_DIR/SHA256SUMS.unix.txt"
}
trap cleanup EXIT

echo "Downloading ${ASSET_NAME}..."
curl -fL "$BINARY_URL" -o "$TMP_BINARY"
chmod +x "$TMP_BINARY"

if curl -fsSL "$CHECKSUM_URL" -o "$INSTALL_DIR/SHA256SUMS.txt"; then
  tr -d '\r' < "$INSTALL_DIR/SHA256SUMS.txt" > "$INSTALL_DIR/SHA256SUMS.unix.txt"
  expected="$(awk -v name="$ASSET_NAME" '$2 == name { print $1; exit }' "$INSTALL_DIR/SHA256SUMS.unix.txt")"
  if [[ -n "$expected" ]]; then
    if command -v sha256sum >/dev/null 2>&1; then
      actual="$(sha256sum "$TMP_BINARY" | awk '{print $1}')"
    elif command -v shasum >/dev/null 2>&1; then
      actual="$(shasum -a 256 "$TMP_BINARY" | awk '{print $1}')"
    else
      actual=""
    fi
    if [[ -n "$actual" && "$actual" != "$expected" ]]; then
      echo "Checksum verification failed." >&2
      exit 1
    fi
  fi
fi

mv -f "$TMP_BINARY" "$INSTALL_DIR/$COMPONENT"
chmod +x "$INSTALL_DIR/$COMPONENT"

cat > "$INSTALL_DIR/config.json" <<EOF
{
  "threads": ${THREADS},
  "proxy": "$(json_escape "$PROXY")",
  "verbose_logs": false,
  "oauth_required": true,
  "cpa_base_url": "$(json_escape "$CPA_BASE_URL")",
  "cpa_token": "$(json_escape "$CPA_TOKEN")",
  "upload_api_proxy": "",
  "mail_api_url": "$(json_escape "$MAIL_API_URL")",
  "mail_api_key": "$(json_escape "$MAIL_API_KEY")",
  "mail_api_auth_mode": "$(json_escape "$MAIL_API_AUTH_MODE")",
  "domains_api_url": "$(json_escape "$DOMAINS_API_URL")",
  "domains_refresh_interval_seconds": 600,
  "mail_poll_interval": 3,
  "mail_poll_timeout_seconds": 120,
  "request_timeout_seconds": 20,
  "local_retry_attempts": 2,
  "local_retry_backoff_seconds": 2.0,
  "registered_accounts_file": "registered_accounts.txt",
  "ak_file": "ak.txt",
  "rk_file": "rk.txt",
  "token_json_dir": "codex_tokens",
  "worker_log_file": "worker.log",
  "worker_pid_file": "worker.pid"
}
EOF

echo
echo "Installed to: $INSTALL_DIR"
echo "Binary: $INSTALL_DIR/$COMPONENT"
echo "Config: $INSTALL_DIR/config.json"

if [[ "$SYSTEMD" == "1" ]]; then
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "--systemd requires root." >&2
    exit 1
  fi
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemctl is not available on this host." >&2
    exit 1
  fi
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=${SERVICE_NAME}
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/${COMPONENT} --config ${INSTALL_DIR}/config.json
Environment=LANG=C.UTF-8
Environment=LC_ALL=C.UTF-8
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now "${SERVICE_NAME}.service"
  echo "Systemd service started."
  echo "Service: ${SERVICE_NAME}.service"
  echo "Check:"
  echo "  systemctl status ${SERVICE_NAME}.service"
  echo "  journalctl -u ${SERVICE_NAME}.service -f"
elif [[ "$BACKGROUND" == "1" ]]; then
  (
    cd "$INSTALL_DIR"
    LANG=C.UTF-8 LC_ALL=C.UTF-8 "./$COMPONENT" --config "$INSTALL_DIR/config.json" --background >/dev/null
  )
  echo "Background worker started."
  echo "Log: $INSTALL_DIR/worker.log"
  echo "PID: $INSTALL_DIR/worker.pid"
  echo "Check:"
  echo "  tail -f $INSTALL_DIR/worker.log"
  echo "  cat $INSTALL_DIR/worker.pid"
else
  echo "Start command:"
  echo "  cd \"$INSTALL_DIR\" && ./$COMPONENT --config \"$INSTALL_DIR/config.json\""
fi
