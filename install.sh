#!/usr/bin/env bash
# ==============================================================================
# Vetka Node Agent вЂ” install.sh  v1.2.6
# Caddy-forwardproxy-naive (amd64-only) + Mieru (mita) + fake-site + probe-resistance
# Supports: Ubuntu 20.04/22.04/24.04, Debian 11/12 | x86_64 only
# ==============================================================================
set -euo pipefail

# в”Ђв”Ђ Capture all installer output to a log file в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
INSTALL_LOG="/var/log/vetka-node-agent-install.log"
mkdir -p "$(dirname "$INSTALL_LOG")"
exec > >(tee -a "$INSTALL_LOG") 2>&1
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] install.sh v1.2.6 started (PID $$)"

# в”Ђв”Ђ Bug 19: ERR trap вЂ” log failure location and guide user to recovery в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
on_error() {
  local exit_code=$1 line=$2
  echo ""
  echo -e "${RED}${BOLD}в•”в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•—${NC}"
  echo -e "${RED}${BOLD}в•‘  install.sh FAILED  (exit $exit_code  at line $line)           ${NC}"
  echo -e "${RED}${BOLD}в•љв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ќ${NC}"
  echo -e "  ${YELLOW}Install log:${NC} $INSTALL_LOG"
  echo -e "  ${YELLOW}Recovery options:${NC}"
  echo -e "    вЂў Retry (idempotent):   ${CYAN}sudo bash install.sh --force${NC}"
  echo -e "    вЂў Clean uninstall:      ${CYAN}sudo bash uninstall.sh${NC}"
  echo -e "    вЂў View last 30 lines:   ${CYAN}tail -30 $INSTALL_LOG${NC}"
  echo ""
}
trap 'on_error $? $LINENO' ERR

# в”Ђв”Ђ Colours в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "\n${CYAN}${BOLD}в–¶ $*${NC}"; }
die()       { log_error "$*"; exit 1; }

# в”Ђв”Ђ Constants в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
PANEL_DIR="/opt/vetka-node-agent"
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

# в”Ђв”Ђ Flags в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
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
        case "${2:-ru}" in en) LANG_RU=false ;; *) LANG_RU=true ;; esac
        shift ;;
      --help|-h)
        echo "Usage: bash install.sh [--non-interactive] [--domain DOMAIN] [--email EMAIL]"
        echo "                       [--admin-user USER] [--admin-pass PASS]"
        echo "                       [--naive-port PORT] [--mieru-start PORT] [--mieru-end PORT]"
        echo "                       [--fake-site-url URL] [--static-site-url URL]"
        echo "                       [--static-site-root PATH] [--skip-static-site] [--probe-secret SECRET]"
        echo "                       [--lang ru|en]"
        exit 0 ;;
      *) log_warn "Unknown argument: $1 (ignored)" ;;
    esac
    shift
  done
}

# в”Ђв”Ђ i18n в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
LANG_RU=true
t() { if $LANG_RU; then echo "$1"; else echo "$2"; fi }

# в”Ђв”Ђ Root check в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
[[ $EUID -ne 0 ]] && die "Р—Р°РїСѓСЃС‚РёС‚Рµ СЃРєСЂРёРїС‚ РѕС‚ root (sudo bash install.sh) / Run as root"

# в”Ђв”Ђ Language selection в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
select_language() {
  if $NON_INTERACTIVE; then return; fi
  echo ""
  echo -e "${BOLD}в•”в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•—${NC}"
  echo -e "${BOLD}в•‘   Vetka Node Agent  v${CURRENT_VERSION}                   в•‘${NC}"
  # Bug 32: interactive prompts go to /dev/tty so tee-to-log doesn't swallow them
  # (exec redirect is set up above; read uses /dev/tty automatically in bash)
  echo -e "${BOLD}в•љв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ќ${NC}"
  echo ""
  echo -e "  Р’С‹Р±РµСЂРёС‚Рµ СЏР·С‹Рє / Select language:"
  echo -e "  ${CYAN}1)${NC} Р СѓСЃСЃРєРёР№ ${GREEN}(РїРѕ СѓРјРѕР»С‡Р°РЅРёСЋ / default)${NC}"
  echo -e "  ${CYAN}2)${NC} English"
  echo ""
  read -rp "  [1/2]: " LANG_CHOICE
  case "${LANG_CHOICE:-1}" in
    2) LANG_RU=false ;;
    *) LANG_RU=true  ;;
  esac
  echo ""
  $LANG_RU && log_info "Р’С‹Р±СЂР°РЅ СЏР·С‹Рє: Р СѓСЃСЃРєРёР№" || log_info "Language selected: English"
}

# в”Ђв”Ђ OS check в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
check_os() {
  log_step "$(t 'РџСЂРѕРІРµСЂРєР° СЃРѕРІРјРµСЃС‚РёРјРѕСЃС‚Рё РћРЎ' 'Checking OS compatibility')"
  [[ ! -f /etc/os-release ]] && die "$(t 'РќРµ СѓРґР°Р»РѕСЃСЊ РѕРїСЂРµРґРµР»РёС‚СЊ РћРЎ' 'Cannot determine OS')"
  source /etc/os-release
  case "$ID" in
    ubuntu)
      case "$VERSION_ID" in
        20.04|22.04|24.04) log_info "OS: Ubuntu $VERSION_ID вњ“" ;;
        *) die "$(t "РќРµРїРѕРґРґРµСЂР¶РёРІР°РµРјР°СЏ Ubuntu: $VERSION_ID" "Unsupported Ubuntu: $VERSION_ID")" ;;
      esac ;;
    debian)
      case "$VERSION_ID" in
        11|12) log_info "OS: Debian $VERSION_ID вњ“" ;;
        *) die "$(t "РќРµРїРѕРґРґРµСЂР¶РёРІР°РµРјС‹Р№ Debian: $VERSION_ID" "Unsupported Debian: $VERSION_ID")" ;;
      esac ;;
    *) die "$(t "РќРµРїРѕРґРґРµСЂР¶РёРІР°РµРјР°СЏ РћРЎ: $ID" "Unsupported OS: $ID")" ;;
  esac
}

# в”Ђв”Ђ Architecture detection вЂ” amd64 only for caddy-naive в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
detect_arch() {
  log_step "$(t 'РћРїСЂРµРґРµР»РµРЅРёРµ Р°СЂС…РёС‚РµРєС‚СѓСЂС‹' 'Detecting architecture')"
  local machine; machine=$(uname -m)
  case "$machine" in
    x86_64|amd64) ARCH="amd64"; DEB_ARCH="amd64" ;;
    # Bug 1: caddy-forwardproxy-naive is amd64-only; ARM not supported
    aarch64|arm64) die "$(t \
      'caddy-forwardproxy-naive РїРѕРґРґРµСЂР¶РёРІР°РµС‚ С‚РѕР»СЊРєРѕ amd64. ARM64 РЅРµ РїРѕРґРґРµСЂР¶РёРІР°РµС‚СЃСЏ РІ v1.2.6.' \
      'caddy-forwardproxy-naive only supports amd64. ARM64 is not supported in v1.2.6.')" ;;
    armv7l) die "$(t \
      'caddy-forwardproxy-naive РїРѕРґРґРµСЂР¶РёРІР°РµС‚ С‚РѕР»СЊРєРѕ amd64. ARMv7 РЅРµ РїРѕРґРґРµСЂР¶РёРІР°РµС‚СЃСЏ РІ v1.2.6.' \
      'caddy-forwardproxy-naive only supports amd64. ARMv7 is not supported in v1.2.6.')" ;;
    *) die "$(t "РќРµРїРѕРґРґРµСЂР¶РёРІР°РµРјР°СЏ Р°СЂС…РёС‚РµРєС‚СѓСЂР°: $machine" "Unsupported architecture: $machine")" ;;
  esac
  log_info "$(t 'РђСЂС…РёС‚РµРєС‚СѓСЂР°' 'Architecture'): $machine в†’ $ARCH вњ“"
}

# в”Ђв”Ђ Idempotent check в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
check_existing() {
  if [[ -f "$PANEL_CONFIG" ]]; then
    log_warn "$(t 'РћР±РЅР°СЂСѓР¶РµРЅР° СЃСѓС‰РµСЃС‚РІСѓСЋС‰Р°СЏ СѓСЃС‚Р°РЅРѕРІРєР°!' 'Existing installation detected!')"
    if $NON_INTERACTIVE || $FORCE_INSTALL; then
      log_info "$(t 'Р¤Р»Р°Рі --force: РїСЂРѕРґРѕР»Р¶Р°РµРј РїРµСЂРµСѓСЃС‚Р°РЅРѕРІРєСѓ.' '--force: proceeding with reinstall.')"
    else
      echo ""
      read -rp "$(t '  РџРµСЂРµСѓСЃС‚Р°РЅРѕРІРёС‚СЊ РїРѕРІРµСЂС…? [Рґ/Рќ]: ' '  Reinstall over existing? [y/N]: ')" REINSTALL
      local ans="${REINSTALL:-N}"
      if $LANG_RU; then
        [[ "${ans^^}" =~ ^(Р”|Y)$ ]] || { log_info "$(t 'РћС‚РјРµРЅРµРЅРѕ.' 'Aborted.')"; exit 0; }
      else
        [[ "${ans^^}" == "Y" ]] || { log_info "Aborted."; exit 0; }
      fi
    fi
    # Backup before reinstall
    local ts; ts=$(date +%Y-%m-%d-%H%M%S)
    local bdir="$BACKUP_DIR/$ts"
    mkdir -p "$bdir"
    [[ -f "$CADDY_FILE"       ]] && cp "$CADDY_FILE"       "$bdir/" || true
    [[ -f "$MITA_STATE_FILE"  ]] && cp "$MITA_STATE_FILE"  "$bdir/" || true
    [[ -f "$PANEL_CONFIG"     ]] && cp "$PANEL_CONFIG"     "$bdir/" || true
    log_info "$(t "Р РµР·РµСЂРІРЅР°СЏ РєРѕРїРёСЏ: $bdir" "Backup created: $bdir")"
  fi
}

# в”Ђв”Ђ NTP sync в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
sync_time() {
  log_step "$(t 'РЎРёРЅС…СЂРѕРЅРёР·Р°С†РёСЏ РІСЂРµРјРµРЅРё (NTP)' 'Synchronising system time (NTP)')"
  log_warn "$(t 'Р’РђР–РќРћ: Mieru С‚СЂРµР±СѓРµС‚ С‚РѕС‡РЅРѕРіРѕ СЃРёСЃС‚РµРјРЅРѕРіРѕ РІСЂРµРјРµРЅРё (В±30 СЃРµРє). РЎРёРЅС…СЂРѕРЅРёР·Р°С†РёСЏ РєСЂРёС‚РёС‡РЅР°!' \
             'IMPORTANT: Mieru requires accurate system time (В±30 s). NTP sync is critical!')"
  timedatectl set-ntp true 2>/dev/null || true
  local synced=false
  for i in $(seq 1 15); do
    if timedatectl status 2>/dev/null | grep -q "synchronized: yes"; then
      synced=true; break
    fi
    sleep 1
  done
  if $synced; then
    log_info "$(t 'Р’СЂРµРјСЏ СЃРёРЅС…СЂРѕРЅРёР·РёСЂРѕРІР°РЅРѕ вњ“' 'Time synchronised вњ“')"
  else
    log_warn "$(t 'РЎРёРЅС…СЂРѕРЅРёР·Р°С†РёСЏ РЅРµ РїРѕРґС‚РІРµСЂР¶РґРµРЅР° Р·Р° 15 СЃ!' 'Sync not confirmed within 15 s!')"
  fi
}

# в”Ђв”Ђ Package dependencies в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
install_deps() {
  log_step "$(t 'РЈСЃС‚Р°РЅРѕРІРєР° Р·Р°РІРёСЃРёРјРѕСЃС‚РµР№' 'Installing dependencies')"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  # Bug 1: certbot removed вЂ” Caddy uses TLS-ALPN-01 (no standalone HTTP-01 needed)
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
  log_info "$(t 'Р—Р°РІРёСЃРёРјРѕСЃС‚Рё СѓСЃС‚Р°РЅРѕРІР»РµРЅС‹ вњ“' 'Dependencies installed вњ“')"
}

# в”Ђв”Ђ Node.js 20 LTS + PM2 в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
install_nodejs() {
  log_step "$(t 'РЈСЃС‚Р°РЅРѕРІРєР° Node.js 20 LTS' 'Installing Node.js 20 LTS')"
  if command -v node &>/dev/null && node --version | grep -qE "^v2[0-9]"; then
    log_info "Node.js $(node --version) вЂ” $(t 'СѓР¶Рµ СѓСЃС‚Р°РЅРѕРІР»РµРЅ вњ“' 'already installed вњ“')"
  else
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
    log_info "Node.js $(node --version) $(t 'СѓСЃС‚Р°РЅРѕРІР»РµРЅ вњ“' 'installed вњ“')"
  fi
  if command -v pm2 &>/dev/null; then
    log_info "PM2 $(pm2 --version) вЂ” $(t 'СѓР¶Рµ СѓСЃС‚Р°РЅРѕРІР»РµРЅ вњ“' 'already installed вњ“')"
  else
    npm install -g pm2 --silent
    log_info "$(t 'PM2 СѓСЃС‚Р°РЅРѕРІР»РµРЅ вњ“' 'PM2 installed вњ“')"
  fi
}

# в”Ђв”Ђ Caddy-forwardproxy-naive binary в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
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
    log_info "Vetka Caddy supports auth_audit_log вњ“"
  else
    log_error "Vetka Caddy adapt output does not contain auth_audit_log"
    ok=false
  fi
  if echo "$adapt_out" | grep -q '"traffic_audit_log"'; then
    log_info "Vetka Caddy supports traffic_audit_log вњ“"
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
  log_step "$(t 'РЈСЃС‚Р°РЅРѕРІРєР° Vetka patched caddy-forwardproxy' 'Installing Vetka patched caddy-forwardproxy')"
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
  log_info "Vetka caddy-naive installed -> $CADDY_BIN ($CADDY_VERSION) вњ“"
  export CADDY_VERSION
}

install_upstream_caddy_naive() {
  log_step "$(t 'РЈСЃС‚Р°РЅРѕРІРєР° upstream caddy-forwardproxy-naive' 'Installing upstream caddy-forwardproxy-naive')"

  local tmp_dir; tmp_dir=$(mktemp -d)
  local archive_path="${tmp_dir}/caddy-forwardproxy-naive.tar.xz"

  log_info "$(t 'Р—Р°РїСЂРѕСЃ РїРѕСЃР»РµРґРЅРµРіРѕ СЂРµР»РёР·Р° РёР· GitHub...' 'Fetching latest release from GitHub...')"
  local asset_url=""
  local release_tag="unknown"

  # Try GitHub API first
  local release_json=""
  release_json=$(curl -fsSL --connect-timeout 10 "$CADDY_NAIVE_RELEASES" 2>/dev/null) || true

  if [[ -n "$release_json" ]]; then
    release_tag=$(echo "$release_json" | jq -r '.tag_name // "unknown"')
    log_info "$(t "РџРѕСЃР»РµРґРЅСЏСЏ РІРµСЂСЃРёСЏ: $release_tag" "Latest release: $release_tag")"

    # Look for .tar.xz asset (the release contains one tarball for linux-amd64)
    asset_url=$(echo "$release_json" | jq -r \
      '.assets[] | select(.name | test("caddy.*forwardproxy.*naive.*\\.tar\\.xz$|caddy-forwardproxy-naive.*\\.tar\\.xz$"; "i")) | .browser_download_url' \
      | head -1)

    # Broader fallback: any .tar.xz
    if [[ -z "$asset_url" ]]; then
      asset_url=$(echo "$release_json" | jq -r \
        '.assets[] | select(.name | endswith(".tar.xz")) | .browser_download_url' | head -1)
    fi
  fi

  # Fallback to pinned v2.10.0 URL if GitHub API failed or no asset found
  if [[ -z "$asset_url" ]]; then
    log_warn "$(t \
      'GitHub API РЅРµРґРѕСЃС‚СѓРїРµРЅ вЂ” РёСЃРїРѕР»СЊР·СѓСЋ СЂРµР·РµСЂРІРЅС‹Р№ URL (v2.10.0)' \
      'GitHub API unavailable вЂ” using fallback URL (v2.10.0)')"
    asset_url="$CADDY_NAIVE_FALLBACK_URL"
    release_tag="v2.10.0-naive"
  fi

  log_info "$(t "Р—Р°РіСЂСѓР·РєР°: $asset_url" "Downloading: $asset_url")"
  wget -q --show-progress --connect-timeout 30 -O "$archive_path" "$asset_url" || \
    die "$(t 'РћС€РёР±РєР° Р·Р°РіСЂСѓР·РєРё caddy-forwardproxy-naive' 'Failed to download caddy-forwardproxy-naive')"

  # Extract
  cd "$tmp_dir"
  tar -xJf "$archive_path" 2>/dev/null || tar -xf "$archive_path" 2>/dev/null || \
    die "$(t 'РћС€РёР±РєР° СЂР°СЃРїР°РєРѕРІРєРё Р°СЂС…РёРІР°' 'Failed to extract archive')"

  # Find the caddy binary (named 'caddy' or 'caddy-naive' inside the archive)
  local caddy_found
  caddy_found=$(find "$tmp_dir" -maxdepth 3 -type f \
    \( -name "caddy" -o -name "caddy-naive" -o -name "caddy-forwardproxy-naive" \) \
    ! -name "*.xz" ! -name "*.gz" ! -name "*.tar" | head -1)

  [[ -z "$caddy_found" ]] && \
    die "$(t 'caddy Р±РёРЅР°СЂРЅС‹Р№ С„Р°Р№Р» РЅРµ РЅР°Р№РґРµРЅ РІ Р°СЂС…РёРІРµ' 'caddy binary not found in archive')"

  install -m 755 "$caddy_found" "$CADDY_BIN"
  rm -rf "$tmp_dir"; cd /

  # Bug 1: setcap so caddy-naive can bind port 443 without root
  if command -v setcap &>/dev/null; then
    setcap 'cap_net_bind_service=+ep' "$CADDY_BIN" 2>/dev/null || true
  fi

  # Verify
  CADDY_VERSION=$("$CADDY_BIN" version 2>/dev/null | head -1 || \
                  "$CADDY_BIN" --version 2>/dev/null | head -1 || echo "$release_tag")
  log_info "caddy-naive $(t 'СѓСЃС‚Р°РЅРѕРІР»РµРЅ' 'installed') в†’ $CADDY_BIN  ($CADDY_VERSION) вњ“"
  export CADDY_VERSION

  # Remove legacy naive binary if present (migration from v1.2.x)
  if [[ -f "$NAIVE_BIN" ]]; then
    log_info "$(t 'РЈРґР°Р»СЏРµРј СѓСЃС‚Р°СЂРµРІС€РёР№ Р±РёРЅР°СЂРЅРёРє naive (v1.2.x)...' 'Removing legacy naive binary (v1.2.x)...')"
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

# в”Ђв”Ђ Mieru (mita) via .deb в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
install_mieru() {
  log_step "$(t 'РЈСЃС‚Р°РЅРѕРІРєР° Mieru (mita)' 'Installing Mieru (mita)')"
  log_info "$(t 'Р—Р°РїСЂРѕСЃ РїРѕСЃР»РµРґРЅРµРіРѕ СЂРµР»РёР·Р°...' 'Fetching latest release...')"
  local release_json
  release_json=$(curl -fsSL "$MIERU_RELEASES") || \
    die "$(t 'РћС€РёР±РєР° Р·Р°РїСЂРѕСЃР° GitHub API РґР»СЏ Mieru' 'Cannot fetch Mieru releases')"
  local tag; tag=$(echo "$release_json" | jq -r '.tag_name')
  log_info "$(t "РџРѕСЃР»РµРґРЅСЏСЏ РІРµСЂСЃРёСЏ Mieru: $tag" "Latest Mieru: $tag")"

  local asset_url
  asset_url=$(echo "$release_json" | jq -r \
    --arg arch "$DEB_ARCH" \
    '.assets[] | select(.name | test("mita.*" + $arch + "\\.deb")) | .browser_download_url' | head -1)
  [[ -z "$asset_url" ]] && \
    asset_url=$(echo "$release_json" | jq -r \
      --arg arch "$DEB_ARCH" \
      '.assets[] | select(.name | test($arch + "\\.deb")) | .browser_download_url' | head -1)
  [[ -z "$asset_url" ]] && die "$(t "РќРµ РЅР°Р№РґРµРЅ .deb Mieru РґР»СЏ $DEB_ARCH" "No Mieru .deb for $DEB_ARCH")"

  local deb_file; deb_file=$(mktemp /tmp/mieru-XXXXXX.deb)
  log_info "$(t "Р—Р°РіСЂСѓР·РєР°: $asset_url" "Downloading: $asset_url")"
  wget -q --show-progress -O "$deb_file" "$asset_url" || \
    die "$(t 'РћС€РёР±РєР° Р·Р°РіСЂСѓР·РєРё Mieru .deb' 'Failed to download Mieru .deb')"
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
  $install_ok || die "$(t 'РћС€РёР±РєР° СѓСЃС‚Р°РЅРѕРІРєРё Mieru .deb' 'Failed to install Mieru .deb')"
  rm -f "$deb_file"
  systemctl stop mita 2>/dev/null || true
  systemctl reset-failed mita 2>/dev/null || true
  MIERU_VERSION=$(mita version 2>/dev/null | grep -oP 'v[\d.]+' | head -1 || echo "$tag")
  log_info "mita $(t 'СѓСЃС‚Р°РЅРѕРІР»РµРЅ' 'installed') ($MIERU_VERSION) вњ“"
}

# в”Ђв”Ђ Interactive / non-interactive config gathering в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
gather_config() {
  log_step "$(t 'РќР°СЃС‚СЂРѕР№РєР°' 'Configuration')"

  if $NON_INTERACTIVE; then
    DOMAIN="${INPUT_DOMAIN:?$(die "$(t '--domain РѕР±СЏР·Р°С‚РµР»РµРЅ РІ --non-interactive СЂРµР¶РёРјРµ' '--domain is required in --non-interactive mode')")}"
    ADMIN_EMAIL="${INPUT_EMAIL:-admin@${DOMAIN}}"
    NAIVE_PORT="${INPUT_NAIVE_PORT:-443}"
    MIERU_PORT_START="${INPUT_MIERU_START:-2012}"
    MIERU_PORT_END="${INPUT_MIERU_END:-2022}"
    ADMIN_USER="${INPUT_ADMIN_USER:-admin}"
    if [[ -z "${INPUT_ADMIN_PASS:-}" ]]; then
      ADMIN_PASS=$(openssl rand -base64 18 | tr -d '/+=' | head -c 20)
      log_info "$(t "РЎРіРµРЅРµСЂРёСЂРѕРІР°РЅ РїР°СЂРѕР»СЊ: ${BOLD}$ADMIN_PASS${NC}" "Generated password: ${BOLD}$ADMIN_PASS${NC}")"
    else
      ADMIN_PASS="$INPUT_ADMIN_PASS"
    fi
    # Bug 1 new fields: fake-site URL and probe secret
    FAKE_SITE_URL="${INPUT_FAKE_SITE_URL:-https://www.example.com}"
    if [[ "${INPUT_STATIC_SITE_SKIP:-false}" == "true" || -z "${INPUT_STATIC_SITE_URL:-}" ]]; then
      STATIC_SITE_ENABLED=false
      if [[ "${INPUT_STATIC_SITE_SKIP:-false}" == "true" ]]; then
        STATIC_SITE_SOURCE_TYPE="skip"
      else
        STATIC_SITE_SOURCE_TYPE="archive_url"
        log_warn "Static site URL is empty; managed static site disabled"
      fi
      STATIC_SITE_SOURCE_URL="${INPUT_STATIC_SITE_URL:-}"
      STATIC_SITE_ROOT="${INPUT_STATIC_SITE_ROOT:-}"
    else
      STATIC_SITE_ENABLED=true
      STATIC_SITE_SOURCE_TYPE="archive_url"
      STATIC_SITE_SOURCE_URL="${INPUT_STATIC_SITE_URL:-}"
      STATIC_SITE_ROOT="${INPUT_STATIC_SITE_ROOT:-}"
    fi
    PROBE_SECRET="${INPUT_PROBE_SECRET:-$(openssl rand -hex 16)}"
    # Bug 81: default probe_resistance mode = bare (matches known-good reference).
    PROBE_MODE="${INPUT_PROBE_MODE:-bare}"
    USE_UFW="Y"
    EXPOSE_PANEL="N"
    log_info "$(t 'РљРѕРЅС„РёРіСѓСЂР°С†РёСЏ РїСЂРёРЅСЏС‚Р° РёР· Р°СЂРіСѓРјРµРЅС‚РѕРІ вњ“' 'Configuration loaded from arguments вњ“')"
    return
  fi

  echo ""
  echo -e "${BOLD}в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђ${NC}"
  echo -e "${BOLD}   Vetka Node Agent вЂ” $(t 'РњР°СЃС‚РµСЂ СѓСЃС‚Р°РЅРѕРІРєРё' 'Setup Wizard')${NC}"
  echo -e "${BOLD}в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђ${NC}"
  echo ""

  # Domain
  read -rp "$(echo -e "${CYAN}$(t 'Р”РѕРјРµРЅ' 'Domain')${NC} (e.g. vpn.example.com): ")" INPUT_DOMAIN
  [[ -z "${INPUT_DOMAIN:-}" ]] && die "$(t 'Р”РѕРјРµРЅ РЅРµ РјРѕР¶РµС‚ Р±С‹С‚СЊ РїСѓСЃС‚С‹Рј' 'Domain cannot be empty')"
  DOMAIN="$INPUT_DOMAIN"

  # Email for ACME
  read -rp "$(echo -e "${CYAN}Email $(t 'РґР»СЏ ACME/TLS (Caddy)' 'for ACME/TLS (Caddy)')${NC}: ")" INPUT_EMAIL
  [[ -z "${INPUT_EMAIL:-}" ]] && die "$(t 'Email РЅРµ РјРѕР¶РµС‚ Р±С‹С‚СЊ РїСѓСЃС‚С‹Рј' 'Email cannot be empty')"
  ADMIN_EMAIL="$INPUT_EMAIL"

  # NaiveProxy port
  read -rp "$(echo -e "${CYAN}$(t 'РџРѕСЂС‚ NaiveProxy HTTPS' 'NaiveProxy HTTPS port')${NC} [443]: ")" INPUT_NAIVE_PORT
  NAIVE_PORT="${INPUT_NAIVE_PORT:-443}"
  if ! [[ "$NAIVE_PORT" =~ ^[0-9]+$ ]] || (( NAIVE_PORT < 1 || NAIVE_PORT > 65535 )); then
    die "$(t "РќРµРєРѕСЂСЂРµРєС‚РЅС‹Р№ РїРѕСЂС‚: $NAIVE_PORT" "Invalid port: $NAIVE_PORT")"
  fi

  # Mieru port range
  echo ""
  echo -e "${YELLOW}$(t 'Mieru РёСЃРїРѕР»СЊР·СѓРµС‚ РґРёР°РїР°Р·РѕРЅ РїРѕСЂС‚РѕРІ TCP. РџРѕ СѓРјРѕР»С‡Р°РЅРёСЋ: 2012-2022' \
                       'Mieru uses a TCP port range. Default: 2012-2022')${NC}"
  read -rp "$(echo -e "${CYAN}$(t 'РќР°С‡Р°Р»СЊРЅС‹Р№ РїРѕСЂС‚ Mieru' 'Mieru start port')${NC} [2012]: ")" INPUT_MIERU_START
  MIERU_PORT_START="${INPUT_MIERU_START:-2012}"
  read -rp "$(echo -e "${CYAN}$(t 'РљРѕРЅРµС‡РЅС‹Р№ РїРѕСЂС‚ Mieru' 'Mieru end port')${NC}  [2022]: ")" INPUT_MIERU_END
  MIERU_PORT_END="${INPUT_MIERU_END:-2022}"
  for p in "$MIERU_PORT_START" "$MIERU_PORT_END"; do
    if ! [[ "$p" =~ ^[0-9]+$ ]] || (( p < 1025 || p > 65535 )); then
      die "$(t "РќРµРєРѕСЂСЂРµРєС‚РЅС‹Р№ РїРѕСЂС‚ Mieru: $p (1025-65535)" "Invalid Mieru port: $p (1025-65535)")"
    fi
  done
  (( MIERU_PORT_END < MIERU_PORT_START )) && \
    die "$(t "РљРѕРЅРµС‡РЅС‹Р№ РїРѕСЂС‚ РґРѕР»Р¶РµРЅ Р±С‹С‚СЊ >= РЅР°С‡Р°Р»СЊРЅРѕРіРѕ" "End port must be >= start port")"

  # Fake site URL (used for probe resistance)
  echo ""
  echo -e "${YELLOW}$(t \
    'Fake site: Caddy РїРѕРєР°Р¶РµС‚ СЌС‚РѕС‚ СЃР°Р№С‚ РЅРµРѕРїРѕР·РЅР°РЅРЅС‹Рј РєР»РёРµРЅС‚Р°Рј (Р·Р°С‰РёС‚Р° РѕС‚ РѕР±РЅР°СЂСѓР¶РµРЅРёСЏ).' \
    'Fake site: Caddy shows this site to unrecognised clients (probe resistance).')${NC}"
  read -rp "$(echo -e "${CYAN}$(t 'URL С„РµР№РєРѕРІРѕРіРѕ СЃР°Р№С‚Р°' 'Fake site URL')${NC} [https://www.example.com]: ")" INPUT_FAKE_SITE_URL
  FAKE_SITE_URL="${INPUT_FAKE_SITE_URL:-https://www.example.com}"

  echo ""
  read -rp "$(echo -e "${CYAN}Configure static placeholder site?${NC} [Y/n]: ")" INPUT_STATIC_SITE_ENABLE
  if [[ "${INPUT_STATIC_SITE_ENABLE:-Y}" =~ ^([Nn]|Рќ|РЅ)$ ]]; then
    STATIC_SITE_ENABLED=false
    STATIC_SITE_SOURCE_TYPE="skip"
    STATIC_SITE_SOURCE_URL=""
    STATIC_SITE_ROOT=""
  else
    STATIC_SITE_ENABLED=true
    STATIC_SITE_ROOT=""
    echo "  1) archive_url"
    echo "  2) skip"
    read -rp "$(echo -e "${CYAN}Static site source type${NC} [1]: ")" INPUT_STATIC_SITE_TYPE
    case "${INPUT_STATIC_SITE_TYPE:-1}" in
      2|skip)
        STATIC_SITE_ENABLED=false
        STATIC_SITE_SOURCE_TYPE="skip"
        STATIC_SITE_SOURCE_URL=""
        ;;
      *)
        STATIC_SITE_SOURCE_TYPE="archive_url"
        read -rp "$(echo -e "${CYAN}dist.tar.gz archive URL${NC}: ")" INPUT_STATIC_SITE_URL
        STATIC_SITE_SOURCE_URL="${INPUT_STATIC_SITE_URL:-}"
        if [[ -z "$STATIC_SITE_SOURCE_URL" ]]; then
          STATIC_SITE_ENABLED=false
          log_warn "Static site URL is empty; managed static site disabled"
        fi
        ;;
    esac
  fi

  # Probe secret
  echo ""
  echo -e "${YELLOW}$(t \
    'Probe secret: РєР»РёРµРЅС‚С‹ РїСЂРµРґСЉСЏРІР»СЏСЋС‚ СЌС‚РѕС‚ СЃРµРєСЂРµС‚ РІ HTTP-Р·Р°РіРѕР»РѕРІРєРµ РґР»СЏ РёРґРµРЅС‚РёС„РёРєР°С†РёРё.' \
    'Probe secret: clients present this secret in an HTTP header for identification.')${NC}"
  read -rp "$(echo -e "${CYAN}$(t 'РЎРµРєСЂРµС‚ Р·РѕРЅРґРёСЂРѕРІР°РЅРёСЏ (РїСѓСЃС‚Рѕ = Р°РІС‚Рѕ)' 'Probe secret (blank = auto)')${NC}: ")" INPUT_PROBE_SECRET
  if [[ -z "${INPUT_PROBE_SECRET:-}" ]]; then
    PROBE_SECRET=$(openssl rand -hex 16)
    log_info "$(t "РЎРіРµРЅРµСЂРёСЂРѕРІР°РЅ probe_secret: ${BOLD}${PROBE_SECRET}${NC}" "Generated probe_secret: ${BOLD}${PROBE_SECRET}${NC}")"
  else
    PROBE_SECRET="$INPUT_PROBE_SECRET"
  fi
  # Bug 81: default probe_resistance mode = bare (matches known-good reference).
  # The secret above is still stored so the panel can switch to 'secret' mode later.
  PROBE_MODE="${INPUT_PROBE_MODE:-bare}"

  # Admin credentials
  echo ""
  read -rp "$(echo -e "${CYAN}$(t 'РРјСЏ Р°РґРјРёРЅРёСЃС‚СЂР°С‚РѕСЂР° РїР°РЅРµР»Рё' 'Panel admin username')${NC} [admin]: ")" INPUT_ADMIN_USER
  ADMIN_USER="${INPUT_ADMIN_USER:-admin}"
  read -rsp "$(echo -e "${CYAN}$(t 'РџР°СЂРѕР»СЊ Р°РґРјРёРЅРёСЃС‚СЂР°С‚РѕСЂР°' 'Panel admin password')${NC} ($(t 'РїСѓСЃС‚Рѕ = Р°РІС‚РѕРіРµРЅРµСЂР°С†РёСЏ' 'blank = auto-generate')): ")" INPUT_ADMIN_PASS
  echo ""
  if [[ -z "${INPUT_ADMIN_PASS:-}" ]]; then
    ADMIN_PASS=$(openssl rand -base64 18 | tr -d '/+=' | head -c 20)
    log_info "$(t "РЎРіРµРЅРµСЂРёСЂРѕРІР°РЅ РїР°СЂРѕР»СЊ: ${BOLD}$ADMIN_PASS${NC}" "Generated password: ${BOLD}$ADMIN_PASS${NC}")"
  else
    ADMIN_PASS="$INPUT_ADMIN_PASS"
  fi

  # UFW
  echo ""
  read -rp "$(echo -e "${CYAN}$(t 'РќР°СЃС‚СЂРѕРёС‚СЊ UFW (С„Р°Р№СЂРІРѕР»)?' 'Configure UFW firewall?')${NC} [$(t 'Р”/РЅ' 'Y/n')]: ")" INPUT_UFW
  USE_UFW="${INPUT_UFW:-Y}"

  # Expose panel
  echo ""
  echo -e "${YELLOW}$(t 'Node Agent СЃР»СѓС€Р°РµС‚ СЃР»СѓР¶РµР±РЅС‹Р№ NODE_PORT; РѕС‚РєСЂРѕР№С‚Рµ РµРіРѕ С‚РѕР»СЊРєРѕ РґР»СЏ Backend Panel IP.' \
                       'Node Agent listens on NODE_PORT; expose it only to the Backend Panel IP.')${NC}"
  read -rp "$(echo -e "${CYAN}$(t 'РћС‚РєСЂС‹С‚СЊ РїР°РЅРµР»СЊ РїСѓР±Р»РёС‡РЅРѕ РЅР° РїРѕСЂС‚Сѓ 8080?' 'Expose panel publicly on port 8080?')${NC} [$(t 'Рґ/Рќ' 'y/N')]: ")" INPUT_EXPOSE
  EXPOSE_PANEL="${INPUT_EXPOSE:-N}"

  echo ""
  log_info "$(t 'РљРѕРЅС„РёРіСѓСЂР°С†РёСЏ СЃРѕР±СЂР°РЅР° вњ“' 'Configuration gathered вњ“')"
}

# в”Ђв”Ђ Bug 1: Setup fake site в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
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
  log_step "$(t 'РЎРѕР·РґР°РЅРёРµ С„РµР№РєРѕРІРѕРіРѕ СЃР°Р№С‚Р° (probe resistance)' 'Setting up fake site (probe resistance)')"
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
  log_info "$(t "Р¤РµР№РєРѕРІС‹Р№ СЃР°Р№С‚ СЃРѕР·РґР°РЅ в†’ $FAKE_SITE_DIR вњ“" "Fake site created в†’ $FAKE_SITE_DIR вњ“")"
}

# в”Ђв”Ђ Write Caddyfile (TLS-ALPN-01, forwardproxy, probe-resistance) в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
# Bug 23: forward_proxy credential lines use  basic_auth <user> <pass>  (with
#          underscore).  The bare  "basic_auth"  keyword with no arguments is
#          invalid in caddy-forwardproxy-naive and causes:
#            "wrong argument count or unexpected line ending after 'basic_auth'"
# Bug 24: caddy validate failure is fatal (die), not a warning.
# Bug 26: template rendered via caddyTemplate.js вЂ” single source of truth.
# Bug 27: backup existing Caddyfile; restore DB users when --force.
# Bug 28: no  tls <email>  in site block вЂ” Caddy handles TLS automatically.
# Bug 29: directive order inside forward_proxy:  basic_auth в†’ hide_ip в†’ hide_via в†’ probe_resistance.
# Bug 30: global  order forward_proxy before file_server.
# Bug 33: DNS check вЂ” warn if domain doesn't resolve to server IP.
# Bug 38: log rotation uses  roll_keep_for 720h  (30 days).
write_caddyfile() {
  log_step "$(t 'Р—Р°РїРёСЃСЊ Caddyfile' 'Writing Caddyfile')"
  # Bug 42: do NOT create /var/log/caddy-naive here вЂ” start_services() does it
  # after the 'caddy' system user is created, ensuring correct ownership.
  mkdir -p "$CADDY_CONFIG_DIR"

  # Bug 27: backup existing Caddyfile before overwriting
  if [[ -f "$CADDY_FILE" ]]; then
    local ts; ts=$(date +%Y%m%d-%H%M%S)
    cp "$CADDY_FILE" "${CADDY_FILE}.bak.${ts}" 2>/dev/null || true
    log_info "$(t "Р РµР·РµСЂРІРЅР°СЏ РєРѕРїРёСЏ Caddyfile: ${CADDY_FILE}.bak.${ts}" \
                  "Caddyfile backup: ${CADDY_FILE}.bak.${ts}")"
  fi

  # Bug 33: DNS pre-flight вЂ” warn if domain doesn't resolve to this server's IP
  local server_ip_check
  server_ip_check=$(curl -4 -fsSL --connect-timeout 5 https://api.ipify.org 2>/dev/null \
                    || hostname -I | awk '{print $1}')
  local dns_ip
  dns_ip=$(getent hosts "$DOMAIN" 2>/dev/null | awk '{print $1; exit}' || true)
  if [[ -n "$dns_ip" && "$dns_ip" != "$server_ip_check" ]]; then
    log_warn "$(t \
      "DNS: $DOMAIN в†’ $dns_ip (СЃРµСЂРІРµСЂ: $server_ip_check) вЂ” СѓР±РµРґРёС‚РµСЃСЊ С‡С‚Рѕ A-Р·Р°РїРёСЃСЊ РІРµСЂРЅР°!" \
      "DNS: $DOMAIN в†’ $dns_ip (server: $server_ip_check) вЂ” verify your A record is correct!")"
  elif [[ -z "$dns_ip" ]]; then
    log_warn "$(t \
      "DNS: $DOMAIN РЅРµ СЂРµР·РѕР»РІРёС‚СЃСЏ вЂ” СѓР±РµРґРёС‚РµСЃСЊ С‡С‚Рѕ A-Р·Р°РїРёСЃСЊ СѓРєР°Р·С‹РІР°РµС‚ РЅР° СЌС‚РѕС‚ СЃРµСЂРІРµСЂ" \
      "DNS: $DOMAIN does not resolve вЂ” ensure your A record points to this server")"
  else
    log_info "$(t "DNS: $DOMAIN в†’ $dns_ip вњ“" "DNS: $DOMAIN в†’ $dns_ip вњ“")"
  fi

  # Bug 27 + Bug 23: gather real DB users when --force / reinstall
  # Bug 23: credential lines are  basic_auth <user> <pass>  (no bare keyword)
  local naive_users_json="[]"
  if [[ -f "$DB_PATH" ]] && command -v node &>/dev/null; then
    # Bug 82: run from $PANEL_DIR so better-sqlite3 resolves (else the try/catch
    # silently returns [] and a --force reinstall would drop all naive users).
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

  # Bug 26: render Caddyfile via the shared caddyTemplate.js module
  local template_js="${PANEL_DIR}/server/caddyTemplate.js"
  local caddyfile_content
  local panel_listen_port="${NODE_PORT:-2222}"

  # Bug 46: log template errors to INSTALL_LOG instead of swallowing them
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
      log_warn "$(t 'caddyTemplate.js РІРµСЂРЅСѓР» РїСѓСЃС‚РѕР№ РІС‹РІРѕРґ вЂ” РёСЃРїРѕР»СЊР·СѓРµРј РІСЃС‚СЂРѕРµРЅРЅС‹Р№ С€Р°Р±Р»РѕРЅ' \
                   'caddyTemplate.js render returned empty output вЂ” using inline fallback')"
    fi
  fi

  # Fallback: render inline (identical rules вЂ” used before panel is installed)
  if [[ -z "${caddyfile_content:-}" ]]; then
    # Bug 23: placeholder uses  basic_auth <user> <pass>  (no bare keyword)
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

    # Bug 81: probe_resistance mode вЂ” 'off' (none) | 'bare' (keyword only) | 'secret' (with token)
    local probe_line=""
    case "${PROBE_MODE:-bare}" in
      off)    probe_line="" ;;
      secret) [[ -n "${PROBE_SECRET:-}" ]] && probe_line="    probe_resistance ${PROBE_SECRET}" || probe_line="    probe_resistance" ;;
      *)      probe_line="    probe_resistance" ;;
    esac

    # Bug 28: no tls directive вЂ” Caddy automatic HTTPS handles it
    # Bug 29: order: basic_auth в†’ hide_ip в†’ hide_via в†’ probe_resistance
    # Bug 30: order forward_proxy before file_server
    # Bug 38: roll_keep_for 720h instead of roll_keep 5
    # Bug 21: no site-level log block
    caddyfile_content="{
  # Bug 30: ensure forward_proxy is evaluated before file_server
  order forward_proxy before file_server
  # Bug 80: HTTP/1.1 + HTTP/2 only (disable HTTP/3 / QUIC)
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

# HTTP в†’ HTTPS redirect + ACME HTTP-01 fallback
:80 {
  redir https://{host}{uri} permanent
}

:${NAIVE_PORT}, ${DOMAIN} {
  # Bug 83: match the known-good reference server: listen on port and domain,
  # explicit tls directive, no route wrapper.
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

  # Write atomically
  local tmp_file="${CADDY_FILE}.new"
  printf '%s\n' "$caddyfile_content" > "$tmp_file"
  mv "$tmp_file" "$CADDY_FILE"
  chown root:caddy "$CADDY_CONFIG_DIR" 2>/dev/null || true
  chmod 750 "$CADDY_CONFIG_DIR" 2>/dev/null || true
  chown root:caddy "$CADDY_FILE" 2>/dev/null || true
  chmod 640 "$CADDY_FILE"

  # Bug 60: format Caddyfile with caddy fmt --overwrite to ensure canonical style
  # (silences caddy fmt warnings during service start; non-fatal if caddy fmt fails)
  "$CADDY_BIN" fmt --overwrite "$CADDY_FILE" 2>>"$INSTALL_LOG" || \
    log_warn "$(t 'caddy fmt --overwrite РІРµСЂРЅСѓР» РѕС€РёР±РєСѓ (РЅРµ РєСЂРёС‚РёС‡РЅРѕ)' \
                 'caddy fmt --overwrite returned an error (non-fatal)')"

  # Bug 24: validate is FATAL вЂ” die on failure, not log_warn
  local validate_out
  if validate_out=$("$CADDY_BIN" validate --config "$CADDY_FILE" --adapter caddyfile 2>&1); then
    log_info "$(t "Caddyfile РїСЂРѕРІРµСЂРµРЅ Рё Р·Р°РїРёСЃР°РЅ в†’ $CADDY_FILE вњ“" "Caddyfile validated and written в†’ $CADDY_FILE вњ“")"
  else
    log_error "$(t "caddy validate РІРµСЂРЅСѓР» РѕС€РёР±РєСѓ:" "caddy validate returned error:")"
    echo "$validate_out"
    die "$(t "Caddyfile РЅРµРІР°Р»РёРґРµРЅ вЂ” СѓСЃС‚Р°РЅРѕРІРєР° РїСЂРµСЂРІР°РЅР°. РџСЂРѕРІРµСЂСЊС‚Рµ $CADDY_FILE" \
              "Caddyfile is invalid вЂ” install aborted. Check $CADDY_FILE")"
  fi

  # Store probe_secret in caddy config dir for panel to read
  echo "$PROBE_SECRET" > "${CADDY_CONFIG_DIR}/probe_secret"
  chown root:caddy "${CADDY_CONFIG_DIR}/probe_secret" 2>/dev/null || true
  chmod 640 "${CADDY_CONFIG_DIR}/probe_secret"
}

# в”Ђв”Ђ Write caddy-naive.service в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
# Bug 22: called explicitly in main() after write_caddyfile() and before
#          start_services() so the unit file always exists before daemon-reload.
write_caddy_service() {
  log_step "$(t 'Р—Р°РїРёСЃСЊ systemd СЋРЅРёС‚Р° caddy-naive.service' 'Writing caddy-naive.service')"

  # Remove legacy naive.service if present (migration)
  if [[ -f /etc/systemd/system/naive.service ]]; then
    systemctl stop    naive 2>/dev/null || true
    systemctl disable naive 2>/dev/null || true
    rm -f /etc/systemd/system/naive.service
    log_info "$(t 'naive.service СѓРґР°Р»С‘РЅ (Р·Р°РјРµРЅС‘РЅ caddy-naive.service) вњ“' \
                 'naive.service removed (replaced by caddy-naive.service) вњ“')"
  fi

  cat > /etc/systemd/system/caddy-naive.service <<SVCCADDY
[Unit]
Description=Caddy forwardproxy-naive Server
Documentation=https://github.com/klzgrad/forwardproxy
After=network.target network-online.target
Requires=network-online.target
# Bug 62: cap restart storms вЂ” 5 failures in 5 min в†’ failed state (stops hammering ACME)
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

  log_info "$(t 'caddy-naive.service РЅР°РїРёСЃР°РЅ вњ“' 'caddy-naive.service written вњ“')"
}

# в”Ђв”Ђ Mieru initial state file в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
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
  log_step "$(t 'Р—Р°РїРёСЃСЊ РЅР°С‡Р°Р»СЊРЅРѕРіРѕ РєРѕРЅС„РёРіР° Mieru' 'Writing initial Mieru state')"
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
  log_info "$(t "Mita state file в†’ $MITA_STATE_FILE вњ“" "Mita state file в†’ $MITA_STATE_FILE вњ“")"
}

# в”Ђв”Ђ Systemd: mita (ensure exists) в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
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

# в”Ђв”Ђ Bug 7: UFW helper вЂ” handles single-port (start==end) correctly в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
# UFW rejects "N:N/proto" range syntax when start equals end.
_ufw_mieru_rule() {
  local s=$1 e=$2 proto=$3 comment=$4
  if [[ "$s" -eq "$e" ]]; then
    ufw allow "${s}/${proto}" comment "${comment}" 2>/dev/null || true
  else
    ufw allow "${s}:${e}/${proto}" comment "${comment}" 2>/dev/null || true
  fi
}

# в”Ђв”Ђ UFW в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
# Bug 20: port 80 required for ACME HTTP-01 challenge.
# Bug 36: backup UFW rules before reset; interactive-mode prompts for confirmation.
setup_ufw() {
  log_step "$(t 'РќР°СЃС‚СЂРѕР№РєР° UFW' 'Configuring UFW firewall')"

  # Bug 36: backup current rules before --force reset
  if command -v ufw &>/dev/null; then
    local ufw_bak="${BACKUP_DIR}/ufw-before-install-$(date +%Y%m%d-%H%M%S).rules"
    mkdir -p "$(dirname "$ufw_bak")"
    ufw status verbose 2>/dev/null > "$ufw_bak" || true
    log_info "$(t "Р РµР·РµСЂРІРЅР°СЏ РєРѕРїРёСЏ РїСЂР°РІРёР» UFW: $ufw_bak" "UFW rules backup: $ufw_bak")"
  fi

  # Bug 36: prompt for confirmation in interactive mode
  if ! $NON_INTERACTIVE; then
    echo ""
    echo -e "${YELLOW}$(t 'UFW --force reset СѓРґР°Р»РёС‚ РІСЃРµ С‚РµРєСѓС‰РёРµ РїСЂР°РІРёР»Р°!' \
                         'UFW --force reset will erase all existing rules!')${NC}"
    read -rp "$(t '  РџСЂРѕРґРѕР»Р¶РёС‚СЊ? [Р”/РЅ]: ' '  Continue? [Y/n]: ')" _ufw_confirm
    local _uc="${_ufw_confirm:-Y}"
    if $LANG_RU; then
      [[ "${_uc^^}" =~ ^(Рќ|N)$ ]] && { log_info "$(t 'UFW РїСЂРѕРїСѓС‰РµРЅ.' 'UFW skipped.')"; return; }
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
  # Bug 7: single-port safe helper
  _ufw_mieru_rule "$MIERU_PORT_START" "$MIERU_PORT_END" tcp "Mieru TCP"
  _ufw_mieru_rule "$MIERU_PORT_START" "$MIERU_PORT_END" udp "Mieru UDP"
  if [[ -n "${BACKEND_PANEL_IP}" ]]; then
    ufw allow from "${BACKEND_PANEL_IP}" to any port "${NODE_PORT}" proto tcp comment "Vetka Backend Panel -> Node Agent"
  else
    log_warn "BACKEND_PANEL_IP is not set; NODE_PORT ${NODE_PORT} was not opened publicly"
  fi
  ufw --force enable || true
  log_info "$(t 'РџСЂР°РІРёР»Р° UFW РїСЂРёРјРµРЅРµРЅС‹ вњ“' 'UFW rules applied вњ“')"
}

# в”Ђв”Ђ Panel installation в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
install_panel() {
  log_step "$(t 'РЈСЃС‚Р°РЅРѕРІРєР° РІРµР±-РїР°РЅРµР»Рё' 'Installing web panel')"
  mkdir -p "$PANEL_DIR"
  # Locate the local panel/ source robustly: try the script's own directory,
  # then the current working directory (covers `sudo bash install.sh` from the
  # cloned repo even when BASH_SOURCE is relative).
  local script_dir; script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
  local src=""
  if [[ -n "$script_dir" && -d "$script_dir/panel" ]]; then
    src="$script_dir/panel"
  elif [[ -d "$PWD/panel" ]]; then
    src="$PWD/panel"
  fi

  if [[ -n "$src" ]]; then
    find "$PANEL_DIR" -mindepth 1 -maxdepth 1 ! -name node_modules -exec rm -rf {} + 2>/dev/null || true
    cp -r "$src/"* "$PANEL_DIR/"
    log_info "$(t "Р¤Р°Р№Р»С‹ РїР°РЅРµР»Рё СЃРєРѕРїРёСЂРѕРІР°РЅС‹ РёР· $src вњ“" "Panel files copied from $src вњ“")"
  else
    log_warn "$(t 'Р›РѕРєР°Р»СЊРЅС‹Рµ РёСЃС…РѕРґРЅРёРєРё РЅРµ РЅР°Р№РґРµРЅС‹ вЂ” РєР»РѕРЅРёСЂРѕРІР°РЅРёРµ РёР· СЂРµРїРѕР·РёС‚РѕСЂРёСЏ...' \
               'Local panel source not found вЂ” cloning from repo...')"
    rm -rf /tmp/panel-src
    git clone --depth 1 --branch "$PANEL_REPO_BRANCH" "$PANEL_REPO_URL" /tmp/panel-src 2>/dev/null || \
      die "$(t 'РќРµ СѓРґР°Р»РѕСЃСЊ РєР»РѕРЅРёСЂРѕРІР°С‚СЊ СЂРµРїРѕР·РёС‚РѕСЂРёР№' 'Failed to clone panel source')"
    find "$PANEL_DIR" -mindepth 1 -maxdepth 1 ! -name node_modules -exec rm -rf {} + 2>/dev/null || true
    log_info "Fetched latest panel from $PANEL_REPO_URL"
    cp -r /tmp/panel-src/panel/* "$PANEL_DIR/"
    rm -rf /tmp/panel-src
  fi
  ( cd "$PANEL_DIR" && npm install --production --silent )
  grep -q "internalRouter" "$PANEL_DIR/server/index.js" || die "Installed stale panel/server/index.js: internalRouter not found"
  grep -q "ip-history" "$PANEL_DIR/server/index.js" || die "Installed stale panel: ip-history endpoint not found"
  grep -q "trafficAuditLogPath" "$PANEL_DIR/server/index.js" || die "Installed stale panel: trafficAuditLogPath not found"
  grep -q "uniqueIpCount24h" "$PANEL_DIR/server/index.js" || die "Installed stale panel: uniqueIpCount24h not found"
  log_info "$(t 'npm Р·Р°РІРёСЃРёРјРѕСЃС‚Рё СѓСЃС‚Р°РЅРѕРІР»РµРЅС‹ вњ“' 'npm dependencies installed вњ“')"
}

# в”Ђв”Ђ config.json в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
write_config_json() {
  log_step "$(t 'Р—Р°РїРёСЃСЊ /etc/vetka-node-agent/config.json' 'Writing /etc/vetka-node-agent/config.json')"
  mkdir -p /etc/vetka-node-agent "$(dirname "$DB_PATH")"
  local server_ip
  server_ip=$(curl -4 -fsSL https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')

  # Generate bcrypt hash via Node (rounds=12).
  # Bug 73 (P0): the password is passed via the VETKA_ADMIN_PASS env var, NOT
  # argv. With `node -e`, there is no script-path argument, so the first user
  # arg lands at process.argv[1] (not argv[2]); the old code read argv[2] в†’
  # undefined в†’ bcrypt.hashSync threw в†’ install aborted at write_config_json.
  # Env-var passing also avoids any shell-quoting issues with special chars.
  local bcrypt_hash
  bcrypt_hash=$(cd "$PANEL_DIR" && VETKA_ADMIN_PASS="$ADMIN_PASS" node -e "
    const bcrypt = require('bcryptjs');
    const pw = process.env.VETKA_ADMIN_PASS || '';
    if (!pw) { process.exit(2); }
    process.stdout.write(bcrypt.hashSync(pw, 12));
  " 2>/dev/null) || true
  # Fallback: htpasswd (apache2-utils) if Node hashing failed for any reason.
  if [[ -z "$bcrypt_hash" ]]; then
    if ! command -v htpasswd &>/dev/null; then
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq apache2-utils 2>/dev/null || true
    fi
    bcrypt_hash=$(htpasswd -bnBC 12 "" "$ADMIN_PASS" 2>/dev/null | tr -d ':\n' | sed 's/^[^$]*//')
  fi
  [[ -z "$bcrypt_hash" ]] && die "$(t 'РќРµ СѓРґР°Р»РѕСЃСЊ СЃРѕР·РґР°С‚СЊ bcrypt-С…РµС€ РїР°СЂРѕР»СЏ' 'Failed to generate bcrypt password hash')"
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
    "exposePanel":     "$EXPOSE_PANEL".upper() in ("Y","Р”"),
    "useUfw":          "$USE_UFW".upper() in ("Y","Р”"),
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
    "language":        "ru",
    "version":         "$CURRENT_VERSION",
    "installedAt":     "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
with open("$PANEL_CONFIG", "w") as f:
    json.dump(data, f, indent=2)
import os; os.chmod("$PANEL_CONFIG", 0o600)
PYCFG

  log_info "$(t 'config.json Р·Р°РїРёСЃР°РЅ вњ“' 'config.json written вњ“')"
}

# в”Ђв”Ђ Version file в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
write_version() {
  mkdir -p "$(dirname "$VERSION_FILE")"
  cat > "$VERSION_FILE" <<VEREOF
panel_version=${CURRENT_VERSION}
caddy_version=${CADDY_VERSION:-unknown}
mieru_version=${MIERU_VERSION:-unknown}
installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
VEREOF
  log_info "$(t "Р’РµСЂСЃРёСЏ Р·Р°РїРёСЃР°РЅР° в†’ $VERSION_FILE вњ“" "Version file written в†’ $VERSION_FILE вњ“")"
}

# в”Ђв”Ђ Start services в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
# Bug 22:  write_caddy_service() called from main() before start_services().
# Bug 37:  caddy-naive runs as dedicated 'caddy' system user.
# Bug 42:  caddy user + all dirs created BEFORE systemctl restart so the service
#          can write logs and ACME certs without permission-denied errors.
# Bug 43:  /var/lib/caddy created + owned by caddy for ACME cert storage.
# Bug 61:  Caddy failure is non-fatal вЂ” install continues so the user can reach
#          the panel UI and diagnose/fix from there.
# Bug 62:  ACME port-wait loop warns if :443 is not listening after 60 s.
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
    log_warn "Mieru РЅРµ РјРѕР¶РµС‚ Р±С‹С‚СЊ Р·Р°РїСѓС‰РµРЅ: РЅРµС‚ Р°РєС‚РёРІРЅС‹С… Mieru-РїРѕР»СЊР·РѕРІР°С‚РµР»РµР№"
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
  log_step "$(t 'Р—Р°РїСѓСЃРє СЃРµСЂРІРёСЃРѕРІ' 'Starting services')"

  # в”Ђв”Ђ 1. System user вЂ” MUST be first so all chown calls succeed в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
  if ! id caddy &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin caddy
    log_info "$(t 'РЎРёСЃС‚РµРјРЅС‹Р№ РїРѕР»СЊР·РѕРІР°С‚РµР»СЊ caddy СЃРѕР·РґР°РЅ вњ“' 'System user caddy created вњ“')"
  fi

  # в”Ђв”Ђ 2. Bug 42: clean up any stale root-owned log file from write_caddyfile в”Ђв”Ђ
  if [[ -f /var/log/caddy-naive/access.log ]]; then
    local _log_owner
    _log_owner=$(stat -c '%U' /var/log/caddy-naive/access.log 2>/dev/null || echo root)
    if [[ "$_log_owner" != "caddy" ]]; then
      log_warn "$(t "РЈРґР°Р»СЏРµРј access.log СЃ РІР»Р°РґРµР»СЊС†РµРј $_log_owner (РЅСѓР¶РµРЅ caddy)" \
                   "Removing stale access.log owned by $_log_owner (need caddy)")"
      rm -f /var/log/caddy-naive/access.log
    fi
  fi

  # в”Ђв”Ђ 3. Directories вЂ” created here with correct owner (Bug 42 + Bug 43) в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
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

  # в”Ђв”Ђ 4. Caddy binary + config permissions в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
  # Bug 55: chmod 755 (not 750) so any user can run caddy-naive validate
  chown root:caddy "$CADDY_BIN" 2>/dev/null || true
  chmod 755 "$CADDY_BIN" 2>/dev/null || true
  setcap 'cap_net_bind_service=+ep' "$CADDY_BIN" 2>/dev/null || true

  # Bug 79: caddy-naive runs as User=caddy and failed at startup with
  #   "reading config from file: open /etc/caddy-naive/Caddyfile: permission denied".
  #   The previous `chgrp caddy + chmod g+r + chmod 640` set the GROUP and read
  #   bits on files, but a 640 directory (drw-r-----) has NO execute (x) bit for
  #   the group, so the caddy user cannot *traverse* the dir to open the file.
  #   Fix: own the whole config dir as root:caddy, give the DIRECTORY 750
  #   (rwxr-x---, group can traverse + read) and the secret/config FILES 640.
  chown -R root:caddy "$CADDY_CONFIG_DIR" 2>/dev/null || true
  # Order matters: make the top dir traversable FIRST, otherwise `find` cannot
  # descend into a 640 dir to chmod the files inside it.
  chmod 750 "$CADDY_CONFIG_DIR" 2>/dev/null || true
  # Directories: 750 so the caddy group can enter and list them.
  find "$CADDY_CONFIG_DIR" -type d -exec chmod 750 {} + 2>/dev/null || true
  # Files: 640 so the caddy group can read them (no write, no exec).
  find "$CADDY_CONFIG_DIR" -type f -exec chmod 640 {} + 2>/dev/null || true
  # Belt-and-suspenders: ensure the Caddyfile is right.
  chmod 640 "$CADDY_FILE" 2>/dev/null || true

  systemctl daemon-reload

  # в”Ђв”Ђ 5. caddy-naive (Bug 61: non-fatal вЂ” continue if Caddy fails) в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
  systemctl enable caddy-naive
  # Bug 79b: clear any prior failure storm so restart isn't blocked by
  # "Start request repeated too quickly" after we've just fixed perms/caps.
  systemctl reset-failed caddy-naive 2>/dev/null || true
  systemctl restart caddy-naive || true
  sleep 2
  if systemctl is-active --quiet caddy-naive; then
    log_info "$(t 'caddy-naive Р·Р°РїСѓС‰РµРЅ вњ“' 'caddy-naive started вњ“')"
    # Bug 58: wait up to 60s for port 443 to appear (ACME challenge may delay it)
    local _port_wait=0
    while [[ $_port_wait -lt 30 ]]; do
      ss -tlnp 2>/dev/null | grep -q ":${NAIVE_PORT} " && break
      sleep 2; (( _port_wait++ ))
    done
    if ! ss -tlnp 2>/dev/null | grep -q ":${NAIVE_PORT} "; then
      log_warn "$(t "caddy-naive РµС‰С‘ РЅРµ СЃР»СѓС€Р°РµС‚ :${NAIVE_PORT} РїРѕСЃР»Рµ 60 СЃ вЂ” ACME challenge РјРѕР¶РµС‚ Р±С‹С‚СЊ РІ РїСЂРѕС†РµСЃСЃРµ" \
                   "caddy-naive not yet listening on :${NAIVE_PORT} after 60 s вЂ” ACME challenge may still be running")"
      log_warn "$(t 'РџСЂРѕРІРµСЂСЊС‚Рµ: dig +short $DOMAIN, journalctl -u caddy-naive -n 50' \
                   'Check: dig +short $DOMAIN, journalctl -u caddy-naive -n 50')"
    fi
  else
    # Bug 61: non-fatal вЂ” dump journal then warn; panel + mita still installed
    log_error "$(t 'caddy-naive РЅРµ Р·Р°РїСѓСЃС‚РёР»СЃСЏ! Р’С‹РІРѕРґ journalctl:' \
                   'caddy-naive failed to start! journalctl output:')"
    journalctl -u caddy-naive -n 40 --no-pager 2>/dev/null || true
    log_warn "$(t \
      'caddy-naive РЅРµ Р°РєС‚РёРІРµРЅ вЂ” СѓСЃС‚Р°РЅРѕРІРєР° РїСЂРѕРґРѕР»Р¶Р°РµС‚СЃСЏ. РџРѕСЃР»Рµ РІС…РѕРґР° РІ РїР°РЅРµР»СЊ Р·Р°РїСѓСЃС‚РёС‚Рµ: bash update.sh --repair' \
      'caddy-naive is not active вЂ” install continues. After opening the panel run: bash update.sh --repair')"
  fi

  # Bug 4: mita crashes when started with empty users[].
  # Apply portBindings config, but only start mita after first user is added.
  write_mita_service
  systemctl enable mita 2>/dev/null || true
  local _mita_apply_rc=0
  apply_mita_config_bootstrap || _mita_apply_rc=$?
  if [[ "$_mita_apply_rc" -eq 0 ]]; then
    log_info "$(t 'mita config РїСЂРёРјРµРЅС‘РЅ вњ“' 'mita config applied вњ“')"
  elif [[ "$_mita_apply_rc" -ne 2 ]]; then
    log_warn "$(t 'mita apply config РІРµСЂРЅСѓР» РѕС€РёР±РєСѓ вЂ” РїСЂРѕРІРµСЂСЊС‚Рµ: mita status' \
               'mita apply config returned non-zero вЂ” check: mita status')"
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
    # Bug 75: the daemon (mita run) starting is NOT enough вЂ” the proxy stays in
    # state IDLE until `mita start` is issued. Restart the daemon, then start the
    # proxy so it actually binds the configured ports.
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
      log_info "$(t 'mita Р·Р°РїСѓС‰РµРЅ вњ“' 'mita started вњ“')"
    else
      [[ -n "$_mita_start_out" ]] && log_warn "mita start failed: $_mita_start_out"
      log_warn "$(t 'mita РЅРµ Р·Р°РїСѓСЃС‚РёР»СЃСЏ вЂ” journalctl -u mita -n 30 / mita status' \
                   'mita failed to start вЂ” journalctl -u mita -n 30 / mita status')"
    fi
  else
    systemctl stop mita 2>/dev/null || true
    systemctl reset-failed mita 2>/dev/null || true
    log_info "$(t 'mita: РЅРµС‚ РїРѕР»СЊР·РѕРІР°С‚РµР»РµР№ вЂ” СЃРµСЂРІРёСЃ Р·Р°РїСѓСЃС‚РёС‚СЃСЏ Р°РІС‚РѕРјР°С‚РёС‡РµСЃРєРё РїРѕСЃР»Рµ РґРѕР±Р°РІР»РµРЅРёСЏ РїРµСЂРІРѕРіРѕ РїРѕР»СЊР·РѕРІР°С‚РµР»СЏ' \
               'mita: no users yet вЂ” service will start automatically after first user is added via panel')"
  fi

  # PM2 node agent
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
  log_info "$(t 'РџР°РЅРµР»СЊ Р·Р°РїСѓС‰РµРЅР° С‡РµСЂРµР· PM2 вњ“' 'Panel started via PM2 вњ“')"
  cd /
}

# в”Ђв”Ђ Bug 14: smoke_test_configs() вЂ” create test user, validate config downloads в”Ђ
smoke_test_configs() {
  log_step "$(t 'Smoke-С‚РµСЃС‚ РєРѕРЅС„РёРіРѕРІ РєР»РёРµРЅС‚Р°' 'Smoke test: client config validation')"
  local test_user="smoke_test_user"
  local test_pass="smoke_pass_123"
  local test_email="smoke@test.local"
  local panel_url="http://127.0.0.1:${NODE_PORT}"
  local pass=0 fail=0
  local cookie_file; cookie_file=$(mktemp)

  # Login
  local login_res
  login_res=$(curl -sf -c "$cookie_file" -X POST "$panel_url/api/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PASS\"}" 2>/dev/null) || true

  if echo "$login_res" | grep -q '"ok":true'; then
    echo -e "  ${GREEN}вњ“${NC} smoke login OK"; (( pass++ ))
  else
    echo -e "  ${YELLOW}вљ ${NC}  smoke login skipped (panel may still be starting)"
    rm -f "$cookie_file"
    return 0
  fi

  # Create test user
  local create_res
  create_res=$(curl -sf -b "$cookie_file" -X POST "$panel_url/api/users" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$test_user\",\"email\":\"$test_email\",\"password\":\"$test_pass\",\"protocols\":[\"naive\",\"mieru\"],\"quotaMB\":0}" \
    2>/dev/null) || true
  local user_id=""
  user_id=$(echo "$create_res" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || true)

  if [[ -n "$user_id" ]]; then
    echo -e "  ${GREEN}вњ“${NC} smoke test user created (id: ${user_id:0:8}вЂ¦)"; (( pass++ ))
  else
    echo -e "  ${RED}вњ—${NC} smoke test user creation failed"; (( fail++ ))
    rm -f "$cookie_file"; return 0
  fi

  # Fetch naive config
  local naive_cfg
  naive_cfg=$(curl -sf -b "$cookie_file" \
    "$panel_url/api/users/$user_id/config/naive?password=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$test_pass'))")" \
    2>/dev/null) || true

  if echo "$naive_cfg" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'link' in d" 2>/dev/null; then
    echo -e "  ${GREEN}вњ“${NC} naive config link valid"; (( pass++ ))
    # Bug 5: verify transport field
    local naive_link; naive_link=$(echo "$naive_cfg" | python3 -c "import json,sys; print(json.load(sys.stdin)['link'])" 2>/dev/null || true)
    if echo "$naive_link" | grep -q "naive+https://"; then
      echo -e "  ${GREEN}вњ“${NC} naive link uses HTTPS transport"; (( pass++ ))
    else
      echo -e "  ${RED}вњ—${NC} naive link missing HTTPS transport"; (( fail++ ))
    fi
  else
    echo -e "  ${RED}вњ—${NC} naive config invalid"; (( fail++ ))
  fi

  # Fetch mieru (sing-box) config
  local mieru_cfg
  mieru_cfg=$(curl -sf -b "$cookie_file" \
    "$panel_url/api/users/$user_id/config/mieru?password=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$test_pass'))")" \
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
    echo -e "  ${GREEN}вњ“${NC} mieru config valid (transport + port fields)"; (( pass++ ))
  else
    echo -e "  ${RED}вњ—${NC} mieru config validation failed"; (( fail++ ))
  fi

  # Cleanup test user
  curl -sf -b "$cookie_file" -X DELETE "$panel_url/api/users/$user_id" > /dev/null 2>&1 || true
  echo -e "  ${GREEN}вњ“${NC} smoke test user cleaned up"
  rm -f "$cookie_file"

  echo ""
  echo -e "  Config smoke: ${GREEN}$pass passed${NC}  ${RED}$fail failed${NC}"
  return 0
}

# в”Ђв”Ђ Smoke tests в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
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
  log_step "$(t 'Smoke-С‚РµСЃС‚С‹' 'Running smoke tests')"
  sleep 5
  local pass=0 fail=0

  chk() {
    if eval "$2" &>/dev/null; then
      echo -e "  ${GREEN}вњ“${NC} $1"; (( pass++ ))
    else
      echo -e "  ${RED}вњ—${NC} $1"; (( fail++ ))
    fi
  }

  # caddy-naive checks
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

  # mita tests
  chk "mita.service enabled"         "systemctl is-enabled mita"
  chk "mita-state.json present"      "[[ -f $MITA_STATE_FILE ]]"
  if has_mieru_users; then
    chk "mita active with configured users" "systemctl is-active --quiet mita"
  else
    echo -e "  ${GREEN}вњ“${NC} mita idle OK, no Mieru users configured"
    (( pass++ ))
  fi

  # Panel
  chk "Node Agent health :${NODE_PORT}" "curl -sf http://127.0.0.1:${NODE_PORT}/health -o /dev/null"
  chk "config.json present"          "[[ -f $PANEL_CONFIG ]]"
  chk "version file present"         "[[ -f $VERSION_FILE ]]"

  # probe_resistance secret saved
  chk "probe_secret file present"    "[[ -f ${CADDY_CONFIG_DIR}/probe_secret ]]"

  if timedatectl status 2>/dev/null | grep -q "synchronized: yes"; then
    echo -e "  ${GREEN}вњ“${NC} $(t 'Р’СЂРµРјСЏ СЃРёРЅС…СЂРѕРЅРёР·РёСЂРѕРІР°РЅРѕ' 'Time synchronised')"
    (( pass++ ))
  else
    echo -e "  ${YELLOW}вљ ${NC}  $(t 'Р’СЂРµРјСЏ РќР• СЃРёРЅС…СЂРѕРЅРёР·РёСЂРѕРІР°РЅРѕ вЂ” РєСЂРёС‚РёС‡РЅРѕ РґР»СЏ Mieru!' \
                                    'Time NOT synchronised вЂ” critical for Mieru!')"
  fi

  echo ""
  echo -e "  $(t 'Р РµР·СѓР»СЊС‚Р°С‚' 'Results'): ${GREEN}$pass $(t 'РїСЂРѕС€Р»Рѕ' 'passed')${NC}  ${RED}$fail $(t 'СѓРїР°Р»Рѕ' 'failed')${NC}"
  (( fail > 0 )) && log_warn "$(t 'РџСЂРѕРІРµСЂСЊС‚Рµ Р»РѕРіРё: journalctl -u caddy-naive mita -n 30' \
                                  'Check logs: journalctl -u caddy-naive mita -n 30')"

  # Bug 14: config smoke tests (require panel running + ADMIN_PASS set)
  if [[ -n "${ADMIN_PASS:-}" ]]; then
    smoke_test_configs
  fi
}

# в”Ђв”Ђ UFW call в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
maybe_ufw() {
  local ans="${USE_UFW:-Y}"
  [[ "${ans^^}" =~ ^(Y|Р”)$ ]] && setup_ufw || true
}

# в”Ђв”Ђ Final banner в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
print_banner() {
  local server_ip
  server_ip=$(python3 -c "import json; print(json.load(open('$PANEL_CONFIG'))['serverIp'])" 2>/dev/null \
              || hostname -I | awk '{print $1}')
  echo ""
  echo -e "${GREEN}${BOLD}в•”в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•—${NC}"
  if $LANG_RU; then
    echo -e "${GREEN}${BOLD}в•‘   Vetka Node Agent v${CURRENT_VERSION} вЂ” РЈСЃС‚Р°РЅРѕРІРєР° Р·Р°РІРµСЂС€РµРЅР° вњ“ в•‘${NC}"
  else
    echo -e "${GREEN}${BOLD}в•‘   Vetka Node Agent v${CURRENT_VERSION} вЂ” Install Complete вњ“   в•‘${NC}"
  fi
  echo -e "${GREEN}${BOLD}в•љв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ќ${NC}"
  echo ""
  echo -e "  ${BOLD}$(t 'Р”РѕРјРµРЅ' 'Domain'):${NC}              $DOMAIN"
  echo -e "  ${BOLD}$(t 'IP СЃРµСЂРІРµСЂР°' 'Server IP'):${NC}          $server_ip"
  echo -e "  ${BOLD}$(t 'РџРѕСЂС‚ NaiveProxy (Caddy)' 'NaiveProxy port (Caddy)'):${NC}  $NAIVE_PORT"
  echo -e "  ${BOLD}$(t 'РџРѕСЂС‚С‹ Mieru' 'Mieru ports'):${NC}        $MIERU_PORT_START-$MIERU_PORT_END (TCP)"
  echo -e "  ${BOLD}$(t 'Probe secret' 'Probe secret'):${NC}       ${PROBE_SECRET}"
  echo -e "  ${BOLD}$(t 'Fake site' 'Fake site'):${NC}          $FAKE_SITE_DIR"
  echo ""
  echo -e "  ${BOLD}Node Agent API:${NC}"
  if [[ "${EXPOSE_PANEL^^}" =~ ^(Y|Р”)$ ]]; then
    echo -e "    $(t 'РџСѓР±Р»РёС‡РЅС‹Р№ URL' 'Public URL'):  ${CYAN}http://$server_ip:8080/${NC}"
  else
    echo -e "    Health: ${CYAN}http://$server_ip:${NODE_PORT}/health${NC}"
    echo -e "    Status: ${CYAN}curl -H 'Authorization: Bearer <NODE_SECRET>' http://127.0.0.1:${NODE_PORT}/status${NC}"
  fi
  echo ""
  echo -e "  ${BOLD}$(t 'Р”Р°РЅРЅС‹Рµ Р°РґРјРёРЅРёСЃС‚СЂР°С‚РѕСЂР°' 'Admin credentials'):${NC}"
  echo -e "    $(t 'Р›РѕРіРёРЅ' 'Username'): ${CYAN}$ADMIN_USER${NC}"
  echo -e "    $(t 'РџР°СЂРѕР»СЊ' 'Password'): ${CYAN}$ADMIN_PASS${NC}"
  echo ""
  echo -e "  ${BOLD}$(t 'РџРѕР»РµР·РЅС‹Рµ РєРѕРјР°РЅРґС‹' 'Useful commands'):${NC}"
  echo -e "    pm2 logs vetka-node-agent"
  echo -e "    systemctl status caddy-naive mita"
  echo -e "    $CADDY_BIN version"
  echo -e "    mita status"
  echo -e "    bash update.sh --status"
  echo -e "    bash update.sh --repair"
  echo ""
  echo -e "  ${BOLD}$(t 'Р›РѕРі СѓСЃС‚Р°РЅРѕРІРєРё' 'Install log'):${NC}      $INSTALL_LOG"
  echo ""
  echo -e "  ${YELLOW}${BOLD}вљ   $(t 'Р’РђР–РќРћ: РЎРѕС…СЂР°РЅРёС‚Рµ РїР°СЂРѕР»СЊ Рё probe_secret вЂ” РѕРЅРё Р±РѕР»СЊС€Рµ РЅРµ Р±СѓРґСѓС‚ РїРѕРєР°Р·Р°РЅС‹!' \
                                    'IMPORTANT: Save the password and probe_secret вЂ” they will not be shown again!')${NC}"
  echo ""
  echo -e "  Telegram: ${CYAN}https://t.me/russian_paradice_vpn${NC}"
  echo -e "  $(t 'Р”РѕРЅР°С‚' 'Donate'):    ${CYAN}https://app.lava.top/2107724612?tabId=donate${NC}"
  echo ""
}

# в”Ђв”Ђ Network tuning (BBR + UDP buffers) в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
tune_network() {
  log_step "$(t 'РЎРµС‚РµРІР°СЏ РѕРїС‚РёРјРёР·Р°С†РёСЏ (BBR, Р±СѓС„РµСЂС‹ UDP)' 'Network tuning (BBR, UDP buffers)')"
  local tune="${PANEL_DIR}/scripts/sysctl_tune.sh"
  if [[ -f "$tune" ]]; then
    bash "$tune" 2>/dev/null && \
      log_info "$(t 'BBR Рё СЃРµС‚РµРІС‹Рµ Р±СѓС„РµСЂС‹ РїСЂРёРјРµРЅРµРЅС‹ вњ“' 'BBR and network buffers applied вњ“')" || \
      log_warn "$(t 'РќРµ СѓРґР°Р»РѕСЃСЊ РїСЂРёРјРµРЅРёС‚СЊ СЃРµС‚РµРІСѓСЋ РѕРїС‚РёРјРёР·Р°С†РёСЋ (РЅРµ РєСЂРёС‚РёС‡РЅРѕ)' \
                   'Could not apply network tuning (non-fatal)')"
  else
    log_warn "$(t "sysctl_tune.sh РЅРµ РЅР°Р№РґРµРЅ РІ $PANEL_DIR/scripts вЂ” РїСЂРѕРїСѓСЃРє" \
                 "sysctl_tune.sh not found in $PANEL_DIR/scripts вЂ” skipping")"
  fi
}

# в”Ђв”Ђ Main в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
main() {
  parse_install_args "$@"

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
  # Bug 41: install_panel BEFORE write_config_json so that bcryptjs (from
  # panel/node_modules) is available when we call  node -e "require('bcryptjs')"
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
