#!/usr/bin/env bash
# Install / update Mieru (mita) from GitHub releases via .deb package
# Usage: bash install_mieru.sh [--update]
set -euo pipefail

MIERU_RELEASES="https://api.github.com/repos/enfein/mieru/releases/latest"
MITA_STATE_FILE="${MITA_STATE_FILE:-/var/lib/vetka-node-agent/mita-state.json}"

ensure_mita_state_permissions() {
  local dir
  dir="$(dirname "$MITA_STATE_FILE")"
  mkdir -p "$dir"

  local out
  if ! getent passwd mita >/dev/null 2>&1 || ! getent group mita >/dev/null 2>&1; then
    echo "[WARN] mita user/group does not exist yet; cannot set mita-state.json permissions"
    return 0
  fi
  if ! out=$(chown root:mita "$dir" 2>&1); then
    echo "[WARN] Failed to set owner root:mita on $dir: $out"
    return 0
  fi
  if ! out=$(chmod 770 "$dir" 2>&1); then
    echo "[WARN] Failed to set mode 770 on $dir: $out"
    return 0
  fi
  if [[ -f "$MITA_STATE_FILE" ]]; then
    if ! out=$(chown root:mita "$MITA_STATE_FILE" 2>&1); then
      echo "[WARN] Failed to set owner root:mita on $MITA_STATE_FILE: $out"
      return 0
    fi
    if ! out=$(chmod 660 "$MITA_STATE_FILE" 2>&1); then
      echo "[WARN] Failed to set mode 660 on $MITA_STATE_FILE: $out"
      return 0
    fi
    if command -v setfacl >/dev/null 2>&1; then
      setfacl -m u:mita:rwx,m:rwx "$dir" 2>/dev/null || true
      setfacl -d -m u:mita:rwx,m:rwx "$dir" 2>/dev/null || true
      setfacl -m u:mita:rw,m:rw "$MITA_STATE_FILE" 2>/dev/null || true
    fi
  fi
}

get_mita_user_count() {
  if [[ ! -f "$MITA_STATE_FILE" ]]; then
    echo 0
    return 0
  fi
  if command -v jq >/dev/null 2>&1; then
    jq -r '(.users // []) | length' "$MITA_STATE_FILE" 2>/dev/null || echo 0
    return 0
  fi
  echo 0
}

restart_mita_after_config_apply() {
  local restart_out
  if restart_out=$(systemctl restart mita 2>&1); then
    [[ -n "$restart_out" ]] && echo "[mieru] systemctl restart output: $restart_out"
    return 0
  fi
  echo "[WARN] systemctl restart mita failed: $restart_out"
  return 1
}

stop_mita_when_no_users() {
  systemctl stop mita 2>/dev/null || true
  systemctl reset-failed mita 2>/dev/null || true
  echo "[mieru] mita has no users; service will stay idle until users are applied via /v1/sync"
}

case "$(uname -m)" in
  x86_64|amd64)  DEB_ARCH="amd64"  ;;
  aarch64|arm64) DEB_ARCH="arm64"  ;;
  armv7l)        DEB_ARCH="armhf"  ;;
  *) echo "[ERROR] Unsupported arch: $(uname -m)"; exit 1 ;;
esac

echo "[mieru] Fetching latest release info..."
release_json=$(curl -fsSL "$MIERU_RELEASES")
tag=$(echo "$release_json" | jq -r '.tag_name')
echo "[mieru] Latest: $tag"

asset_url=$(echo "$release_json" | jq -r \
  --arg arch "$DEB_ARCH" \
  '.assets[] | select(.name | test("mita.*" + $arch + "\\.deb")) | .browser_download_url' \
  | head -1)

if [[ -z "$asset_url" ]]; then
  asset_url=$(echo "$release_json" | jq -r \
    --arg arch "$DEB_ARCH" \
    '.assets[] | select(.name | test($arch + "\\.deb")) | .browser_download_url' \
    | head -1)
fi

[[ -z "$asset_url" ]] && { echo "[ERROR] No .deb found for $DEB_ARCH"; exit 1; }

deb_file=$(mktemp /tmp/mieru-XXXXXX.deb)
echo "[mieru] Downloading $asset_url"
wget -q --show-progress -O "$deb_file" "$asset_url"

echo "[mieru] Installing .deb package..."
dpkg -i "$deb_file" 2>/dev/null || apt-get install -f -y
rm -f "$deb_file"
ensure_mita_state_permissions

# Enable and reconcile mita service
systemctl daemon-reload
systemctl enable mita 2>/dev/null || true
if [[ "$(get_mita_user_count)" -gt 0 ]]; then
  restart_mita_after_config_apply || true
else
  stop_mita_when_no_users
fi

echo "[mieru] Installed: $(mita version 2>/dev/null | head -1 || echo $tag)"
