#!/usr/bin/env bash
# ==============================================================================
# Vetka Node Agent - install.sh v1.2.6
# Caddy-forwardproxy-naive (amd64-only) + Mieru (mita) + fake-site + probe-resistance
# Supports: Ubuntu 20.04/22.04/24.04, Debian 11/12 | x86_64 only
# ==============================================================================
set -euo pipefail

# Capture all installer output to a log file
INSTALL_LOG="/var/log/vetka-node-agent-install.log"
mkdir -p "$(dirname "$INSTALL_LOG")"
exec > >(tee -a "$INSTALL_LOG") 2>&1
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] install.sh v1.2.6 started (PID $$)"

# Bug 19: ERR trap - log failure location and guide user to recovery
on_error() {
  local exit_code=$1 line=$2
  echo ""
  echo -e "${RED}${BOLD}========================================${NC}"
  echo -e "${RED}${BOLD}  install.sh FAILED (exit $exit_code at line $line)${NC}"
  echo -e "${RED}${BOLD}========================================${NC}"
  echo -e "  ${YELLOW}Install log:${NC} $INSTALL_LOG"
  echo -e "  ${YELLOW}Recovery options:${NC}"
  echo -e "    - Retry (idempotent):   ${CYAN}sudo bash install.sh --force${NC}"
  echo -e "    - Clean uninstall:      ${CYAN}sudo bash uninstall.sh${NC}"
  echo -e "    - View last 30 lines:   ${CYAN}tail -30 $INSTALL_LOG${NC}"
  echo ""
}
trap 'on_error $? $LINENO' ERR

# Colours
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "\n${CYAN}${BOLD}==> $*${NC}"; }
die()       { log_error "$*"; exit 1; }

# Source/runtime separation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
SOURCE_REPO_DIR="$SCRIPT_DIR"
PANEL_RUNTIME_DIR="/opt/vetka-node-agent"

# Constants
PANEL_DIR="$PANEL_RUNTIME_DIR"
PANEL_CONFIG="/etc/vetka-node-agent/config.json"
VERSION_FILE="/etc/vetka-node-agent/version"
BACKUP_DIR="/etc/vetka-node-agent/backups"
DB_PATH="/var/lib/vetka-node-agent/cache.sqlite"
MITA_STATE_FILE="/var/lib/vetka-node-agent/mita-state.json"
APPLIED_STATE_FILE="/var/lib/vetka-node-agent/state.json"
NODE_ID="${NODE_ID:-}"
NODE_SECRET="${NODE_SECRET:-}"
NODE_PORT="${NODE_PORT:-2222}"
NODE_LISTEN_HOST="${NODE_LISTEN_HOST:-0.0.0.0}"
PROTOCOL_TYPE="${PROTOCOL_TYPE:-naive}"
BACKEND_PANEL_IP="${BACKEND_PANEL_IP:-}"
ALLOW_LOCAL_USER_MUTATIONS="${ALLOW_LOCAL_USER_MUTATIONS:-false}"

# v1.2.3: Caddy-forwardproxy-naive replaces standalone naive binary
CADDY_BIN="/usr/local/bin/caddy-naive"
CADDY_CONFIG_DIR="/etc/caddy-naive"
CADDY_FILE="${CADDY_CONFIG_DIR}/Caddyfile"
CADDY_VERSION_FILE="${CADDY_CONFIG_DIR}/version"
FAKE_SITE_DIR="/var/www/fake-site"

# Legacy paths kept for migration/repair reference
NAIVE_BIN="/usr/local/bin/naive"        # may still exist from v1.2.x; will be removed
NAIVE_CONFIG_DIR="/etc/naive"

CURRENT_VERSION="1.2.6"
PANEL_REPO_URL="${PANEL_REPO_URL:-https://github.com/Daniil-GR/vetka-node-agent}"
PANEL_REPO_BRANCH="${PANEL_REPO_BRANCH:-main}"
REPO_URL="$PANEL_REPO_URL"
# Bug 1: direct download URL for caddy-forwardproxy-naive (amd64 only)
CADDY_NAIVE_RELEASES="https://api.github.com/repos/klzgrad/forwardproxy/releases/latest"
CADDY_NAIVE_FALLBACK_URL="https://github.com/klzgrad/forwardproxy/releases/download/v2.10.0-naive/caddy-forwardproxy-naive.tar.xz"
MIERU_RELEASES="https://api.github.com/repos/enfein/mieru/releases/latest"
CADDY_MODE="${CADDY_MODE:-vetka}"
VETKA_CADDY_REPO="${VETKA_CADDY_REPO:-https://github.com/Daniil-GR/caddy-forwardproxy-vetka.git}"
VETKA_CADDY_BRANCH="${VETKA_CADDY_BRANCH:-naive}"
VETKA_CADDY_BUILD_DIR="${VETKA_CADDY_BUILD_DIR:-/opt/caddy-forwardproxy-vetka}"

# Flags
NON_INTERACTIVE=false
FORCE_INSTALL=false
STATIC_SITE_ENABLED=false
STATIC_SITE_SOURCE_TYPE="archive_url"
STATIC_SITE_SOURCE_URL=""
STATIC_SITE_ROOT=""
STATIC_SITE_DEPLOY_ON_INSTALL=true
STATIC_SITE_DEPLOY_ON_UPDATE="missing-only"
STATIC_SITE_CREATE_IF_MISSING=true

parse_install_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --non-interactive|--force|-y) NON_INTERACTIVE=true; FORCE_INSTALL=true ;;
      --domain)         INPUT_DOMAIN="${2:-}";          shift ;;
      --email)          INPUT_EMAIL="${2:-}";           shift ;;
      --admin-user)     INPUT_ADMIN_USER="${2:-}";      shift ;;
      --admin-pass)     INPUT_ADMIN_PASS="${2:-}";      shift ;;
      --naive-port)     INPUT_NAIVE_PORT="${2:-}";      shift ;;
      --mieru-start)    INPUT_MIERU_START="${2:-}";     shift ;;
      --mieru-end)      INPUT_MIERU_END="${2:-}";       shift ;;
      --fake-site-url)  INPUT_FAKE_SITE_URL="${2:-}";   shift ;;
      --static-site-url) INPUT_STATIC_SITE_URL="${2:-}"; shift ;;
      --static-site-root) INPUT_STATIC_SITE_ROOT="${2:-}"; shift ;;
      --skip-static-site) INPUT_STATIC_SITE_SKIP=true ;;
      --probe-secret)   INPUT_PROBE_SECRET="${2:-}";    shift ;;
      --probe-mode)     INPUT_PROBE_MODE="${2:-}";      shift ;;
      --lang)
        case "${2:-en}" in ru) LANG_RU=false ;; *) LANG_RU=false ;; esac
        shift ;;
      --help|-h)
        echo "Usage: bash install.sh [--non-interactive] [--domain DOMAIN] [--email EMAIL]"
        echo "                       [--admin-user USER] [--admin-pass PASS]"
        echo "                       [--naive-port PORT] [--mieru-start PORT] [--mieru-end PORT]"
        echo "                       [--fake-site-url URL] [--static-site-url URL]"
        echo "                       [--static-site-root PATH] [--skip-static-site] [--probe-secret SECRET]"
        echo "                       [--lang en]"
        exit 0 ;;
      *) log_warn "Unknown argument: $1 (ignored)" ;;
    esac
    shift
  done
}

# i18n
LANG_RU=false

# Root check
[[ $EUID -ne 0 ]] && die "Run as root (sudo bash install.sh)"

validate_install_source() {
  [[ -n "$SOURCE_REPO_DIR" ]] || die "Cannot determine install.sh source directory"
  if [[ "$SOURCE_REPO_DIR" == "$PANEL_RUNTIME_DIR" ]]; then
    die "Do not run install.sh from /opt/vetka-node-agent. Clone the repository to /opt/vetka-node-agent-src or /tmp/vetka-node-agent and run install.sh from there."
  fi
  if [[ ! -d "$SOURCE_REPO_DIR/panel" ]]; then
    die "Source panel directory not found: $SOURCE_REPO_DIR/panel"
  fi
}

# Language selection
select_language() {
  if $NON_INTERACTIVE; then return; fi
  echo ""
  echo -e "${BOLD}========================================${NC}"
  echo -e "${BOLD}  Vetka Node Agent v${CURRENT_VERSION}${NC}"
  echo -e "${BOLD}========================================${NC}"
  echo ""
  log_info "Language: English (ASCII-compatible output)"
}

check_os() {
  log_step "Checking OS compatibility"
  [[ ! -f /etc/os-release ]] && die "Cannot determine OS"
  source /etc/os-release
  case "$ID" in
    ubuntu)
      case "$VERSION_ID" in
        20.04|22.04|24.04) log_info "OS: Ubuntu $VERSION_ID OK" ;;
        *) die "Unsupported Ubuntu: $VERSION_ID" ;;
      esac ;;
    debian)
      case "$VERSION_ID" in
        11|12) log_info "OS: Debian $VERSION_ID OK" ;;
        *) die "Unsupported Debian: $VERSION_ID" ;;
      esac ;;
    *) die "Unsupported OS: $ID" ;;
  esac
}

# Architecture detection - amd64 only for caddy-naive
detect_arch() {
  log_step "Detecting architecture"
  local machine; machine=$(uname -m)
  case "$machine" in
    x86_64|amd64) ARCH="amd64"; DEB_ARCH="amd64" ;;
#
    aarch64|arm64) die "caddy-forwardproxy-naive only supports amd64. ARM64 is not supported in v1.2.6." ;;
    armv7l) die "caddy-forwardproxy-naive only supports amd64. ARMv7 is not supported in v1.2.6." ;;
    *) die "Unsupported architecture: $machine" ;;
  esac
  log_info "Architecture: $machine -> $ARCH OK"
}

tune_network() {
  local helper="${SOURCE_REPO_DIR}/panel/scripts/sysctl_tune.sh"
  if [[ -f "$helper" ]]; then
    bash "$helper" || log_warn "Network tuning failed/skipped"
  else
    log_warn "Network tuning helper not found; skipping"
  fi
}

# Idempotent check
check_existing() {
  if [[ -f "$PANEL_CONFIG" ]]; then
    log_warn "Existing installation detected!"
    if $NON_INTERACTIVE || $FORCE_INSTALL; then
      log_info "--force: proceeding with reinstall."
    else
      echo ""
      read -rp "  Reinstall over existing? [y/N]: " REINSTALL
      local ans="${REINSTALL:-N}"
      if false; then
        [[ "${ans^^}" =~ ^(Y)$ ]] || { log_info "Aborted."; exit 0; }
      else
        [[ "${ans^^}" == "Y" ]] || { log_info "Aborted."; exit 0; }
      fi
    fi
#
    local ts; ts=$(date +%Y-%m-%d-%H%M%S)
    local bdir="$BACKUP_DIR/$ts"
    mkdir -p "$bdir"
    [[ -f "$CADDY_FILE"       ]] && cp "$CADDY_FILE"       "$bdir/" || true
    [[ -f "$MITA_STATE_FILE"  ]] && cp "$MITA_STATE_FILE"  "$bdir/" || true
    [[ -f "$PANEL_CONFIG"     ]] && cp "$PANEL_CONFIG"     "$bdir/" || true
    log_info "Backup created: $bdir"
  fi
}

# NTP sync
sync_time() {
  log_step "Synchronising system time (NTP)"
  log_warn "IMPORTANT: Mieru requires accurate system time (+/-30 s). NTP sync is critical!"
  timedatectl set-ntp true 2>/dev/null || true
  local synced=false
  for i in $(seq 1 15); do
    if timedatectl status 2>/dev/null | grep -q "synchronized: yes"; then
      synced=true; break
    fi
    sleep 1
  done
  if $synced; then
    log_info "Time synchronised OK"
  else
    log_warn "Sync not confirmed within 15 s!"
  fi
}

# Package dependencies
install_deps() {
  log_step "Installing dependencies"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
#
  apt-get install -y -qq \
    curl wget git ufw unzip tar xz-utils jq \
    ca-certificates gnupg lsb-release \
    systemd cron net-tools iproute2 \
    coreutils acl 2>/dev/null || \
  apt-get install -y \
    curl wget git ufw unzip tar xz-utils jq \
    ca-certificates gnupg lsb-release \
    systemd cron net-tools iproute2 \
    coreutils acl
  log_info "Dependencies installed OK"
}

# Node.js 20 LTS + PM2
install_nodejs() {
  log_step "Installing Node.js 20 LTS"
  if command -v node &>/dev/null && node --version | grep -qE "^v2[0-9]"; then
    log_info "Node.js $(node --version) - already installed OK"
  else
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
    log_info "Node.js $(node --version) installed OK"
  fi
  if command -v pm2 &>/dev/null; then
    log_info "PM2 $(pm2 --version) - already installed OK"
  else
    npm install -g pm2 --silent
    log_info "PM2 installed OK"
  fi
}

# Caddy-forwardproxy-naive binary
ensure_xcaddy() {
  if ! command -v git &>/dev/null || ! command -v go &>/dev/null || ! command -v strings &>/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git golang-go build-essential ca-certificates binutils
  fi
  if ! command -v xcaddy &>/dev/null; then
    GOBIN=/usr/local/bin go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
  fi
}

verify_vetka_caddy() {
  local caddy_bin="${1:-$CADDY_BIN}"
  local test_cfg; test_cfg=$(mktemp /tmp/vetka-caddy-XXXXXX.Caddyfile)
  local adapt_err; adapt_err=$(mktemp /tmp/vetka-caddy-adapt-XXXXXX.err)
  cat > "$test_cfg" <<'CADDYTEST'
:0 {
  forward_proxy {
    auth_audit_log /tmp/auth-audit.log
    traffic_audit_log /tmp/traffic-audit.log
  }
}
CADDYTEST
  local adapt_out=""
  if ! adapt_out=$("$caddy_bin" adapt --config "$test_cfg" --adapter caddyfile 2>"$adapt_err"); then
    log_error "Vetka Caddy adapt failed:"
    cat "$adapt_err" >&2 || true
    echo "$adapt_out" >&2
    rm -f "$test_cfg" "$adapt_err"
    return 1
  fi
  local ok=true
  if echo "$adapt_out" | grep -q '"auth_audit_log"'; then
    log_info "Vetka Caddy supports auth_audit_log OK"
  else
    log_error "Vetka Caddy adapt output does not contain auth_audit_log"
    ok=false
  fi
  if echo "$adapt_out" | grep -q '"traffic_audit_log"'; then
    log_info "Vetka Caddy supports traffic_audit_log OK"
  else
    log_error "Vetka Caddy adapt output does not contain traffic_audit_log"
    ok=false
  fi
  if $ok; then
    rm -f "$test_cfg" "$adapt_err"
    return 0
  fi
  log_error "adapt stderr:"
  cat "$adapt_err" >&2 || true
  log_error "adapt stdout:"
  echo "$adapt_out" >&2
  strings "$caddy_bin" | grep -q 'auth_audit_log' || log_error "Binary strings do not contain auth_audit_log."
  strings "$caddy_bin" | grep -q 'traffic_audit_log' || log_error "Binary strings do not contain traffic_audit_log."
  rm -f "$test_cfg" "$adapt_err"
  return 1
}

install_vetka_caddy_naive() {
  log_step "Installing Vetka patched caddy-forwardproxy"
  ensure_xcaddy
  if [[ -d "$VETKA_CADDY_BUILD_DIR/.git" ]]; then
    git -C "$VETKA_CADDY_BUILD_DIR" fetch origin "$VETKA_CADDY_BRANCH"
    git -C "$VETKA_CADDY_BUILD_DIR" checkout "$VETKA_CADDY_BRANCH"
    git -C "$VETKA_CADDY_BUILD_DIR" reset --hard "origin/$VETKA_CADDY_BRANCH"
  else
    rm -rf "$VETKA_CADDY_BUILD_DIR"
    git clone --depth 1 --branch "$VETKA_CADDY_BRANCH" "$VETKA_CADDY_REPO" "$VETKA_CADDY_BUILD_DIR"
  fi

  local tmp_dir; tmp_dir=$(mktemp -d)
  xcaddy build --output "$tmp_dir/caddy-naive" \
    --with "github.com/caddyserver/forwardproxy@master=${VETKA_CADDY_BUILD_DIR}"
  verify_vetka_caddy "$tmp_dir/caddy-naive" || die "Vetka Caddy build does not support auth_audit_log"
  install -m 755 "$tmp_dir/caddy-naive" "$CADDY_BIN"
  rm -rf "$tmp_dir"

  if command -v setcap &>/dev/null; then
    setcap 'cap_net_bind_service=+ep' "$CADDY_BIN" 2>/dev/null || true
  fi
  CADDY_VERSION=$("$CADDY_BIN" version 2>/dev/null | head -1 || echo "vetka-${VETKA_CADDY_BRANCH}")
  log_info "Vetka caddy-naive installed -> $CADDY_BIN ($CADDY_VERSION) OK"
  export CADDY_VERSION
}

install_upstream_caddy_naive() {
  log_step "Installing upstream caddy-forwardproxy-naive"

  local tmp_dir; tmp_dir=$(mktemp -d)
  local archive_path="${tmp_dir}/caddy-forwardproxy-naive.tar.xz"

  log_info "Fetching latest release from GitHub..."
  local asset_url=""
  local release_tag="unknown"

#
  local release_json=""
  release_json=$(curl -fsSL --connect-timeout 10 "$CADDY_NAIVE_RELEASES" 2>/dev/null) || true

  if [[ -n "$release_json" ]]; then
    release_tag=$(echo "$release_json" | jq -r '.tag_name // "unknown"')
    log_info "Latest release: $release_tag"

#
    asset_url=$(echo "$release_json" | jq -r \
      '.assets[] | select(.name | test("caddy.*forwardproxy.*naive.*\\.tar\\.xz$|caddy-forwardproxy-naive.*\\.tar\\.xz$"; "i")) | .browser_download_url' \
      | head -1)

#
    if [[ -z "$asset_url" ]]; then
      asset_url=$(echo "$release_json" | jq -r \
        '.assets[] | select(.name | endswith(".tar.xz")) | .browser_download_url' | head -1)
    fi
  fi

#
  if [[ -z "$asset_url" ]]; then
    log_warn "GitHub API unavailable - using fallback URL (v2.10.0)"
    asset_url="$CADDY_NAIVE_FALLBACK_URL"
    release_tag="v2.10.0-naive"
  fi

  log_info "Downloading: $asset_url"
  wget -q --show-progress --connect-timeout 30 -O "$archive_path" "$asset_url" || \
    die "Failed to download caddy-forwardproxy-naive"

#
  cd "$tmp_dir"
  tar -xJf "$archive_path" 2>/dev/null || tar -xf "$archive_path" 2>/dev/null || \
    die "Failed to extract archive"

#
  local caddy_found
  caddy_found=$(find "$tmp_dir" -maxdepth 3 -type f \
    \( -name "caddy" -o -name "caddy-naive" -o -name "caddy-forwardproxy-naive" \) \
    ! -name "*.xz" ! -name "*.gz" ! -name "*.tar" | head -1)

  [[ -z "$caddy_found" ]] && \
    die "caddy binary not found in archive"

  install -m 755 "$caddy_found" "$CADDY_BIN"
  rm -rf "$tmp_dir"; cd /

#
  if command -v setcap &>/dev/null; then
    setcap 'cap_net_bind_service=+ep' "$CADDY_BIN" 2>/dev/null || true
  fi

#
  CADDY_VERSION=$("$CADDY_BIN" version 2>/dev/null | head -1 || \
                  "$CADDY_BIN" --version 2>/dev/null | head -1 || echo "$release_tag")
  log_info "caddy-naive installed -> $CADDY_BIN  ($CADDY_VERSION) OK"
  export CADDY_VERSION

#
  if [[ -f "$NAIVE_BIN" ]]; then
    log_info "Removing legacy naive binary (v1.2.x)..."
    rm -f "$NAIVE_BIN"
  fi
}

install_caddy_naive() {
  case "${CADDY_MODE:-vetka}" in
    vetka) install_vetka_caddy_naive ;;
    upstream) install_upstream_caddy_naive ;;
    *) die "Unsupported CADDY_MODE=${CADDY_MODE}. Use vetka or upstream." ;;
  esac
}

# Mieru (mita) via .deb
install_mieru() {
  log_step "Installing Mieru (mita)"
  log_info "Fetching latest release..."
  local release_json
  release_json=$(curl -fsSL "$MIERU_RELEASES") || \
    die "Cannot fetch Mieru releases"
  local tag; tag=$(echo "$release_json" | jq -r '.tag_name')
  log_info "Latest Mieru: $tag"

  local asset_url
  asset_url=$(echo "$release_json" | jq -r \
    --arg arch "$DEB_ARCH" \
    '.assets[] | select(.name | test("mita.*" + $arch + "\\.deb")) | .browser_download_url' | head -1)
  [[ -z "$asset_url" ]] && \
    asset_url=$(echo "$release_json" | jq -r \
      --arg arch "$DEB_ARCH" \
      '.assets[] | select(.name | test($arch + "\\.deb")) | .browser_download_url' | head -1)
  [[ -z "$asset_url" ]] && die "No Mieru .deb for $DEB_ARCH"

  local deb_file; deb_file=$(mktemp /tmp/mieru-XXXXXX.deb)
  log_info "Downloading: $asset_url"
  wget -q --show-progress -O "$deb_file" "$asset_url" || \
    die "Failed to download Mieru .deb"
  local policy_rc_created=false
  if [[ ! -e /usr/sbin/policy-rc.d ]]; then
    cat > /usr/sbin/policy-rc.d <<'POLICYRC'
#!/bin/sh
exit 101
POLICYRC
    chmod +x /usr/sbin/policy-rc.d
    policy_rc_created=true
  fi
  local install_ok=true
  dpkg -i "$deb_file" 2>/dev/null || apt-get install -f -y || install_ok=false
  if $policy_rc_created; then rm -f /usr/sbin/policy-rc.d; fi
  $install_ok || die "Failed to install Mieru .deb"
  rm -f "$deb_file"
  systemctl stop mita 2>/dev/null || true
  systemctl reset-failed mita 2>/dev/null || true
  MIERU_VERSION=$(mita version 2>/dev/null | grep -oP 'v[\d.]+' | head -1 || echo "$tag")
  log_info "mita installed ($MIERU_VERSION) OK"
}

# Interactive / non-interactive config gathering
gather_config() {
  log_step "Configuration"

  if $NON_INTERACTIVE; then
    DOMAIN="${INPUT_DOMAIN:->$(die "--domain is required in --non-interactive mode")}"
    ADMIN_EMAIL="${INPUT_EMAIL:-admin@${DOMAIN}}"
    NAIVE_PORT="${INPUT_NAIVE_PORT:-443}"
    MIERU_PORT_START="${INPUT_MIERU_START:-2012}"
    MIERU_PORT_END="${INPUT_MIERU_END:-2022}"
    ADMIN_USER="${INPUT_ADMIN_USER:-admin}"
    if [[ -z "${INPUT_ADMIN_PASS:-}" ]]; then
      ADMIN_PASS=$(openssl rand -base64 18 | tr -d '/+=' | head -c 20)
      log_info "Generated password: ${BOLD}$ADMIN_PASS${NC}"
    else
      ADMIN_PASS="$INPUT_ADMIN_PASS"
    fi
#
    FAKE_SITE_URL="${INPUT_FAKE_SITE_URL:-https://www.example.com}"
    if [[ "${INPUT_STATIC_SITE_SKIP:-false}" == "true" ]]; then
      STATIC_SITE_ENABLED=false
      STATIC_SITE_SOURCE_TYPE="skip"
      STATIC_SITE_SOURCE_URL=""
      STATIC_SITE_ROOT="${INPUT_STATIC_SITE_ROOT:-}"
      STATIC_SITE_DEPLOY_ON_INSTALL=false
    else
      STATIC_SITE_SOURCE_URL="${INPUT_STATIC_SITE_URL:-}"
      STATIC_SITE_ROOT="${INPUT_STATIC_SITE_ROOT:-}"
      if [[ -z "${INPUT_STATIC_SITE_URL:-}" ]]; then
        STATIC_SITE_ENABLED=false
        STATIC_SITE_SOURCE_TYPE="skip"
        STATIC_SITE_SOURCE_URL=""
        STATIC_SITE_DEPLOY_ON_INSTALL=false
        log_warn "Static site URL is empty; managed static site disabled"
      else
        STATIC_SITE_ENABLED=true
        STATIC_SITE_SOURCE_TYPE="archive_url"
        STATIC_SITE_DEPLOY_ON_INSTALL=true
      fi
    fi
    PROBE_SECRET="${INPUT_PROBE_SECRET:-$(openssl rand -hex 16)}"
#
    PROBE_MODE="${INPUT_PROBE_MODE:-bare}"
    USE_UFW="Y"
    EXPOSE_PANEL="N"
    log_info "Configuration loaded from arguments OK"
    return
  fi

  echo ""
  echo ""
  echo -e "${BOLD}========================================${NC}"
  echo -e "${BOLD}  Vetka Node Agent - Setup Wizard${NC}"
  echo -e "${BOLD}========================================${NC}"
  echo ""

#
  read -rp "$(echo -e "${CYAN}Domain${NC} (e.g. vpn.example.com): ")" INPUT_DOMAIN
  [[ -z "${INPUT_DOMAIN:-}" ]] && die "Domain cannot be empty"
  DOMAIN="$INPUT_DOMAIN"

#
  read -rp "$(echo -e "${CYAN}Email for ACME/TLS (Caddy)${NC}: ")" INPUT_EMAIL
  [[ -z "${INPUT_EMAIL:-}" ]] && die "Email cannot be empty"
  ADMIN_EMAIL="$INPUT_EMAIL"

#
  read -rp "$(echo -e "${CYAN}NaiveProxy HTTPS port${NC} [443]: ")" INPUT_NAIVE_PORT
  NAIVE_PORT="${INPUT_NAIVE_PORT:-443}"
  if ! [[ "$NAIVE_PORT" =~ ^[0-9]+$ ]] || (( NAIVE_PORT < 1 || NAIVE_PORT > 65535 )); then
    die "Invalid port: $NAIVE_PORT"
  fi

#
  echo ""
  echo -e "${YELLOW}Mieru uses a TCP port range. Default: 2012-2022${NC}"
  read -rp "$(echo -e "${CYAN}Mieru start port${NC} [2012]: ")" INPUT_MIERU_START
  MIERU_PORT_START="${INPUT_MIERU_START:-2012}"
  read -rp "$(echo -e "${CYAN}Mieru end port${NC}  [2022]: ")" INPUT_MIERU_END
  MIERU_PORT_END="${INPUT_MIERU_END:-2022}"
  for p in "$MIERU_PORT_START" "$MIERU_PORT_END"; do
    if ! [[ "$p" =~ ^[0-9]+$ ]] || (( p < 1025 || p > 65535 )); then
      die "Invalid Mieru port: $p (1025-65535)"
    fi
  done
  (( MIERU_PORT_END < MIERU_PORT_START )) && \
    die "End port must be >= start port"

#
  echo ""
  echo -e "${YELLOW}Fake site: Caddy shows this site to unrecognised clients (probe resistance).${NC}"
  read -rp "$(echo -e "${CYAN}Fake site URL${NC} [https://www.example.com]: ")" INPUT_FAKE_SITE_URL
  FAKE_SITE_URL="${INPUT_FAKE_SITE_URL:-https://www.example.com}"

  echo ""
  read -rp "$(echo -e "${CYAN}Configure static placeholder site->${NC} [Y/n]: ")" INPUT_STATIC_SITE_ENABLE
  if [[ ! "${INPUT_STATIC_SITE_ENABLE:-Y}" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]; then
    STATIC_SITE_ENABLED=false
    STATIC_SITE_SOURCE_TYPE="skip"
    STATIC_SITE_SOURCE_URL=""
    STATIC_SITE_ROOT=""
    STATIC_SITE_DEPLOY_ON_INSTALL=false
  else
    STATIC_SITE_ENABLED=true
    STATIC_SITE_ROOT=""
    STATIC_SITE_DEPLOY_ON_INSTALL=true
    echo "  1) archive_url"
    echo "  2) skip"
    read -rp "$(echo -e "${CYAN}Static site source type${NC} [1]: ")" INPUT_STATIC_SITE_TYPE
    case "${INPUT_STATIC_SITE_TYPE:-1}" in
      2|skip)
        STATIC_SITE_ENABLED=false
        STATIC_SITE_SOURCE_TYPE="skip"
        STATIC_SITE_SOURCE_URL=""
        STATIC_SITE_DEPLOY_ON_INSTALL=false
        ;;
      *)
        STATIC_SITE_SOURCE_TYPE="archive_url"
        read -rp "$(echo -e "${CYAN}dist.tar.gz archive URL${NC}: ")" INPUT_STATIC_SITE_URL
        STATIC_SITE_SOURCE_URL="${INPUT_STATIC_SITE_URL:-}"
        if [[ -z "$STATIC_SITE_SOURCE_URL" ]]; then
          STATIC_SITE_ENABLED=false
          STATIC_SITE_SOURCE_TYPE="skip"
          STATIC_SITE_SOURCE_URL=""
          STATIC_SITE_DEPLOY_ON_INSTALL=false
          log_warn "Static site URL is empty; managed static site disabled"
        fi
        ;;
    esac
  fi

#
  echo ""
  echo -e "${YELLOW}Probe secret: clients present this secret in an HTTP header for identification.${NC}"
  read -rp "$(echo -e "${CYAN}Probe secret (blank = auto)${NC}: ")" INPUT_PROBE_SECRET
  if [[ -z "${INPUT_PROBE_SECRET:-}" ]]; then
    PROBE_SECRET=$(openssl rand -hex 16)
    log_info "Generated probe_secret: ${BOLD}${PROBE_SECRET}${NC}"
  else
    PROBE_SECRET="$INPUT_PROBE_SECRET"
  fi
#
#
  PROBE_MODE="${INPUT_PROBE_MODE:-bare}"

#
  echo ""
  read -rp "$(echo -e "${CYAN}Panel admin username${NC} [admin]: ")" INPUT_ADMIN_USER
  ADMIN_USER="${INPUT_ADMIN_USER:-admin}"
  read -rsp "$(echo -e "${CYAN}Panel admin password${NC} (blank = auto-generate): ")" INPUT_ADMIN_PASS
  echo ""
  if [[ -z "${INPUT_ADMIN_PASS:-}" ]]; then
    ADMIN_PASS=$(openssl rand -base64 18 | tr -d '/+=' | head -c 20)
    log_info "Generated password: ${BOLD}$ADMIN_PASS${NC}"
  else
    ADMIN_PASS="$INPUT_ADMIN_PASS"
  fi

#
  echo ""
  read -rp "$(echo -e "${CYAN}Configure UFW firewall->${NC} [Y/n]: ")" INPUT_UFW
  USE_UFW="${INPUT_UFW:-Y}"

#
  echo ""
  echo -e "${YELLOW}Node Agent listens on NODE_PORT; expose it only to the Backend Panel IP.${NC}"
  read -rp "$(echo -e "${CYAN}Expose panel publicly on port 8080->${NC} [y/N]: ")" INPUT_EXPOSE
  EXPOSE_PANEL="${INPUT_EXPOSE:-N}"

  echo ""
  log_info "Configuration gathered OK"
}

# Bug 1: Setup fake site
setup_fake_site() {
  if [[ "${STATIC_SITE_ENABLED:-false}" == "true" ]]; then
    FAKE_SITE_DIR="${STATIC_SITE_ROOT:-/var/www/${DOMAIN}/dist}"
    log_info "Managed static site enabled; Caddy root will be $FAKE_SITE_DIR"
    if [[ "${STATIC_SITE_CREATE_IF_MISSING:-true}" == "true" ]]; then
      mkdir -p "$FAKE_SITE_DIR"
      chmod 755 "$(dirname "$FAKE_SITE_DIR")" "$FAKE_SITE_DIR" 2>/dev/null || true
    fi
    return 0
  fi
  log_step "Setting up fake site (probe resistance)"
  mkdir -p "$FAKE_SITE_DIR"
  cat > "${FAKE_SITE_DIR}/index.html" <<FAKEHTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Welcome</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: system-ui, -apple-system, sans-serif; background: #f5f5f5;
           display: flex; align-items: center; justify-content: center;
           min-height: 100vh; color: #333; }
    .container { text-align: center; padding: 2rem; }
    h1 { font-size: 2rem; margin-bottom: 0.5rem; }
    p  { color: #666; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Welcome</h1>
    <p>This service is currently unavailable. Please try again later.</p>
  </div>
</body>
</html>
FAKEHTML

  chmod 644 "${FAKE_SITE_DIR}/index.html"
  log_info "Fake site created -> $FAKE_SITE_DIR OK"
}

# Write Caddyfile (TLS-ALPN-01, forwardproxy, probe-resistance)
# Bug 23: forward_proxy credential lines use basic_auth <user> <pass> (with
# underscore). The bare "basic_auth" keyword with no arguments is
# invalid in caddy-forwardproxy-naive and causes:
# "wrong argument count or unexpected line ending after 'basic_auth'"
# Bug 24: caddy validate failure is fatal (die), not a warning.
# Bug 26: template rendered via caddyTemplate.js - single source of truth.
# Bug 27: backup existing Caddyfile; restore DB users when --force.
# Bug 28: no tls <email> in site block - Caddy handles TLS automatically.
# Bug 29: directive order inside forward_proxy: basic_auth -> hide_ip -> hide_via -> probe_resistance.
# Bug 30: global order forward_proxy before file_server.
# Bug 33: DNS check - warn if domain doesn't resolve to server IP.
# Bug 38: log rotation uses roll_keep_for 720h (30 days).
write_caddyfile() {
  log_step "Writing Caddyfile"
#
#
  mkdir -p "$CADDY_CONFIG_DIR"

#
  if [[ -f "$CADDY_FILE" ]]; then
    local ts; ts=$(date +%Y%m%d-%H%M%S)
    cp "$CADDY_FILE" "${CADDY_FILE}.bak.${ts}" 2>/dev/null || true
    log_info "Caddyfile backup: ${CADDY_FILE}.bak.${ts}"
  fi

#
  local server_ip_check
  server_ip_check=$(curl -4 -fsSL --connect-timeout 5 https://api.ipify.org 2>/dev/null \
                    || hostname -I | awk '{print $1}')
  local dns_ip
  dns_ip=$(getent hosts "$DOMAIN" 2>/dev/null | awk '{print $1; exit}' || true)
  if [[ -n "$dns_ip" && "$dns_ip" != "$server_ip_check" ]]; then
    log_warn "DNS: $DOMAIN -> $dns_ip (server: $server_ip_check) - verify your A record is correct!"
  elif [[ -z "$dns_ip" ]]; then
    log_warn "DNS: $DOMAIN does not resolve - ensure your A record points to this server"
  else
    log_info "DNS: $DOMAIN -> $dns_ip OK"
  fi

#
#
  local naive_users_json="[]"
  if [[ -f "$DB_PATH" ]] && command -v node &>/dev/null; then
#
#
    naive_users_json=$(cd "$PANEL_DIR" 2>/dev/null && node -e "
      try {
        const Database = require('better-sqlite3');
        const db = new Database('$DB_PATH', { readonly: true });
        const rows = db.prepare('SELECT username, password, protocols FROM users').all()
          .filter(u => {
            try { return JSON.parse(u.protocols || '[\"naive\",\"mieru\"]').includes('naive'); }
            catch { return true; }
          });
        process.stdout.write(JSON.stringify(rows.map(u => ({ username: u.username, password: u.password }))));
        db.close();
      } catch(e) { process.stdout.write('[]'); }
    " 2>/dev/null || echo '[]')
  fi

#
  local template_js="${PANEL_DIR}/server/caddyTemplate.js"
  local caddyfile_content
  local panel_listen_port="${NODE_PORT:-2222}"

#
  if [[ -f "$template_js" ]] && command -v node &>/dev/null; then
    caddyfile_content=$(STATIC_SITE_ROOT="$STATIC_SITE_ROOT" node -e "
      const t = require('$template_js');
      const users = $naive_users_json;
      const cfg = {
        adminEmail:  '${ADMIN_EMAIL}',
        domain:      '${DOMAIN}',
        naivePort:   ${NAIVE_PORT},
        panelPort:   ${panel_listen_port},
        fakeSiteDir: '${FAKE_SITE_DIR}',
        staticSite: {
          enabled: ${STATIC_SITE_ENABLED},
          root: process.env.STATIC_SITE_ROOT || ''
        },
        probeSecret: '${PROBE_SECRET}',
        probeMode:   '${PROBE_MODE:-bare}',
        logFile:     '/var/log/caddy-naive/access.log',
        authAuditLogPath: '/var/log/caddy-naive/auth-audit.log',
        trafficAuditLogPath: '/var/log/caddy-naive/traffic-audit.log'
      };
      process.stdout.write(t.render(cfg, users));
    " 2>>"$INSTALL_LOG") || true
    if [[ -z "${caddyfile_content:-}" ]]; then
      log_warn "caddyTemplate.js render returned empty output - using inline fallback"
    fi
  fi

#
  if [[ -z "${caddyfile_content:-}" ]]; then
#
    local placeholder_user="_placeholder_install"
    local placeholder_pass
    placeholder_pass=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 32)

    local auth_lines
    if [[ "$naive_users_json" != "[]" ]] && command -v node &>/dev/null; then
      auth_lines=$(node -e "
        const rows = $naive_users_json;
        rows.forEach(u => process.stdout.write('    basic_auth ' + u.username + ' ' + u.password + '\n'));
      " 2>/dev/null || true)
    fi
    if [[ -z "${auth_lines:-}" ]]; then
      auth_lines="    basic_auth ${placeholder_user} ${placeholder_pass}"
    fi

#
    local probe_line=""
    case "${PROBE_MODE:-bare}" in
      off)    probe_line="" ;;
      secret) [[ -n "${PROBE_SECRET:-}" ]] && probe_line="    probe_resistance ${PROBE_SECRET}" || probe_line="    probe_resistance" ;;
      *)      probe_line="    probe_resistance" ;;
    esac

#
#
#
#
#
    caddyfile_content="{
#
  order forward_proxy before file_server
#
  servers {
    protocols h1 h2
  }
  email ${ADMIN_EMAIL}
  admin off
  log {
    output file /var/log/caddy-naive/access.log {
      roll_size     50mb
      roll_keep_for 720h
    }
    format json
  }
}

# HTTP -> HTTPS redirect + ACME HTTP-01 fallback
:80 {
  redir https://{host}{uri} permanent
}

:${NAIVE_PORT}, ${DOMAIN} {
#
#
  tls ${ADMIN_EMAIL}

  handle /sub/* {
    reverse_proxy 127.0.0.1:${panel_listen_port}
  }

  forward_proxy {
${auth_lines}
    hide_ip
    hide_via"
    [[ -n "$probe_line" ]] && caddyfile_content+="
${probe_line}"
    caddyfile_content+="
    auth_audit_log /var/log/caddy-naive/auth-audit.log
    traffic_audit_log /var/log/caddy-naive/traffic-audit.log"
    caddyfile_content+="
  }

  file_server {
    root ${FAKE_SITE_DIR}
  }
}"
  fi

#
  local tmp_file="${CADDY_FILE}.new"
  printf '%s\n' "$caddyfile_content" > "$tmp_file"
  mv "$tmp_file" "$CADDY_FILE"
  chown root:caddy "$CADDY_CONFIG_DIR" 2>/dev/null || true
  chmod 750 "$CADDY_CONFIG_DIR" 2>/dev/null || true
  chown root:caddy "$CADDY_FILE" 2>/dev/null || true
  chmod 640 "$CADDY_FILE"

#
#
  "$CADDY_BIN" fmt --overwrite "$CADDY_FILE" 2>>"$INSTALL_LOG" || \
    log_warn "caddy fmt --overwrite returned an error (non-fatal)"

#
  local validate_out
  if validate_out=$("$CADDY_BIN" validate --config "$CADDY_FILE" --adapter caddyfile 2>&1); then
    log_info "Caddyfile validated and written -> $CADDY_FILE OK"
  else
    log_error "caddy validate returned error:"
    echo "$validate_out"
    die "Caddyfile is invalid - install aborted. Check $CADDY_FILE"
  fi

#
  echo "$PROBE_SECRET" > "${CADDY_CONFIG_DIR}/probe_secret"
  chown root:caddy "${CADDY_CONFIG_DIR}/probe_secret" 2>/dev/null || true
  chmod 640 "${CADDY_CONFIG_DIR}/probe_secret"
}

# Write caddy-naive.service
# Bug 22: called explicitly in main() after write_caddyfile() and before
# start_services() so the unit file always exists before daemon-reload.
write_caddy_service() {
  log_step "Writing caddy-naive.service"

#
  if [[ -f /etc/systemd/system/naive.service ]]; then
    systemctl stop    naive 2>/dev/null || true
    systemctl disable naive 2>/dev/null || true
    rm -f /etc/systemd/system/naive.service
    log_info "naive.service removed (replaced by caddy-naive.service) OK"
  fi

  cat > /etc/systemd/system/caddy-naive.service <<SVCCADDY
[Unit]
Description=Caddy forwardproxy-naive Server
Documentation=https://github.com/klzgrad/forwardproxy
After=network.target network-online.target
Requires=network-online.target
# Bug 62: cap restart storms - 5 failures in 5 min -> failed state (stops hammering ACME)
StartLimitBurst=5
StartLimitIntervalSec=300

[Service]
Type=notify
# Bug 37: run as unprivileged system user; cap_net_bind_service grants port 443
User=caddy
Group=caddy
ExecStart=${CADDY_BIN} run --config ${CADDY_FILE} --adapter caddyfile
ExecReload=/bin/kill -USR1 \$MAINPID
TimeoutStopSec=5
Restart=on-failure
# Bug 62: slow restarts to reduce ACME rate-limit pressure
RestartSec=10
LimitNOFILE=1048576
PrivateTmp=true
# Bug 65: ProtectSystem=strict (not full) is required when ReadWritePaths
# includes /etc paths; ProtectSystem=full makes all of /etc read-only
# system-wide regardless of ReadWritePaths on older kernels.
ProtectSystem=strict
# Bug 43: ACME certs stored under XDG_DATA_HOME; both dirs need write access
Environment=XDG_DATA_HOME=/var/lib/caddy
Environment=XDG_CONFIG_HOME=/var/lib/caddy
ReadWritePaths=/var/log/caddy-naive /etc/caddy-naive /var/lib/caddy
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
SVCCADDY

  log_info "caddy-naive.service written OK"
}

# Mieru initial state file
ensure_mita_state_permissions() {
  local dir
  dir="$(dirname "$MITA_STATE_FILE")"
  mkdir -p "$dir"

  if ! getent group mita >/dev/null 2>&1; then
    log_warn "mita group does not exist yet; cannot set mita-state.json group permissions"
    return 1
  fi

  local out
  if ! out=$(chgrp mita "$dir" 2>&1); then
    log_warn "Failed to set mita group on $dir: $out"
    return 1
  fi
  if ! out=$(chmod 750 "$dir" 2>&1); then
    log_warn "Failed to set mode 750 on $dir: $out"
    return 1
  fi

  if [[ -f "$MITA_STATE_FILE" ]]; then
    if ! out=$(chgrp mita "$MITA_STATE_FILE" 2>&1); then
      log_warn "Failed to set mita group on $MITA_STATE_FILE: $out"
      return 1
    fi
    if ! out=$(chmod 640 "$MITA_STATE_FILE" 2>&1); then
      log_warn "Failed to set mode 640 on $MITA_STATE_FILE: $out"
      return 1
    fi
    if command -v sudo >/dev/null 2>&1; then
      sudo -u mita test -x "$dir" && sudo -u mita test -r "$MITA_STATE_FILE" || {
        log_warn "mita cannot read $MITA_STATE_FILE. Check directory/file permissions."
        return 1
      }
    else
      runuser -u mita -- test -x "$dir" && runuser -u mita -- test -r "$MITA_STATE_FILE" || {
        log_warn "mita cannot read $MITA_STATE_FILE. Check directory/file permissions."
        return 1
      }
    fi
  fi

  return 0
}

write_mita_state() {
  log_step "Writing initial Mieru state"
  mkdir -p "$(dirname "$MITA_STATE_FILE")"

  python3 - <<PYEOF
import json
start = $MIERU_PORT_START
end   = $MIERU_PORT_END
cfg = {
    "portBindings": [
        {"port": p, "protocol": "TCP"}
        for p in range(start, end + 1)
    ],
    "users": [],
    "loggingLevel": "INFO",
    "mtu": 1400
}
with open("$MITA_STATE_FILE", "w") as f:
    json.dump(cfg, f, indent=2)
PYEOF
  ensure_mita_state_permissions || true
  log_info "Mita state file -> $MITA_STATE_FILE OK"
}

# Systemd: mita (ensure exists)
write_mita_service() {
  if [[ ! -f /lib/systemd/system/mita.service ]] && \
     [[ ! -f /etc/systemd/system/mita.service ]]; then
    cat > /etc/systemd/system/mita.service <<MITSVC
[Unit]
Description=Mieru Proxy Server (mita)
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/mita run
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
MITSVC
  fi
}

# Bug 7: UFW helper - handles single-port (start==end) correctly
# UFW rejects "N:N/proto" range syntax when start equals end.
_ufw_mieru_rule() {
  local s=$1 e=$2 proto=$3 comment=$4
  if [[ "$s" -eq "$e" ]]; then
    ufw allow "${s}/${proto}" comment "${comment}" 2>/dev/null || true
  else
    ufw allow "${s}:${e}/${proto}" comment "${comment}" 2>/dev/null || true
  fi
}

# UFW
# Bug 20: port 80 required for ACME HTTP-01 challenge.
# Bug 36: backup UFW rules before reset; interactive-mode prompts for confirmation.
setup_ufw() {
  log_step "Configuring UFW firewall"

#
  if command -v ufw &>/dev/null; then
    local ufw_bak="${BACKUP_DIR}/ufw-before-install-$(date +%Y%m%d-%H%M%S).rules"
    mkdir -p "$(dirname "$ufw_bak")"
    ufw status verbose 2>/dev/null > "$ufw_bak" || true
    log_info "UFW rules backup: $ufw_bak"
  fi

#
  if ! $NON_INTERACTIVE; then
    echo ""
    echo -e "${YELLOW}UFW --force reset will erase all existing rules!${NC}"
    read -rp "  Continue-> [Y/n]: " _ufw_confirm
    local _uc="${_ufw_confirm:-Y}"
    if false; then
      [[ "${_uc^^}" =~ ^(|N)$ ]] && { log_info "UFW skipped."; return; }
    else
      [[ "${_uc^^}" == "N" ]] && { log_info "UFW skipped."; return; }
    fi
  fi
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow ssh
  ufw allow 80/tcp comment "ACME HTTP-01 + redir HTTPS"
  if [[ "${PROTOCOL_TYPE}" == "naive" ]]; then
    ufw allow "${NAIVE_PORT}/tcp" comment "CaddyNaive HTTPS"
  fi
#
  _ufw_mieru_rule "$MIERU_PORT_START" "$MIERU_PORT_END" tcp "Mieru TCP"
  _ufw_mieru_rule "$MIERU_PORT_START" "$MIERU_PORT_END" udp "Mieru UDP"
  if [[ -n "${BACKEND_PANEL_IP}" ]]; then
    ufw allow from "${BACKEND_PANEL_IP}" to any port "${NODE_PORT}" proto tcp comment "Vetka Backend Panel -> Node Agent"
  else
    log_warn "BACKEND_PANEL_IP is not set; NODE_PORT ${NODE_PORT} was not opened publicly"
  fi
  ufw --force enable || true
  log_info "UFW rules applied OK"
}

# Panel installation
install_panel() {
  log_step "Installing web panel"
  mkdir -p "$PANEL_DIR"
  local src=""
  if [[ -d "$SOURCE_REPO_DIR/panel" ]]; then
    src="$SOURCE_REPO_DIR/panel"
  fi

  if [[ -n "$src" ]]; then
    find "$PANEL_DIR" -mindepth 1 -maxdepth 1 ! -name node_modules -exec rm -rf {} + 2>/dev/null || true
    cp -a "$src/." "$PANEL_DIR/"
    log_info "Panel files copied from $src OK"
  else
    log_warn "Local panel source not found - cloning from repo..."
    local tmp_panel_src; tmp_panel_src=$(mktemp -d /tmp/vetka-node-agent-panel-src.XXXXXX)
    git clone --depth 1 --branch "$PANEL_REPO_BRANCH" "$PANEL_REPO_URL" "$tmp_panel_src" 2>/dev/null || \
      die "Failed to clone panel source"
    find "$PANEL_DIR" -mindepth 1 -maxdepth 1 ! -name node_modules -exec rm -rf {} + 2>/dev/null || true
    log_info "Fetched latest panel from $PANEL_REPO_URL"
    [[ -d "$tmp_panel_src/panel" ]] || die "Cloned source panel directory not found: $tmp_panel_src/panel"
    cp -a "$tmp_panel_src/panel/." "$PANEL_DIR/"
    rm -rf "$tmp_panel_src"
  fi
  ( cd "$PANEL_DIR" && npm install --production --silent )
  grep -q "internalRouter" "$PANEL_DIR/server/index.js" || die "Installed stale panel/server/index.js: internalRouter not found"
  grep -q "ip-history" "$PANEL_DIR/server/index.js" || die "Installed stale panel: ip-history endpoint not found"
  grep -q "trafficAuditLogPath" "$PANEL_DIR/server/index.js" || die "Installed stale panel: trafficAuditLogPath not found"
  grep -q "uniqueIpCount24h" "$PANEL_DIR/server/index.js" || die "Installed stale panel: uniqueIpCount24h not found"
  log_info "npm dependencies installed OK"
}

# config.json
write_config_json() {
  log_step "Writing /etc/vetka-node-agent/config.json"
  mkdir -p /etc/vetka-node-agent "$(dirname "$DB_PATH")"
  local server_ip
  server_ip=$(curl -4 -fsSL https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')

#
#
#
#
#
#
  local bcrypt_hash
  bcrypt_hash=$(cd "$PANEL_DIR" && VETKA_ADMIN_PASS="$ADMIN_PASS" node -e "
    const bcrypt = require('bcryptjs');
    const pw = process.env.VETKA_ADMIN_PASS || '';
    if (!pw) { process.exit(2); }
    process.stdout.write(bcrypt.hashSync(pw, 12));
  " 2>/dev/null) || true
#
  if [[ -z "$bcrypt_hash" ]]; then
    if ! command -v htpasswd &>/dev/null; then
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq apache2-utils 2>/dev/null || true
    fi
    bcrypt_hash=$(htpasswd -bnBC 12 "" "$ADMIN_PASS" 2>/dev/null | tr -d ':\n' | sed 's/^[^$]*//')
  fi
  [[ -z "$bcrypt_hash" ]] && die "Failed to generate bcrypt password hash"
  local node_secret="${NODE_SECRET:-}"
  if [[ -z "$node_secret" ]]; then
    if $NON_INTERACTIVE; then
      die "NODE_SECRET is required for non-interactive install"
    fi
    read -rsp "NODE_SECRET: " node_secret
    echo ""
    [[ -z "$node_secret" ]] && die "NODE_SECRET is required"
  fi
  local node_id="${NODE_ID:-$(hostname -s 2>/dev/null || echo vetka-node)}"

  python3 - <<PYCFG
import json
data = {
    "domain":          "$DOMAIN",
    "serverIp":        "$server_ip",
    "adminEmail":      "$ADMIN_EMAIL",
    "adminUser":       "$ADMIN_USER",
    "adminPassHash":   "${bcrypt_hash}",
    "naivePort":       $NAIVE_PORT,
    "mieruPortStart":  $MIERU_PORT_START,
    "mieruPortEnd":    $MIERU_PORT_END,
    "panelPort":       int("$NODE_PORT"),
    "panelHost":       "$NODE_LISTEN_HOST",
    "exposePanel":     "$EXPOSE_PANEL".upper() in ("Y",""),
    "useUfw":          "$USE_UFW".upper() in ("Y",""),
    "dbPath":          "$DB_PATH",
    "caddyBin":        "$CADDY_BIN",
    "caddyFile":       "$CADDY_FILE",
    "caddyConfigDir":  "$CADDY_CONFIG_DIR",
    "fakeSiteDir":     "$FAKE_SITE_DIR",
    "fakeSiteUrl":     "$FAKE_SITE_URL",
    "staticSite": {
        "enabled": "$STATIC_SITE_ENABLED".lower() == "true",
        "root": "$STATIC_SITE_ROOT",
        "sourceType": "$STATIC_SITE_SOURCE_TYPE",
        "sourceUrl": "$STATIC_SITE_SOURCE_URL",
        "deployOnInstall": "$STATIC_SITE_DEPLOY_ON_INSTALL".lower() == "true",
        "deployOnUpdate": "$STATIC_SITE_DEPLOY_ON_UPDATE",
        "createIfMissing": "$STATIC_SITE_CREATE_IF_MISSING".lower() == "true"
    },
    "probeSecret":     "$PROBE_SECRET",
    "probeMode":       "${PROBE_MODE:-bare}",
    "nodeApiKey":      "",
    "nodeId":          "$node_id",
    "nodeSecret":      "$node_secret",
    "nodePort":        int("$NODE_PORT"),
    "nodeListenHost":  "$NODE_LISTEN_HOST",
    "protocolType":    "$PROTOCOL_TYPE",
    "appliedStateFile": "$APPLIED_STATE_FILE",
    "backendAllowedIps": [ip for ip in ["127.0.0.1", "$BACKEND_PANEL_IP"] if ip],
    "allowAnyBackendIp": False,
    "allowLocalUserMutations": "$ALLOW_LOCAL_USER_MUTATIONS".lower() in ("1", "true", "yes", "y"),
    "sessionTtlMinutes": 10,
    "authAuditLogPath": "/var/log/caddy-naive/auth-audit.log",
    "trafficAuditLogPath": "/var/log/caddy-naive/traffic-audit.log",
    "ipHistoryTtlHours": 24,
    "maxUniqueIpsPerUser": 5,
    "enforceIpLimit":  False,
    "subscriptionBaseUrl": "",
    "mitaStateFile":   "$MITA_STATE_FILE",
    "trafficPattern":  "NOOP",
    "mtu":             1400,
    "udpEnabled":      False,
    "language":        "en",
    "version":         "$CURRENT_VERSION",
    "installedAt":     "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
with open("$PANEL_CONFIG", "w") as f:
    json.dump(data, f, indent=2)
import os; os.chmod("$PANEL_CONFIG", 0o600)
PYCFG

  log_info "config.json written OK"
}

# Version file
write_version() {
  mkdir -p "$(dirname "$VERSION_FILE")"
  cat > "$VERSION_FILE" <<VEREOF
panel_version=${CURRENT_VERSION}
caddy_version=${CADDY_VERSION:-unknown}
mieru_version=${MIERU_VERSION:-unknown}
installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
VEREOF
  log_info "Version file written -> $VERSION_FILE OK"
}

# Start services
# Bug 22: write_caddy_service() called from main() before start_services().
# Bug 37: caddy-naive runs as dedicated 'caddy' system user.
# Bug 42: caddy user + all dirs created BEFORE systemctl restart so the service
# can write logs and ACME certs without permission-denied errors.
# Bug 43: /var/lib/caddy created + owned by caddy for ACME cert storage.
# Bug 61: Caddy failure is non-fatal - install continues so the user can reach
# the panel UI and diagnose/fix from there.
# Bug 62: ACME port-wait loop warns if :443 is not listening after 60 s.
deploy_static_site() {
  if [[ "${STATIC_SITE_ENABLED:-false}" != "true" ]]; then
    return 0
  fi
  if [[ "${STATIC_SITE_DEPLOY_ON_INSTALL:-true}" != "true" ]]; then
    log_info "Static site deployOnInstall=false; skipping deploy"
    return 0
  fi
  if [[ "${STATIC_SITE_SOURCE_TYPE:-skip}" == "skip" || -z "${STATIC_SITE_SOURCE_URL:-}" ]]; then
    log_warn "Static site enabled but no archive URL provided; expected root: ${FAKE_SITE_DIR}"
    return 0
  fi
  local helper="${PANEL_DIR}/scripts/static-site.sh"
  if [[ ! -f "$helper" ]]; then
    log_warn "static-site helper not found at $helper; skipping deploy"
    return 0
  fi
  bash "$helper" deploy || die "Static site deploy failed"
}

ensure_mita_json_bootstrap() {
  mkdir -p /etc/systemd/system/mita.service.d
  cat > /etc/systemd/system/mita.service.d/10-vetka-node-agent.conf <<MITADROPIN
[Service]
Environment=MITA_CONFIG_JSON_FILE=${MITA_STATE_FILE}
MITADROPIN
  systemctl daemon-reload
}

apply_mita_config_bootstrap() {
  if ! has_mieru_users; then
    log_warn "Mieru cannot be started: no active Mieru users configured"
    systemctl stop mita 2>/dev/null || true
    systemctl reset-failed mita 2>/dev/null || true
    return 2
  fi

  ensure_mita_state_permissions || return 1

  local out
  if out=$(mita apply config "$MITA_STATE_FILE" 2>&1); then
    [[ -n "$out" ]] && log_info "mita apply config output: $out"
    return 0
  fi
  log_warn "mita apply config failed: $out"
  if echo "$out" | grep -qiE 'daemon is not running|connection refused|unavailable'; then
    ensure_mita_json_bootstrap
    systemctl reset-failed mita 2>/dev/null || true
    systemctl restart mita 2>&1 || true
    sleep 1
    if out=$(mita apply config "$MITA_STATE_FILE" 2>&1); then
      [[ -n "$out" ]] && log_info "mita apply config output: $out"
      return 0
    fi
  fi
  log_warn "mita apply config failed after bootstrap: $out"
  return 1
}

start_services() {
  log_step "Starting services"

#
  if ! id caddy &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin caddy
    log_info "System user caddy created OK"
  fi

#
  if [[ -f /var/log/caddy-naive/access.log ]]; then
    local _log_owner
    _log_owner=$(stat -c '%U' /var/log/caddy-naive/access.log 2>/dev/null || echo root)
    if [[ "$_log_owner" != "caddy" ]]; then
      log_warn "Removing stale access.log owned by $_log_owner (need caddy)"
      rm -f /var/log/caddy-naive/access.log
    fi
  fi

#
  mkdir -p /var/log/caddy-naive /var/lib/caddy
  chown -R caddy:caddy /var/log/caddy-naive /var/lib/caddy
  chmod 755 /var/log/caddy-naive
  chmod 700 /var/lib/caddy
  touch /var/log/caddy-naive/auth-audit.log
  touch /var/log/caddy-naive/traffic-audit.log
  chown caddy:caddy /var/log/caddy-naive/auth-audit.log
  chown caddy:caddy /var/log/caddy-naive/traffic-audit.log
  chmod 600 /var/log/caddy-naive/auth-audit.log
  chmod 600 /var/log/caddy-naive/traffic-audit.log

#
#
  chown root:caddy "$CADDY_BIN" 2>/dev/null || true
  chmod 755 "$CADDY_BIN" 2>/dev/null || true
  setcap 'cap_net_bind_service=+ep' "$CADDY_BIN" 2>/dev/null || true

#
#
#
#
#
#
#
  chown -R root:caddy "$CADDY_CONFIG_DIR" 2>/dev/null || true
#
#
  chmod 750 "$CADDY_CONFIG_DIR" 2>/dev/null || true
#
  find "$CADDY_CONFIG_DIR" -type d -exec chmod 750 {} + 2>/dev/null || true
#
  find "$CADDY_CONFIG_DIR" -type f -exec chmod 640 {} + 2>/dev/null || true
#
  chmod 640 "$CADDY_FILE" 2>/dev/null || true

  systemctl daemon-reload

#
  systemctl enable caddy-naive
#
#
  systemctl reset-failed caddy-naive 2>/dev/null || true
  systemctl restart caddy-naive || true
  sleep 2
  if systemctl is-active --quiet caddy-naive; then
    log_info "caddy-naive started OK"
#
    local _port_wait=0
    while [[ $_port_wait -lt 30 ]]; do
      ss -tlnp 2>/dev/null | grep -q ":${NAIVE_PORT} " && break
      sleep 2; (( _port_wait++ ))
    done
    if ! ss -tlnp 2>/dev/null | grep -q ":${NAIVE_PORT} "; then
      log_warn "caddy-naive not yet listening on :${NAIVE_PORT} after 60 s - ACME challenge may still be running"
      log_warn "Check: dig +short $DOMAIN, journalctl -u caddy-naive -n 50"
    fi
  else
#
    log_error "caddy-naive failed to start! journalctl output:"
    journalctl -u caddy-naive -n 40 --no-pager 2>/dev/null || true
    log_warn "caddy-naive is not active - install continues. After opening the panel run: bash update.sh --repair"
  fi

#
#
  write_mita_service
  systemctl enable mita 2>/dev/null || true
  local _mita_apply_rc=0
  apply_mita_config_bootstrap || _mita_apply_rc=$?
  if [[ "$_mita_apply_rc" -eq 0 ]]; then
    log_info "mita config applied OK"
  elif [[ "$_mita_apply_rc" -ne 2 ]]; then
    log_warn "mita apply config returned non-zero - check: mita status"
  fi
  local _mita_users
  _mita_users=$(python3 -c "
import json, sys
try:
    d = json.load(open('$MITA_STATE_FILE'))
    print(len(d.get('users', [])))
except Exception:
    print(0)
" 2>/dev/null || echo 0)
  if [[ "$_mita_users" -gt 0 ]]; then
#
#
#
    local _mita_restart_out
    if ! _mita_restart_out=$(systemctl restart mita 2>&1); then
      log_warn "systemctl restart mita failed: $_mita_restart_out"
    elif [[ -n "$_mita_restart_out" ]]; then
      log_info "systemctl restart mita output: $_mita_restart_out"
    fi
    sleep 1
    local _mita_start_out
    if _mita_start_out=$(mita start 2>&1); then
      [[ -n "$_mita_start_out" ]] && log_info "mita start output: $_mita_start_out"
      log_info "mita started OK"
    else
      [[ -n "$_mita_start_out" ]] && log_warn "mita start failed: $_mita_start_out"
      log_warn "mita failed to start - journalctl -u mita -n 30 / mita status"
    fi
  else
    systemctl stop mita 2>/dev/null || true
    systemctl reset-failed mita 2>/dev/null || true
    log_info "mita: no users yet - service will start automatically after first user is added via panel"
  fi

#
  cd "$PANEL_DIR"
  pm2 delete vetka-node-agent 2>/dev/null || true
  NODE_ID="${NODE_ID:-$(hostname -s 2>/dev/null || echo vetka-node)}" NODE_SECRET="${NODE_SECRET:-}" NODE_LISTEN_HOST="$NODE_LISTEN_HOST" NODE_PORT="$NODE_PORT" PROTOCOL_TYPE="$PROTOCOL_TYPE" BACKEND_ALLOWED_IPS="$BACKEND_PANEL_IP" \
    pm2 start server/index.js \
      --name vetka-node-agent \
      --log /var/log/vetka-node-agent.log \
      --time 2>/dev/null || \
  NODE_ENV=production NODE_ID="${NODE_ID:-$(hostname -s 2>/dev/null || echo vetka-node)}" NODE_SECRET="${NODE_SECRET:-}" NODE_LISTEN_HOST="$NODE_LISTEN_HOST" NODE_PORT="$NODE_PORT" PROTOCOL_TYPE="$PROTOCOL_TYPE" BACKEND_ALLOWED_IPS="$BACKEND_PANEL_IP" \
    pm2 start server/index.js --name vetka-node-agent --time
  pm2 save
  pm2 startup systemd -u root --hp /root 2>/dev/null | tail -1 | bash 2>/dev/null || true
  log_info "Panel started via PM2 OK"
  cd /
}

# Bug 14: smoke_test_configs() - create test user, validate config downloads
smoke_test_configs() {
  log_step "Smoke test: client config validation"
  local test_user="smoke_test_user"
  local test_pass="smoke_pass_123"
  local test_email="smoke@test.local"
  local panel_url="http://127.0.0.1:${NODE_PORT}"
  local pass=0 fail=0
  local cookie_file; cookie_file=$(mktemp)

#
  local login_res
  login_res=$(curl -sf -c "$cookie_file" -X POST "$panel_url/api/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PASS\"}" 2>/dev/null) || true

  if echo "$login_res" | grep -q '"ok":true'; then
    echo -e "  ${GREEN}OK${NC} smoke login OK"; (( pass++ ))
  else
    echo -e "  ${YELLOW}WARN${NC}  smoke login skipped (panel may still be starting)"
    rm -f "$cookie_file"
    return 0
  fi

#
  local create_res
  create_res=$(curl -sf -b "$cookie_file" -X POST "$panel_url/api/users" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$test_user\",\"email\":\"$test_email\",\"password\":\"$test_pass\",\"protocols\":[\"naive\",\"mieru\"],\"quotaMB\":0}" \
    2>/dev/null) || true
  local user_id=""
  user_id=$(echo "$create_res" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || true)

  if [[ -n "$user_id" ]]; then
    echo -e "  ${GREEN}OK${NC} smoke test user created (id: ${user_id:0:8}...)"; (( pass++ ))
  else
    echo -e "  ${RED}FAIL${NC} smoke test user creation failed"; (( fail++ ))
    rm -f "$cookie_file"; return 0
  fi

#
  local naive_cfg
  naive_cfg=$(curl -sf -b "$cookie_file" \
    "$panel_url/api/users/$user_id/config/naive->password=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$test_pass'))")" \
    2>/dev/null) || true

  if echo "$naive_cfg" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'link' in d" 2>/dev/null; then
    echo -e "  ${GREEN}OK${NC} naive config link valid"; (( pass++ ))
#
    local naive_link; naive_link=$(echo "$naive_cfg" | python3 -c "import json,sys; print(json.load(sys.stdin)['link'])" 2>/dev/null || true)
    if echo "$naive_link" | grep -q "naive+https://"; then
      echo -e "  ${GREEN}OK${NC} naive link uses HTTPS transport"; (( pass++ ))
    else
      echo -e "  ${RED}FAIL${NC} naive link missing HTTPS transport"; (( fail++ ))
    fi
  else
    echo -e "  ${RED}FAIL${NC} naive config invalid"; (( fail++ ))
  fi

#
  local mieru_cfg
  mieru_cfg=$(curl -sf -b "$cookie_file" \
    "$panel_url/api/users/$user_id/config/mieru->password=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$test_pass'))")" \
    2>/dev/null) || true

  if echo "$mieru_cfg" | python3 -c "
import json,sys
d=json.load(sys.stdin)
ob=d.get('outbounds',[])
m=[o for o in ob if o.get('type')=='mieru']
assert m, 'no mieru outbound'
# Bug 12: server_ports array
assert 'server_ports' in m[0] or 'server_port' in m[0], 'missing port field'
# Bug 5: transport field
assert m[0].get('transport','TCP') in ('TCP','UDP'), 'invalid transport'
" 2>/dev/null; then
    echo -e "  ${GREEN}OK${NC} mieru config valid (transport + port fields)"; (( pass++ ))
  else
    echo -e "  ${RED}FAIL${NC} mieru config validation failed"; (( fail++ ))
  fi

#
  curl -sf -b "$cookie_file" -X DELETE "$panel_url/api/users/$user_id" > /dev/null 2>&1 || true
  echo -e "  ${GREEN}OK${NC} smoke test user cleaned up"
  rm -f "$cookie_file"

  echo ""
  echo -e "  Config smoke: ${GREEN}$pass passed${NC}  ${RED}$fail failed${NC}"
  return 0
}

# Smoke tests
has_mieru_users() {
  python3 - "$MITA_STATE_FILE" <<'PY' 2>/dev/null
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    data = {}
raise SystemExit(0 if len(data.get("users", [])) > 0 else 1)
PY
}

smoke_test() {
  log_step "Running smoke tests"
  sleep 5
  local pass=0 fail=0

  chk() {
    if eval "$2" &>/dev/null; then
      echo -e "  ${GREEN}OK${NC} $1"; (( pass++ ))
    else
      echo -e "  ${RED}FAIL${NC} $1"; (( fail++ ))
    fi
  }

#
  chk "caddy-naive version"          "timeout 5 $CADDY_BIN version || $CADDY_BIN --version"
  chk "caddy-naive.service active"   "systemctl is-active caddy-naive"
  chk "caddy-naive port :${NAIVE_PORT} listening" \
      "ss -tlnup sport = :${NAIVE_PORT} 2>/dev/null | grep -q :${NAIVE_PORT}"
  chk "Caddyfile present"            "[[ -f $CADDY_FILE ]]"
  if [[ "${STATIC_SITE_ENABLED:-false}" == "true" ]]; then
    chk "static-site index.html present" "[[ -f ${FAKE_SITE_DIR}/index.html ]]"
  else
    chk "legacy fake-site index.html present" "[[ -f ${FAKE_SITE_DIR}/index.html ]]"
  fi

#
  chk "mita.service enabled"         "systemctl is-enabled mita"
  chk "mita-state.json present"      "[[ -f $MITA_STATE_FILE ]]"
  if has_mieru_users; then
    chk "mita active with configured users" "systemctl is-active --quiet mita"
  else
    echo -e "  ${GREEN}OK${NC} mita idle OK, no Mieru users configured"
    (( pass++ ))
  fi

#
  chk "Node Agent health :${NODE_PORT}" "curl -sf -H \"Authorization: Bearer \$(jq -r '.nodeSecret // empty' '$PANEL_CONFIG')\" http://127.0.0.1:${NODE_PORT}/health -o /dev/null"
  chk "config.json present"          "[[ -f $PANEL_CONFIG ]]"
  chk "version file present"         "[[ -f $VERSION_FILE ]]"

#
  chk "probe_secret file present"    "[[ -f ${CADDY_CONFIG_DIR}/probe_secret ]]"

  if timedatectl status 2>/dev/null | grep -q "synchronized: yes"; then
    echo -e "  ${GREEN}OK${NC} Time synchronised"
    (( pass++ ))
  else
    echo -e "  ${YELLOW}WARN${NC}  Time NOT synchronised - critical for Mieru!"
  fi

  echo ""
  echo -e "  Results: ${GREEN}$pass passed${NC}  ${RED}$fail failed${NC}"
  (( fail > 0 )) && log_warn "Check logs: journalctl -u caddy-naive mita -n 30"

#
  if [[ -n "${ADMIN_PASS:-}" ]]; then
    smoke_test_configs
  fi
}

# UFW call
maybe_ufw() {
  local ans="${USE_UFW:-Y}"
  [[ "${ans^^}" =~ ^(Y|)$ ]] && setup_ufw || true
}

# Final banner
print_banner() {
  local server_ip
  server_ip=$(python3 -c "import json; print(json.load(open('$PANEL_CONFIG'))['serverIp'])" 2>/dev/null               || hostname -I | awk '{print $1}')
  echo ""
  echo -e "${GREEN}${BOLD}========================================${NC}"
  echo -e "${GREEN}${BOLD}  Vetka Node Agent v${CURRENT_VERSION} - Install Complete${NC}"
  echo -e "${GREEN}${BOLD}========================================${NC}"
  echo ""
  echo -e "  ${BOLD}Domain:${NC}              $DOMAIN"
  echo -e "  ${BOLD}Server IP:${NC}          $server_ip"
  echo -e "  ${BOLD}NaiveProxy port (Caddy):${NC}  $NAIVE_PORT"
  echo -e "  ${BOLD}Mieru ports:${NC}        $MIERU_PORT_START-$MIERU_PORT_END (TCP)"
  echo -e "  ${BOLD}Probe secret:${NC}       ${PROBE_SECRET}"
  echo -e "  ${BOLD}Managed static site:${NC} $FAKE_SITE_DIR"
  echo ""
  echo -e "  ${BOLD}Node Agent API:${NC}"
  if [[ "${EXPOSE_PANEL^^}" =~ ^Y$ ]]; then
    echo -e "    Public URL:  ${CYAN}http://$server_ip:8080/${NC}"
  else
    echo -e "    Health: ${CYAN}curl -H 'Authorization: Bearer <NODE_SECRET>' http://127.0.0.1:${NODE_PORT}/health${NC}"
    echo -e "    Status: ${CYAN}curl -H 'Authorization: Bearer <NODE_SECRET>' http://127.0.0.1:${NODE_PORT}/status${NC}"
  fi
  echo ""
  echo -e "  ${BOLD}Admin credentials:${NC}"
  echo -e "    Username: ${CYAN}$ADMIN_USER${NC}"
  echo -e "    Password: ${CYAN}$ADMIN_PASS${NC}"
  echo ""
  echo -e "  ${BOLD}Useful commands:${NC}"
  echo "    pm2 logs vetka-node-agent"
  echo "    systemctl status caddy-naive mita"
  echo "    $CADDY_BIN version"
  echo "    mita status"
  echo "    bash update.sh --status"
  echo "    bash update.sh --repair"
  echo ""
  echo -e "  ${BOLD}Install log:${NC}      $INSTALL_LOG"
  echo ""
  echo -e "  ${YELLOW}${BOLD}IMPORTANT: Save the password and probe_secret. They will not be shown again.${NC}"
  echo ""
  echo -e "  Donate:    ${CYAN}https://app.lava.top/2107724612->tabId=donate${NC}"
  echo ""
}

main() {
  parse_install_args "$@"

  validate_install_source
  select_language
  check_os
  detect_arch
  check_existing
  sync_time
  install_deps
  install_nodejs
  install_caddy_naive
  install_mieru
  ensure_mita_state_permissions || true
  gather_config
  setup_fake_site
  write_mita_state
#
#
  install_panel
  write_config_json
  deploy_static_site
  write_caddyfile
  write_caddy_service
  write_version
  tune_network      # BBR + UDP buffers (uses panel/scripts/sysctl_tune.sh)
  maybe_ufw
  start_services
  smoke_test
  print_banner
}

main "$@"
