#!/usr/bin/env bash
# ==============================================================================
# tests/e2e.sh End-to-end regression test for Vetka Node Agent v1.2.6
#
# Tests:
# install validate service-check create-user-via-API re-validate
# curl-https download-config sing-box check uninstall assert-clean
#
# Usage (on a fresh Ubuntu 24.04 amd64 VPS with valid DNS A record):
# sudo bash tests/e2e.sh --domain vpn.example.com --email admin@example.com
# sudo bash tests/e2e.sh --domain vpn.example.com --email admin@example.com --skip-install
# sudo bash tests/e2e.sh --help
#
# Exit codes: 0 = all tests passed 1 = one or more tests failed
# ==============================================================================
set -euo pipefail

# Colours
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

pass_count=0
fail_count=0
warn_count=0

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; (( warn_count++ )); }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "\n${CYAN}${BOLD}==> $*${NC}"; }

pass() { echo -e "  ${GREEN}PASS${NC}  $1"; (( pass_count++ )); }
fail() { echo -e "  ${RED}FAIL${NC}  $1"; (( fail_count++ )); }
skip() { echo -e "  ${YELLOW}SKIP${NC}  $1 (skipped)"; }

# Constants
CADDY_BIN="/usr/local/bin/caddy-naive"
CADDY_FILE="/etc/caddy-naive/Caddyfile"
CADDY_CONFIG_DIR="/etc/caddy-naive"
FAKE_SITE_DIR="/var/www/fake-site"
PANEL_CONFIG="/etc/vetka-node-agent/config.json"
VERSION_FILE="/etc/vetka-node-agent/version"
DB_PATH="/var/lib/vetka-node-agent/cache.sqlite"
MITA_STATE_FILE="/var/lib/vetka-node-agent/mita-state.json"
NODE_PORT="${NODE_PORT:-2222}"
PANEL_URL="http://127.0.0.1:${NODE_PORT}"
ADMIN_USER="admin"
ADMIN_PASS=""          # filled from --admin-pass or auto-detected
DOMAIN=""
EMAIL=""
NAIVE_PORT=443
SKIP_INSTALL=false
SKIP_UNINSTALL=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Argument parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)       DOMAIN="${2:-}";       shift ;;
    --email)        EMAIL="${2:-}";        shift ;;
    --admin-pass)   ADMIN_PASS="${2:-}";   shift ;;
    --naive-port)   NAIVE_PORT="${2:-443}"; shift ;;
    --skip-install)   SKIP_INSTALL=true ;;
    --skip-uninstall) SKIP_UNINSTALL=true ;;
    --help|-h)
      echo "Usage: sudo bash tests/e2e.sh --domain <domain> --email <email> [options]"
      echo "  --admin-pass PASS    admin password (auto-detected from config if omitted)"
      echo "  --naive-port PORT    HTTPS port (default 443)"
      echo "  --skip-install       skip installation step (use existing install)"
      echo "  --skip-uninstall     skip uninstall cleanup step"
      exit 0 ;;
    *) log_warn "Unknown argument: $1" ;;
  esac
  shift
done

[[ $EUID -ne 0 ]] && { log_error "Run as root: sudo bash tests/e2e.sh"; exit 1; }
[[ -z "$DOMAIN" ]]  && { log_error "--domain is required"; exit 1; }
[[ -z "$EMAIL" ]]   && EMAIL="admin@${DOMAIN}"
E2E_NODE_SECRET="${NODE_SECRET:-vetka_e2e_$(openssl rand -hex 24)}"

# Helper: assert with message
assert() {
  local label="$1"; shift
  if eval "$*" &>/dev/null; then pass "$label"; else fail "$label"; fi
}

# Cookie jar for API calls
COOKIE_JAR=$(mktemp)
trap 'rm -f "$COOKIE_JAR"' EXIT

# Detect admin password from config if not supplied
detect_admin_pass() {
  if [[ -z "$ADMIN_PASS" ]] && [[ -f "$PANEL_CONFIG" ]]; then
#
    local from_log
    from_log=$(grep -oP "(?<=Generated password: )[\w]+" \
                 /var/log/vetka-node-agent-install.log 2>/dev/null | tail -1 || true)
    ADMIN_PASS="${from_log:-}"
  fi
  if [[ -z "$ADMIN_PASS" ]]; then
    log_warn "Could not detect admin password - API tests will be skipped"
  fi
}

#
log_step "E2E test suite - Vetka Node Agent v1.2.6"
echo "  Domain:    $DOMAIN"
echo "  Email:     $EMAIL"
echo "  Port:      $NAIVE_PORT"
echo "  Repo root: $REPO_ROOT"
echo "  Node secret: configured (hidden)"

# STEP 1 Install
log_step "Step 1: Install"
if $SKIP_INSTALL; then
  skip "Installation (--skip-install)"
else
  log_info "Running install.sh in non-interactive mode..."
  if NODE_SECRET="$E2E_NODE_SECRET" \
      ALLOW_LOCAL_USER_MUTATIONS=true \
      bash "$REPO_ROOT/install.sh" \
      --non-interactive \
      --domain "$DOMAIN" \
      --email  "$EMAIL" \
      --naive-port "$NAIVE_PORT" \
      --lang en; then
    pass "install.sh exited 0"
  else
    fail "install.sh exited non-zero"
    log_error "Aborting e2e: installation failed. See /var/log/vetka-node-agent-install.log"
    exit 1
  fi
fi

detect_admin_pass

# STEP 2 Caddyfile validation
log_step "Step 2: Caddyfile validation"
assert "Caddyfile exists"                    "[[ -f '$CADDY_FILE' ]]"
assert "probe_secret file exists"            "[[ -f '${CADDY_CONFIG_DIR}/probe_secret' ]]"
SITE_INDEX_LABEL="fake-site index.html exists"
if [[ -f "$PANEL_CONFIG" ]] && command -v jq &>/dev/null && \
   [[ "$(jq -r '.staticSite.enabled // false' "$PANEL_CONFIG" 2>/dev/null)" == "true" ]]; then
  SITE_INDEX_LABEL="static-site index.html exists"
fi
assert "$SITE_INDEX_LABEL"                   "[[ -f '${FAKE_SITE_DIR}/index.html' ]]"

if [[ -x "$CADDY_BIN" ]]; then
  if "$CADDY_BIN" validate --config "$CADDY_FILE" --adapter caddyfile &>/dev/null; then
    pass "caddy validate  Valid configuration"
  else
    fail "caddy validate returned an error"
    "$CADDY_BIN" validate --config "$CADDY_FILE" --adapter caddyfile 2>&1 | head -20 || true
  fi
#
  if grep -qP '^\s+basic_auth\s*$' "$CADDY_FILE" 2>/dev/null; then
    fail "Caddyfile contains bare 'basic_auth' with no arguments (Bug 23)"
  else
    pass "Caddyfile: no bare 'basic_auth' without arguments"
  fi
#
  if grep -qP '^\s+tls\s+\S+@' "$CADDY_FILE" 2>/dev/null; then
    pass "Caddyfile: explicit 'tls <email>' directive present"
  else
    fail "Caddyfile missing explicit 'tls <email>' directive"
  fi
  if grep -q 'protocols h1 h2' "$CADDY_FILE" 2>/dev/null; then
    pass "Caddyfile: HTTP/3/QUIC disabled via h1/h2 protocols"
  else
    fail "Caddyfile missing 'protocols h1 h2'"
  fi
  if stat -c '%U:%G %a' "$CADDY_FILE" 2>/dev/null | grep -q '^root:caddy 640$'; then
    pass "Caddyfile permissions are root:caddy 640"
  else
    fail "Caddyfile permissions are not root:caddy 640"
  fi
#
  if grep -q 'order forward_proxy before file_server' "$CADDY_FILE" 2>/dev/null; then
    pass "Caddyfile: 'order forward_proxy before file_server' present (Bug 30)"
  else
    fail "Caddyfile missing 'order forward_proxy before file_server' (Bug 30)"
  fi
#
  if grep -q 'roll_keep_for' "$CADDY_FILE" 2>/dev/null; then
    pass "Caddyfile: 'roll_keep_for' log rotation present (Bug 38)"
  else
    fail "Caddyfile missing 'roll_keep_for' (Bug 38)"
  fi
#
  log_count=$(grep -c '^\s*log\s*{' "$CADDY_FILE" 2>/dev/null || echo 0)
  if [[ "$log_count" -le 1 ]]; then
    pass "Caddyfile: only one log block (Bug 21)"
  else
    fail "Caddyfile has $log_count log blocks  duplicate (Bug 21)"
  fi
#
  if "$CADDY_BIN" fmt --diff "$CADDY_FILE" 2>/dev/null | grep -q '^[-+]'; then
    log_warn "Caddyfile has fmt differences (Bug 60  caddy fmt may not have run)"
  else
    pass "Caddyfile: caddy fmt shows no differences (Bug 60)"
  fi
else
  skip "caddy binary not found at $CADDY_BIN  skipping validation"
fi

# STEP 3 Service health check
log_step "Step 3: Service health"
assert "caddy-naive.service active"          "systemctl is-active caddy-naive"
assert "caddy-naive runs as user 'caddy' (Bug 37)" \
       "systemctl show caddy-naive -p User | grep -q 'User=caddy'"
assert "mita.service enabled (Bug 64)"       "systemctl is-enabled mita"
if python3 - "$MITA_STATE_FILE" <<'PY' 2>/dev/null
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    data = {}
raise SystemExit(0 if len(data.get("users", [])) > 0 else 1)
PY
then
  assert "mita.service active with configured users" "systemctl is-active --quiet mita"
else
  assert "mita idle OK, no Mieru users configured" "! systemctl is-active --quiet mita"
fi
assert "Node Agent process running (PM2)"         "pm2 list 2>/dev/null | grep -q vetka-node-agent"
assert "Node Agent health responds"             "curl -sf '$PANEL_URL/' -o /dev/null"
assert "config.json present"                 "[[ -f '$PANEL_CONFIG' ]]"
if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); raise SystemExit(0 if d.get('nodeSecret') else 1)" "$PANEL_CONFIG" 2>/dev/null; then
  pass "nodeSecret configured in config.json"
else
  fail "nodeSecret missing from config.json"
fi
assert "version file present"                "[[ -f '$VERSION_FILE' ]]"
assert "agent version in file is 1.2.6"      "grep -q '1.2.6' '$VERSION_FILE'"
assert "DB present"                          "[[ -f '$DB_PATH' ]]"
assert "mita-state.json present"             "[[ -f '$MITA_STATE_FILE' ]]"

# Bug 37: caddy-naive should NOT run as root
assert "caddy-naive NOT running as root (Bug 37)" \
       "! ps aux | grep -v grep | grep caddy-naive | grep -q '^root '"

# Time sync
if timedatectl status 2>/dev/null | grep -q "synchronized: yes"; then
  pass "NTP time synchronised"
else
  log_warn "Time NOT synchronised  critical for Mieru"
fi

# STEP 4 HTTP/HTTPS connectivity
log_step "Step 4: HTTP/HTTPS connectivity"
assert "port :80 listening (ACME + redirect, Bug 20)" \
       "ss -tlnup sport = :80 | grep -q :80"
assert "port :$NAIVE_PORT listening" \
       "ss -tlnup sport = :${NAIVE_PORT} | grep -q :${NAIVE_PORT}"

# HTTP HTTPS redirect (308)
http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 \
              "http://${DOMAIN}/" 2>/dev/null || echo "000")
if [[ "$http_code" == "308" || "$http_code" == "301" || "$http_code" == "302" ]]; then
  pass "HTTP  HTTPS redirect returns $http_code"
else
  log_warn "HTTP redirect returned $http_code (expected 30x; DNS/connectivity may not be ready)"
fi

# HTTPS fake site (200 with Server: Caddy)
https_code=$(curl -sk -o /dev/null -w "%{http_code}" --connect-timeout 10 \
               "https://${DOMAIN}/" 2>/dev/null || echo "000")
if [[ "$https_code" == "200" ]]; then
  pass "HTTPS fake site returns 200"
else
  log_warn "HTTPS returned $https_code (expected 200; TLS cert may still be provisioning)"
fi

# STEP 5 Create user via API + re-validate Caddyfile
log_step "Step 5: Create user via API + Caddyfile re-validation"

if [[ -z "$ADMIN_PASS" ]]; then
  skip "API tests (admin password not available)"
else
#
  login_res=$(curl -sf -c "$COOKIE_JAR" -X POST "$PANEL_URL/api/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" 2>/dev/null) || login_res=""

  if echo "$login_res" | grep -q '"ok":true'; then
    pass "Local UI API login succeeded"

    TEST_USER="e2e_test_$(date +%s)"
    TEST_PASS="E2ePass$(openssl rand -hex 6)"
    TEST_EMAIL="e2e@test.local"

#
    create_res=$(curl -sf -b "$COOKIE_JAR" -X POST "$PANEL_URL/api/users" \
      -H "Content-Type: application/json" \
      -d "{\"username\":\"$TEST_USER\",\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASS\",\"protocols\":[\"naive\",\"mieru\"],\"quotaMB\":0}" \
      2>/dev/null) || create_res=""
    USER_ID=$(echo "$create_res" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)

    if [[ -n "$USER_ID" ]]; then
      pass "User '$TEST_USER' created (id: ${USER_ID:0:8})"

#
      sleep 3

#
      if [[ -x "$CADDY_BIN" ]]; then
        if "$CADDY_BIN" validate --config "$CADDY_FILE" --adapter caddyfile &>/dev/null; then
          pass "Caddyfile still valid after user creation"
        else
          fail "Caddyfile invalid after user creation"
          "$CADDY_BIN" validate --config "$CADDY_FILE" --adapter caddyfile 2>&1 | head -20 || true
        fi
      fi

#
      if grep -q "basic_auth $TEST_USER " "$CADDY_FILE" 2>/dev/null; then
        pass "Caddyfile: user line is 'basic_auth $TEST_USER <pass>' (Bug 23)"
      else
        fail "Caddyfile: expected 'basic_auth $TEST_USER ...' not found (Bug 23)"
      fi

      NODE_SECRET_VALUE=$(python3 -c "import json; d=json.load(open('$PANEL_CONFIG')); print(d.get('nodeSecret',''))" 2>/dev/null || true)
      if [[ -n "$NODE_SECRET_VALUE" ]]; then
        node_status=$(curl -sf -H "Authorization: Bearer $NODE_SECRET_VALUE" "$PANEL_URL/status" 2>/dev/null || true)
        if echo "$node_status" | grep -q '"ok":true'; then
          pass "Node Agent /status works with Bearer NODE_SECRET"
        else
          fail "Node Agent /status failed"
        fi
        internal_health=$(curl -sf -H "Authorization: Bearer $NODE_SECRET_VALUE" "$PANEL_URL/internal/health" 2>/dev/null || true)
        if echo "$internal_health" | grep -q '"ok":true'; then
          pass "Deprecated internal API health works with Bearer NODE_SECRET"
        else
          fail "Internal API health failed"
        fi
        internal_explorer=$(curl -s -H "Authorization: Bearer $NODE_SECRET_VALUE" "$PANEL_URL/internal/sessions/explorer" 2>/dev/null || true)
        if echo "$internal_explorer" | grep -q '"ok":true' && echo "$internal_explorer" | grep -q '"summary"'; then
          pass "Internal sessions explorer returns summary"
        else
          fail "Internal sessions explorer failed"
        fi
        internal_details=$(curl -s -H "Authorization: Bearer $NODE_SECRET_VALUE" "$PANEL_URL/internal/users/$USER_ID/details" 2>/dev/null || true)
        if echo "$internal_details" | grep -q '"ok":true' && echo "$internal_details" | grep -q '"ipHistory"'; then
          pass "Internal user details returns ipHistory"
        else
          fail "Internal user details failed"
        fi
        internal_ip=$(curl -s -H "Authorization: Bearer $NODE_SECRET_VALUE" "$PANEL_URL/internal/ip/127.0.0.1" 2>/dev/null || true)
        if echo "$internal_ip" | grep -q '"ok":true' && echo "$internal_ip" | grep -q '"ip":"127.0.0.1"'; then
          pass "Internal IP lookup works"
        else
          fail "Internal IP lookup failed"
        fi
        internal_logs=$(curl -s -H "Authorization: Bearer $NODE_SECRET_VALUE" "$PANEL_URL/internal/logs/status" 2>/dev/null || true)
        if echo "$internal_logs" | grep -q '"ok":true' && echo "$internal_logs" | grep -q '"authAuditLogRecords"'; then
          pass "Internal logs status works"
        else
          fail "Internal logs status failed"
        fi
      else
        fail "nodeSecret missing from config.json"
      fi

      users_sessions=$(curl -s -b "$COOKIE_JAR" "$PANEL_URL/api/users/sessions" 2>/dev/null || true)
      if echo "$users_sessions" | grep -q 'User not found'; then
        fail "/api/users/sessions was captured by /api/users/:id"
      elif echo "$users_sessions" | grep -q '"ok":true'; then
        pass "/api/users/sessions returns sessions payload"
      else
        fail "/api/users/sessions did not return ok"
      fi

      user_detail=$(curl -s -b "$COOKIE_JAR" "$PANEL_URL/api/users/$USER_ID" 2>/dev/null || true)
      if echo "$user_detail" | grep -q "\"id\":\"$USER_ID\""; then
        pass "/api/users/:id returns real user"
      else
        fail "/api/users/:id failed for real user"
      fi

      users_list=$(curl -s -b "$COOKIE_JAR" "$PANEL_URL/api/users" 2>/dev/null || true)
      if echo "$users_list" | grep -q '"uniqueIpCount24h"'; then
        pass "/api/users includes uniqueIpCount24h"
      else
        fail "/api/users missing uniqueIpCount24h"
      fi

      ip_history=$(curl -s -b "$COOKIE_JAR" "$PANEL_URL/api/users/$USER_ID/ip-history" 2>/dev/null || true)
      if echo "$ip_history" | grep -q '"ok":true'; then
        pass "/api/users/:id/ip-history returns ok"
      else
        fail "/api/users/:id/ip-history did not return ok"
      fi

      reset_sessions=$(curl -s -b "$COOKIE_JAR" -X POST "$PANEL_URL/api/users/$USER_ID/reset-sessions" 2>/dev/null || true)
      ip_history_after_reset=$(curl -s -b "$COOKIE_JAR" "$PANEL_URL/api/users/$USER_ID/ip-history" 2>/dev/null || true)
      if echo "$reset_sessions" | grep -q '"ok":true' && echo "$ip_history_after_reset" | grep -q '"ok":true'; then
        pass "Reset IPs keeps /api/users/:id/ip-history healthy"
      else
        fail "Reset IPs broke /api/users/:id/ip-history"
      fi

#
      if grep -q '_placeholder_' "$CADDY_FILE" 2>/dev/null; then
        fail "Caddyfile: placeholder NOT removed after real user added (Bug 34)"
      else
        pass "Caddyfile: placeholder replaced by real user (Bug 34)"
      fi

#
      sleep 2
      if systemctl is-active --quiet mita; then
        pass "mita started after first user created"
      else
        log_warn "mita did not start after user creation (may be normal if no Mieru users)"
      fi

#
      ENC_PASS=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$TEST_PASS'))" 2>/dev/null || true)
      naive_cfg=$(curl -sf -b "$COOKIE_JAR" \
        "$PANEL_URL/api/users/$USER_ID/config/naive->password=${ENC_PASS}" \
        2>/dev/null) || naive_cfg=""
      if echo "$naive_cfg" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'link' in d" 2>/dev/null; then
        pass "NaiveProxy client config returned 'link' field"
        naive_link=$(echo "$naive_cfg" | python3 -c "import json,sys; print(json.load(sys.stdin)['link'])" 2>/dev/null || true)
        if echo "$naive_link" | grep -q "naive+https://"; then
          pass "NaiveProxy link uses HTTPS transport"
        else
          fail "NaiveProxy link missing 'naive+https://' prefix"
        fi
      else
        fail "NaiveProxy client config invalid"
      fi

#
      mieru_cfg=$(curl -sf -b "$COOKIE_JAR" \
        "$PANEL_URL/api/users/$USER_ID/config/mieru->password=${ENC_PASS}" \
        2>/dev/null) || mieru_cfg=""
      if echo "$mieru_cfg" | python3 -c "
import json,sys
d=json.load(sys.stdin)
ob=d.get('outbounds',[])
m=[o for o in ob if o.get('type')=='mieru']
assert m, 'no mieru outbound'
assert 'server_ports' in m[0] or 'server_port' in m[0], 'missing port field'
assert m[0].get('transport','TCP') in ('TCP','UDP'), 'bad transport'
" 2>/dev/null; then
        pass "Mieru sing-box config valid (transport + port fields)"
      else
        fail "Mieru sing-box config validation failed"
      fi

#
      curl -sf -b "$COOKIE_JAR" -X DELETE "$PANEL_URL/api/users/$USER_ID" >/dev/null 2>&1 || true
      log_info "Test user '$TEST_USER' cleaned up"
    else
      fail "User creation failed"
    fi
  else
    fail "Local UI API login failed"
  fi
fi

# STEP 6 update.sh --repair
log_step "Step 6: update.sh --repair"
if [[ -f "$REPO_ROOT/update.sh" ]]; then
  if bash "$REPO_ROOT/update.sh" --repair -y &>/dev/null; then
    pass "update.sh --repair exited 0"
#
    if [[ -x "$CADDY_BIN" ]]; then
      if "$CADDY_BIN" validate --config "$CADDY_FILE" --adapter caddyfile &>/dev/null; then
        pass "Caddyfile valid after --repair"
      else
        fail "Caddyfile invalid after --repair"
      fi
    fi
  else
    fail "update.sh --repair exited non-zero"
  fi
else
  skip "update.sh not found"
fi

# STEP 7 idempotent reinstall (--force)
log_step "Step 7: idempotent --force reinstall"
if $SKIP_INSTALL; then
  skip "Idempotent reinstall (--skip-install set)"
else
  if NODE_SECRET="$E2E_NODE_SECRET" \
      ALLOW_LOCAL_USER_MUTATIONS=true \
      bash "$REPO_ROOT/install.sh" \
      --non-interactive --force \
      --domain "$DOMAIN" \
      --email  "$EMAIL" \
      --naive-port "$NAIVE_PORT" \
      --lang en &>/dev/null; then
    pass "install.sh --force (idempotent reinstall) exited 0"
    if [[ -x "$CADDY_BIN" ]]; then
      if "$CADDY_BIN" validate --config "$CADDY_FILE" --adapter caddyfile &>/dev/null; then
        pass "Caddyfile valid after --force reinstall"
      else
        fail "Caddyfile invalid after --force reinstall"
      fi
    fi
  else
    fail "install.sh --force exited non-zero"
  fi
fi

# STEP 8 Uninstall + clean-state check
log_step "Step 8: Uninstall"
if $SKIP_UNINSTALL; then
  skip "Uninstall (--skip-uninstall)"
else
  if bash "$REPO_ROOT/uninstall.sh" --yes &>/dev/null; then
    pass "uninstall.sh exited 0"
  else
    fail "uninstall.sh exited non-zero"
  fi

#
  assert "caddy-naive binary removed"         "! [[ -f '/usr/local/bin/caddy-naive' ]]"
  assert "caddy-naive.service removed"        "! [[ -f '/etc/systemd/system/caddy-naive.service' ]]"
  assert "/etc/caddy-naive removed"           "! [[ -d '/etc/caddy-naive' ]]"
  assert "/var/www/fake-site removed"         "! [[ -d '/var/www/fake-site' ]]"
  assert "/opt/vetka-node-agent removed"     "! [[ -d '/opt/vetka-node-agent' ]]"
  assert "/etc/vetka-node-agent removed"           "! [[ -d '/etc/vetka-node-agent' ]]"
  assert "caddy-naive.service inactive"       "! systemctl is-active caddy-naive"
  assert "Node Agent PM2 process stopped"          "! pm2 list 2>/dev/null | grep -q vetka-node-agent"
fi

# STEP 9 Version consistency check (without install)
log_step "Step 9: Version consistency across all files"
VERSION_EXPECTED="1.2.6"
check_version_in() {
  local label="$1" file="$2" pattern="$3"
  if [[ -f "$file" ]] && grep -qP "$pattern" "$file" 2>/dev/null; then
    pass "Version $VERSION_EXPECTED in $label"
  else
    fail "Version $VERSION_EXPECTED NOT found in $label"
  fi
}
check_version_in "install.sh"            "$REPO_ROOT/install.sh"                   "1\\.2\\.6"
check_version_in "update.sh"             "$REPO_ROOT/update.sh"                    "TARGET_VERSION=\"1\\.2\\.6\""
check_version_in "panel/server/index.js" "$REPO_ROOT/panel/server/index.js"        "v1\\.2\\.6"
check_version_in "panel/public/index.html" "$REPO_ROOT/panel/public/index.html"    "v1\\.2\\.6"
check_version_in "panel/public/app.js"   "$REPO_ROOT/panel/public/app.js"          "v1\\.2\\.6"
check_version_in "panel/package.json"    "$REPO_ROOT/panel/package.json"           "\"version\": \"1\\.2\\.6\""
check_version_in "CHANGELOG.md"          "$REPO_ROOT/CHANGELOG.md"                 "\[v1\\.2\\.6\]"
check_version_in "caddyTemplate.js"      "$REPO_ROOT/panel/server/caddyTemplate.js" "v1\\.2\\.6"
check_version_in "uninstall.sh"          "$REPO_ROOT/uninstall.sh"                  "v1\\.2\\.6"

# Regression checks for post-release audit bugs 65-70
log_step "Step 9b: Post-release audit regression checks (Bugs 65-70)"

# Bug 65: ProtectSystem=strict (not full) in both install.sh and update.sh
assert "Bug65: install.sh has ProtectSystem=strict" \
  "grep -q 'ProtectSystem=strict' '$REPO_ROOT/install.sh'"
assert "Bug65: install.sh has NO ProtectSystem=full" \
  "! grep -q '^ProtectSystem=full' '$REPO_ROOT/install.sh'"
assert "Bug65: update.sh ensure_caddy_service has ProtectSystem=strict" \
  "grep -q 'ProtectSystem=strict' '$REPO_ROOT/update.sh'"

# Bug 66: rebuild_caddyfile_direct() does chown after mkdir
assert "Bug66: update.sh rebuild chown /var/log/caddy-naive" \
  "grep -q 'chown caddy:caddy.*var/log/caddy-naive' '$REPO_ROOT/update.sh'"
assert "Bug66: update.sh rebuild creates /var/lib/caddy" \
  "grep -q '/var/lib/caddy' '$REPO_ROOT/update.sh'"

# Bug 67: empty-password filter in rebuild_caddyfile_direct()
assert "Bug67: update.sh rebuild filters empty passwords" \
  "grep -q \"password.trim.*!==.*''\" '$REPO_ROOT/update.sh'"

# Bug 68: correct log-block closing braces in fallback
assert "Bug68: update.sh fallback has '  }' before global-close brace" \
  "grep -q \"'  }',.*// closes log\" '$REPO_ROOT/update.sh'"

# Bug 69: parseInt in rebuild_mita_state_direct
assert "Bug69: update.sh mita-state rebuild has parseInt portStart" \
  "grep -A5 'portStart.*parseInt.*mieruPortStart' '$REPO_ROOT/update.sh' | grep -q 'mieruPortEnd'"

# Bug 70: parseInt in index.js config/mieru and config/universal
assert "Bug70: index.js config/mieru has parseInt portStart" \
  "grep -q '_portStart70a.*parseInt.*mieruPortStart' '$REPO_ROOT/panel/server/index.js'"
assert "Bug70: index.js config/universal has parseInt portStart" \
  "grep -q '_portStart70b.*parseInt.*mieruPortStart' '$REPO_ROOT/panel/server/index.js'"

# ARM error messages
assert "ARM error: install.sh references v1.2.6 (not older)" \
  "! grep -q 'not supported in v1.2.[45]' '$REPO_ROOT/install.sh'"

# uninstall.sh removes /var/lib/caddy
assert "uninstall.sh removes /var/lib/caddy" \
  "grep -q 'rm -rf /var/lib/caddy' '$REPO_ROOT/uninstall.sh'"

# Bug 73 (P0): write_config_json must pass the admin password via env var and
# read it from process.env (NOT process.argv[2], which is undefined for node -e).
assert "Bug73: install.sh bcrypt uses VETKA_ADMIN_PASS env (not argv[2])" \
  "grep -q 'VETKA_ADMIN_PASS' '$REPO_ROOT/install.sh' && ! grep -q 'hashSync(process.argv\\[2\\]' '$REPO_ROOT/install.sh'"
assert "Bug73: install.sh reads pw from process.env.VETKA_ADMIN_PASS" \
  "grep -q 'process.env.VETKA_ADMIN_PASS' '$REPO_ROOT/install.sh'"
assert "Bug73: install.sh htpasswd fallback installs apache2-utils" \
  "grep -q 'apache2-utils' '$REPO_ROOT/install.sh'"
assert "install.sh install_panel falls back to PWD/panel" \
  "grep -q 'PWD/panel' '$REPO_ROOT/install.sh'"

# Cascade Variant B (static) checks
log_step "Step 9c: Cascade Variant B (redsocks + iptables + mieru-client)"

CASC="$REPO_ROOT/panel/scripts/cascade_mieru.sh"
assert "cascade_mieru.sh exists"             "[[ -f '$CASC' ]]"
assert "cascade_mieru.sh is executable"      "[[ -x '$CASC' ]]"
assert "cascade_mieru.sh passes bash -n"     "bash -n '$CASC'"
assert "cascade_mieru.sh has setup/teardown/status" \
  "grep -q 'do_setup'  '$CASC' && grep -q 'do_teardown' '$CASC' && grep -q 'do_status' '$CASC'"
assert "cascade uses 'profiles' (plural, not bare 'profile')" \
  "grep -q '\"profiles\"' '$CASC'"
assert "cascade client config has NO mtu JSON key" \
  "! grep -qE '\"mtu\"[[:space:]]*:' '$CASC'"
assert "cascade mieru.service uses Type=forking" \
  "grep -q 'Type=forking' '$CASC'"
assert "cascade restarts redsocks via ExecStartPost" \
  "grep -q 'ExecStartPost=/bin/systemctl restart redsocks' '$CASC'"
assert "cascade has anti-loop RETURN for exit IP" \
  "grep -q 'exit_ip.*-j RETURN' '$CASC'"
assert "cascade iptables owner-match mita uid" \
  "grep -q 'uid-owner' '$CASC'"
assert "cascade watchdog uses 3 consecutive failures" \
  "grep -q 'FAILS.*-eq 3' '$CASC'"
assert "cascade lazy-installs redsocks" \
  "grep -q 'ensure_packages' '$CASC'"

# Server wiring
assert "index.js invokes cascade_mieru.sh" \
  "grep -q 'cascade_mieru.sh' '$REPO_ROOT/panel/server/index.js'"
assert "index.js has runCascadeMieru (execFileSync, no shell)" \
  "grep -q 'function runCascadeMieru' '$REPO_ROOT/panel/server/index.js' && grep -q 'execFileSync' '$REPO_ROOT/panel/server/index.js'"
assert "index.js exposes cascade status endpoint" \
  "grep -q \"/api/settings/cascade/status\" '$REPO_ROOT/panel/server/index.js'"
assert "index.js masks cascade exit password in /api/config" \
  "grep -q 'cascadeMieru' '$REPO_ROOT/panel/server/index.js'"
assert "default cfg has cascadeMieru object" \
  "grep -q 'cascadeMieru:' '$REPO_ROOT/panel/server/index.js'"

# Install / Uninstall wiring
assert "install.sh defines tune_network wrapper and calls sysctl_tune.sh" \
  "grep -q '^tune_network()' '$REPO_ROOT/install.sh' && grep -q 'panel/scripts/sysctl_tune.sh' '$REPO_ROOT/install.sh'"
assert "install.sh static-site opt-out skips source prompt branch" \
  "grep -q 'if \\[\\[ ! \"\\\${INPUT_STATIC_SITE_ENABLE:-Y}\" =~' '$REPO_ROOT/install.sh' && grep -q 'STATIC_SITE_DEPLOY_ON_INSTALL=false' '$REPO_ROOT/install.sh'"
assert "no broken ternary operators remain in shell/runtime sources" \
  "python3 - '$REPO_ROOT' <<'PY'\nfrom pathlib import Path\nimport sys\nroot = Path(sys.argv[1])\narrow = chr(45) + chr(62)\npatterns = ['probeSecret ' + arrow, arrow + ' ' + chr(39) + 'secret' + chr(39) + ' :']\npaths = [root / 'update.sh', root / 'install.sh', root / 'panel', root / 'tests']\nfor base in paths:\n    files = [base] if base.is_file() else [p for p in base.rglob('*') if p.is_file()]\n    for p in files:\n        text = p.read_text(encoding='utf-8', errors='ignore')\n        if any(pattern in text for pattern in patterns):\n            raise SystemExit(1)\nraise SystemExit(0)\nPY"
assert "Mieru runtime apply writes full state and restarts mita directly" \
  "grep -q 'function restartMieruAfterConfigApply' '$REPO_ROOT/panel/server/index.js' && grep -q \"systemctl', \\['restart', 'mita'\\]\" '$REPO_ROOT/panel/server/index.js' && ! grep -q 'mita apply config' '$REPO_ROOT/panel/server/index.js'"
assert "Mieru runtime apply supports idle no-user state" \
  "grep -q 'function stopMieruWhenNoUsers' '$REPO_ROOT/panel/server/index.js' && grep -q 'service will stay idle until users are applied via /v1/sync' '$REPO_ROOT/panel/server/index.js'"
assert "Mieru installer/update permissions stay read-write for mita state" \
  "grep -q 'chmod 660' '$REPO_ROOT/install.sh' && grep -q 'chmod 660' '$REPO_ROOT/update.sh' && ! grep -q 'chmod 640.*MITA_STATE_FILE' '$REPO_ROOT/install.sh' && ! grep -q 'chmod 640.*MITA_STATE_FILE' '$REPO_ROOT/update.sh'"
assert "install_mieru helper keeps mita-state.json writable for mita" \
  "grep -q 'chmod 660' '$REPO_ROOT/panel/scripts/install_mieru.sh' && ! grep -q 'chmod 640.*MITA_STATE_FILE' '$REPO_ROOT/panel/scripts/install_mieru.sh'"
assert "install_mieru helper has idle no-users path" \
  "grep -q 'service will stay idle until users are applied via /v1/sync' '$REPO_ROOT/panel/scripts/install_mieru.sh' && grep -q 'systemctl stop mita' '$REPO_ROOT/panel/scripts/install_mieru.sh'"
assert "uninstall.sh removes iptables REDSOCKS chain" \
  "grep -q 'iptables -t nat -X REDSOCKS' '$REPO_ROOT/uninstall.sh'"
assert "uninstall.sh removes mieru.service" \
  "grep -q '/etc/systemd/system/mieru.service' '$REPO_ROOT/uninstall.sh'"
assert "uninstall.sh removes redsocks.conf" \
  "grep -q '/etc/redsocks.conf' '$REPO_ROOT/uninstall.sh'"
assert "uninstall.sh removes watchdog cron" \
  "grep -q 'mieru-cascade-watchdog' '$REPO_ROOT/uninstall.sh'"

# UI wiring
assert "index.html has exit port-range inputs" \
  "grep -q 's-cascade-mieru-port-start' '$REPO_ROOT/panel/public/index.html' && grep -q 's-cascade-mieru-port-end' '$REPO_ROOT/panel/public/index.html'"
assert "app.js posts cascadeMieru (host/portStart/portEnd/user/pass)" \
  "grep -q 'cascadeMieru' '$REPO_ROOT/panel/public/app.js' && grep -q 'portStart' '$REPO_ROOT/panel/public/app.js'"

# Summary
echo ""
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  E2E Results${NC}"
echo -e "${BOLD}========================================${NC}"
echo -e "  ${GREEN}  Passed:${NC}   $pass_count"
echo -e "  ${RED}  Failed:${NC}   $fail_count"
echo -e "  ${YELLOW}  Warnings:${NC} $warn_count"
echo ""

if [[ "$fail_count" -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}ALL TESTS PASSED${NC}"
  exit 0
else
  echo -e "  ${RED}${BOLD}$fail_count TEST(S) FAILED${NC}"
  exit 1
fi
