#!/usr/bin/env bash
# ==============================================================================
# Vetka Node Agent РІР‚вЂќ uninstall.sh  v1.2.6
# Removes all panel components, services, configs, and data.
#
# v1.2.3: Full cleanup for caddy-forwardproxy-naive migration.
# v1.2.5: Also removes /var/lib/caddy (ACME cert storage, Bug 43).
# v1.2.6: Cascade/relay cleanup (mieru-client, redsocks, iptables, watchdog).
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_step()  { echo -e "\n${CYAN}${BOLD}РІвЂ“В¶ $*${NC}"; }
die()       { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

[[ $EUID -ne 0 ]] && die "Run as root (sudo bash uninstall.sh)"

echo -e "\n${RED}${BOLD}РІвЂўвЂќРІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўвЂ”${NC}"
echo -e "${RED}${BOLD}РІвЂўвЂ   Vetka Node Agent РІР‚вЂќ UNINSTALL  v1.2.6                РІвЂўвЂ${NC}"
echo -e "${RED}${BOLD}РІвЂўС™РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўСњ${NC}\n"

echo -e "${YELLOW}${BOLD}WARNING:${NC} This will permanently remove ALL panel data, users,"
echo -e "         configurations, binaries, and log files."
echo ""
read -rp "Type 'yes' to confirm uninstall: " CONFIRM
[[ "$CONFIRM" != "yes" ]] && { log_info "Aborted."; exit 0; }

# РІвЂќР‚РІвЂќР‚ Stop and disable services РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚
log_step "Stopping and disabling services"

# PM2 panel process
pm2 stop   vetka-node-agent 2>/dev/null || true
pm2 delete vetka-node-agent 2>/dev/null || true
pm2 save   2>/dev/null || true
log_info "PM2 panel process removed РІСљвЂњ"

# v1.2.3 primary: caddy-naive.service
if systemctl is-active caddy-naive &>/dev/null 2>&1 || \
   systemctl is-enabled caddy-naive &>/dev/null 2>&1; then
  systemctl stop    caddy-naive 2>/dev/null || true
  systemctl disable caddy-naive 2>/dev/null || true
  log_info "caddy-naive.service stopped and disabled РІСљвЂњ"
fi

# Legacy v1.2.x: naive.service
if systemctl is-active naive &>/dev/null 2>&1 || \
   systemctl is-enabled naive &>/dev/null 2>&1; then
  systemctl stop    naive 2>/dev/null || true
  systemctl disable naive 2>/dev/null || true
  log_info "naive.service (legacy) stopped and disabled РІСљвЂњ"
fi

# mita: stop but keep mita package installed (user choice below)
systemctl stop mita 2>/dev/null || true
log_info "mita stopped РІСљвЂњ"

# РІвЂќР‚РІвЂќР‚ v1.2.6: Cascade (Variant B) cleanup РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚
# Mirror `cascade_mieru.sh teardown` so an uninstall leaves no relay artifacts:
# mieru-client service, redsocks, iptables REDSOCKS chain, watchdog, cron, drop-in.
log_step "Removing cascade (relay) artifacts"

# 1) iptables REDSOCKS chain + OUTPUT owner-match jump (mita uid).
MITA_UID="$(id -u mita 2>/dev/null || true)"
if [[ -n "$MITA_UID" ]]; then
  while iptables -t nat -C OUTPUT -p tcp -m owner --uid-owner "$MITA_UID" -j REDSOCKS 2>/dev/null; do
    iptables -t nat -D OUTPUT -p tcp -m owner --uid-owner "$MITA_UID" -j REDSOCKS 2>/dev/null || break
  done
fi
iptables -t nat -F REDSOCKS 2>/dev/null || true
iptables -t nat -X REDSOCKS 2>/dev/null || true
command -v netfilter-persistent &>/dev/null && netfilter-persistent save 2>/dev/null || true

# 2) mieru-client relay service.
systemctl stop    mieru 2>/dev/null || true
systemctl disable mieru 2>/dev/null || true
rm -f /etc/systemd/system/mieru.service

# 3) redsocks service + drop-in.
systemctl stop    redsocks 2>/dev/null || true
systemctl disable redsocks 2>/dev/null || true
rm -f /etc/systemd/system/redsocks.service.d/cascade.conf
rmdir /etc/systemd/system/redsocks.service.d 2>/dev/null || true
rm -f /etc/redsocks.conf

# 4) Watchdog + cron.
rm -f /usr/local/bin/mieru-watchdog.sh
rm -f /etc/cron.d/mieru-cascade-watchdog

# 5) Cascade state + client config (contains exit credentials РІвЂ вЂ™ shred).
[[ -f /var/lib/vetka-node-agent/mieru-client-config.json ]] && \
  { shred -u /var/lib/vetka-node-agent/mieru-client-config.json 2>/dev/null || \
    rm -f /var/lib/vetka-node-agent/mieru-client-config.json; }
rm -f /var/lib/vetka-node-agent/cascade-mieru.state

systemctl daemon-reload
log_info "Cascade artifacts removed РІСљвЂњ"

# РІвЂќР‚РІвЂќР‚ Remove systemd unit files РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚
log_step "Removing systemd unit files"
rm -f /etc/systemd/system/caddy-naive.service   # v1.2.3
rm -f /etc/systemd/system/naive.service         # v1.2.x legacy
# Note: mita.service is managed by its .deb package РІР‚вЂќ not removed here
systemctl daemon-reload
log_info "Systemd units removed РІСљвЂњ"

# РІвЂќР‚РІвЂќР‚ Remove binaries РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚
log_step "Removing binaries"
# v1.2.3: caddy-forwardproxy-naive binary
if [[ -f /usr/local/bin/caddy-naive ]]; then
  rm -f /usr/local/bin/caddy-naive
  log_info "/usr/local/bin/caddy-naive removed РІСљвЂњ"
fi
# v1.2.x legacy: standalone naive binary
if [[ -f /usr/local/bin/naive ]]; then
  rm -f /usr/local/bin/naive
  log_info "/usr/local/bin/naive (legacy) removed РІСљвЂњ"
fi
log_info "Binaries removed РІСљвЂњ"

# РІвЂќР‚РІвЂќР‚ Remove configuration directories РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚
log_step "Removing configuration directories"
# v1.2.3: Caddy config dir (Caddyfile, probe_secret, version)
if [[ -d /etc/caddy-naive ]]; then
  rm -rf /etc/caddy-naive
  log_info "/etc/caddy-naive removed РІСљвЂњ"
fi
# v1.2.x legacy: naive config dir (config.json, htpasswd)
if [[ -d /etc/naive ]]; then
  rm -rf /etc/naive
  log_info "/etc/naive (legacy) removed РІСљвЂњ"
fi
# Panel config
rm -rf /etc/vetka-node-agent
log_info "/etc/vetka-node-agent removed РІСљвЂњ"
log_info "Configuration directories removed РІСљвЂњ"

# Legacy fake site / managed static site
echo ""
read -rp "Remove managed static site files? [y/N]: " REMOVE_STATIC_SITE
if [[ "${REMOVE_STATIC_SITE^^}" == "Y" ]]; then
  log_step "Removing legacy fake site / managed static site"
  if [[ -d /var/www/fake-site ]]; then
    rm -rf /var/www/fake-site
    log_info "/var/www/fake-site removed"
  else
    log_info "Legacy fake site / managed static site directory not found (skipped)"
  fi
else
  log_info "Legacy fake site / managed static site preserved"
fi

# РІвЂќР‚РІвЂќР‚ Remove panel directory РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚
log_step "Removing panel files"
if [[ -d /opt/vetka-node-agent ]]; then
  rm -rf /opt/vetka-node-agent
  log_info "/opt/vetka-node-agent removed РІСљвЂњ"
fi
log_info "Panel files removed РІСљвЂњ"

# РІвЂќР‚РІвЂќР‚ Remove database and runtime data РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚
log_step "Removing database and runtime data"
if [[ -f /var/lib/vetka-node-agent/cache.sqlite ]]; then
  shred -u /var/lib/vetka-node-agent/cache.sqlite 2>/dev/null || \
    rm -f /var/lib/vetka-node-agent/cache.sqlite
  log_info "SQLite database securely removed РІСљвЂњ"
fi
rm -rf /var/lib/vetka-node-agent
# Bug 43 / v1.2.5: /var/lib/caddy stores ACME TLS certificates РІР‚вЂќ remove on uninstall
rm -rf /var/lib/caddy 2>/dev/null || true
log_info "Runtime data removed РІСљвЂњ"

# РІвЂќР‚РІвЂќР‚ Remove logs РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚
log_step "Removing logs"
rm -rf /var/log/caddy-naive                    # v1.2.3 caddy access logs
rm -rf /var/log/naive                          # v1.2.x legacy naive logs
rm -f  /var/log/vetka-node-agent.log          # PM2 panel log
rm -f  /var/log/vetka-node-agent-install.log        # install log
log_info "Logs removed РІСљвЂњ"

# РІвЂќР‚РІвЂќР‚ Remove Certbot renewal hook (v1.2.x legacy) РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚
if [[ -f /etc/letsencrypt/renewal-hooks/deploy/restart-naive.sh ]]; then
  rm -f /etc/letsencrypt/renewal-hooks/deploy/restart-naive.sh
  log_info "Certbot renewal hook removed РІСљвЂњ"
fi

# РІвЂќР‚РІвЂќР‚ Remove sysctl tuning РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚
if [[ -f /etc/sysctl.d/99-vetka-node-agent.conf ]]; then
  rm -f /etc/sysctl.d/99-vetka-node-agent.conf
  sysctl -p /etc/sysctl.conf 2>/dev/null || true
  log_info "Sysctl tuning removed РІСљвЂњ"
fi

# РІвЂќР‚РІвЂќР‚ UFW cleanup (optional) РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚
echo ""
read -rp "Remove UFW rules added by the panel? [y/N]: " UFW_CLEAN
if [[ "${UFW_CLEAN^^}" == "Y" ]]; then
  log_step "Cleaning UFW rules"
  # v1.2.3 rules
  ufw delete allow comment "CaddyNaive HTTPS"  2>/dev/null || true
  # v1.2.x legacy rules
  ufw delete allow comment "NaiveProxy HTTPS"  2>/dev/null || true
  # Common rules
  ufw delete allow comment "Mieru TCP"         2>/dev/null || true
  ufw delete allow comment "Mieru UDP"         2>/dev/null || true
  ufw delete allow comment "Panel Web UI"      2>/dev/null || true
  ufw delete allow comment "Certbot HTTP-01"   2>/dev/null || true
  ufw delete allow 8080/tcp                    2>/dev/null || true
  log_info "UFW rules cleaned РІСљвЂњ"
fi

# РІвЂќР‚РІвЂќР‚ Optional: remove mita package РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚
echo ""
read -rp "Also remove the mita (Mieru) package via apt? [y/N]: " REMOVE_MITA
if [[ "${REMOVE_MITA^^}" == "Y" ]]; then
  log_step "Removing mita package"
  apt-get remove -y mita 2>/dev/null || true
  apt-get autoremove -y  2>/dev/null || true
  rm -rf /etc/mita       2>/dev/null || true
  log_info "mita package removed РІСљвЂњ"
fi

# РІвЂќР‚РІвЂќР‚ Optional: remove redsocks package (lazy-installed for cascade Variant B) РІвЂќР‚РІвЂќР‚
if dpkg -l redsocks 2>/dev/null | grep -q '^ii'; then
  echo ""
  read -rp "Also remove the redsocks package (used by cascade relay)? [y/N]: " REMOVE_REDSOCKS
  if [[ "${REMOVE_REDSOCKS^^}" == "Y" ]]; then
    log_step "Removing redsocks package"
    apt-get remove -y redsocks 2>/dev/null || true
    apt-get autoremove -y      2>/dev/null || true
    log_info "redsocks package removed РІСљвЂњ"
  fi
fi

# РІвЂќР‚РІвЂќР‚ Final summary РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚РІвЂќР‚
echo ""
echo -e "${GREEN}${BOLD}РІвЂўвЂќРІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўвЂ”${NC}"
echo -e "${GREEN}${BOLD}РІвЂўвЂ   Uninstall complete РІСљвЂњ                                    РІвЂўвЂ${NC}"
echo -e "${GREEN}${BOLD}РІвЂўС™РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўС’РІвЂўСњ${NC}"
echo ""
echo -e "  ${BOLD}Removed:${NC}"
echo -e "    РІР‚Сћ caddy-naive binary + service + Caddyfile"
echo -e "    РІР‚Сћ Legacy naive binary + service (v1.2.x)"
echo -e "    РІР‚Сћ Node Agent files (/opt/vetka-node-agent)"
echo -e "    РІР‚Сћ Configuration (/etc/vetka-node-agent, /etc/caddy-naive)"
[[ "${REMOVE_STATIC_SITE^^}" == "Y" ]] && echo -e "    вЂў Legacy fake site / managed static site (/var/www/fake-site)"
echo -e "    РІР‚Сћ Database (/var/lib/vetka-node-agent/cache.sqlite)"
echo -e "    РІР‚Сћ Cascade relay (mieru-client svc, redsocks.conf, iptables REDSOCKS, watchdog/cron)"
echo -e "    РІР‚Сћ Logs (/var/log/caddy-naive, /var/log/vetka-node-agent.log)"
echo ""
echo -e "  ${BOLD}Still installed:${NC}"
if [[ "${REMOVE_MITA^^}" != "Y" ]]; then
  echo -e "    вЂў Mieru (mita) вЂ” remove with: ${CYAN}apt remove mita${NC}"
fi
echo -e "    РІР‚Сћ Node.js and PM2 РІР‚вЂќ remove with: ${CYAN}npm uninstall -g pm2 && apt remove nodejs${NC}"
echo -e "    РІР‚Сћ Let's Encrypt certificates РІР‚вЂќ preserved at /etc/letsencrypt/ (if any)"
echo ""
