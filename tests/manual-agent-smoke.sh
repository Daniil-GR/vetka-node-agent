#!/usr/bin/env bash
set -Eeuo pipefail

NODE_AGENT_URL="${NODE_AGENT_URL:-http://127.0.0.1:2222}"
NODE_ID="${NODE_ID:-alps-naive-1}"
NODE_SECRET="${NODE_SECRET:-}"
PROTOCOL_TYPE="${PROTOCOL_TYPE:-naive}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass_count=0
fail_count=0

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required"
}

pass() {
  pass_count=$((pass_count + 1))
  echo "OK: $*"
}

check_jq_bool() {
  local file="$1"
  shift
  jq -e "$@" "$file" >/dev/null
}

request() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local output="$4"
  local code_file="$5"
  local tmp_code
  tmp_code="$(mktemp)"
  if [[ -n "$body" ]]; then
    curl -sS -X "$method" \
      -H "Authorization: Bearer ${NODE_SECRET}" \
      -H "X-Node-Id: ${NODE_ID}" \
      -H "Content-Type: application/json" \
      --data-binary "@${body}" \
      -o "$output" \
      -w "%{http_code}" \
      "${NODE_AGENT_URL}${path}" >"$tmp_code"
  else
    curl -sS -X "$method" \
      -H "Authorization: Bearer ${NODE_SECRET}" \
      -H "X-Node-Id: ${NODE_ID}" \
      -o "$output" \
      -w "%{http_code}" \
      "${NODE_AGENT_URL}${path}" >"$tmp_code"
  fi
  cat "$tmp_code" >"$code_file"
  rm -f "$tmp_code"
}

make_payload() {
  local source="$1"
  local target="$2"
  local version="$3"
  jq \
    --arg node_id "$NODE_ID" \
    --arg protocol_type "$PROTOCOL_TYPE" \
    --argjson config_version "$version" \
    '.node_id = $node_id | .protocol_type = $protocol_type | .config_version = $config_version' \
    "$source" >"$target"
}

require_cmd curl
require_cmd jq

[[ -n "$NODE_SECRET" ]] || fail "NODE_SECRET is required"
case "$PROTOCOL_TYPE" in
  naive|mieru) ;;
  *) fail "PROTOCOL_TYPE must be naive or mieru" ;;
esac

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

unauth_body="$tmp_dir/health-unauth.json"
unauth_code="$tmp_dir/health-unauth.code"
curl -sS -o "$unauth_body" -w "%{http_code}" "${NODE_AGENT_URL}/health" >"$unauth_code" || true
case "$(cat "$unauth_code")" in
  401|403) pass "GET /health without token is rejected" ;;
  *) fail "GET /health without token returned HTTP $(cat "$unauth_code"), expected 401/403" ;;
esac

body="$tmp_dir/health.json"
code="$tmp_dir/health.code"
request GET /health "" "$body" "$code"
[[ "$(cat "$code")" == "200" ]] || fail "GET /health returned HTTP $(cat "$code")"
check_jq_bool "$body" '.ok == true' || fail "GET /health did not return ok=true"
pass "GET /health with Bearer returns ok=true"

body="$tmp_dir/status.json"
code="$tmp_dir/status.code"
request GET /status "" "$body" "$code"
[[ "$(cat "$code")" == "200" ]] || fail "GET /status returned HTTP $(cat "$code")"
check_jq_bool "$body" --arg node_id "$NODE_ID" --arg protocol_type "$PROTOCOL_TYPE" \
  '.node_id == $node_id and .protocol_type == $protocol_type and (.current_version | type == "number")' \
  || fail "GET /status did not return node_id/protocol_type/current version"
CURRENT_VERSION="$(jq -r '.current_version // .applied_version // 0' "$body")"
[[ "$CURRENT_VERSION" =~ ^[0-9]+$ ]] || fail "GET /status returned invalid current_version"
NEXT_VERSION=$((CURRENT_VERSION + 1))
STALE_VERSION=$((NEXT_VERSION - 1))
pass "GET /status returns node identity and current version"

case "$PROTOCOL_TYPE" in
  naive) base_payload="$ROOT_DIR/examples/sync-naive-v1.json" ;;
  mieru) base_payload="$ROOT_DIR/examples/sync-mieru-v1.json" ;;
esac

payload_v1="$tmp_dir/sync-v1.json"
payload_repeat="$tmp_dir/sync-v1-repeat.json"
payload_stale="$tmp_dir/sync-stale.json"
make_payload "$base_payload" "$payload_v1" "$NEXT_VERSION"
make_payload "$base_payload" "$payload_repeat" "$NEXT_VERSION"
make_payload "$base_payload" "$payload_stale" "$STALE_VERSION"

body="$tmp_dir/sync-v1-response.json"
code="$tmp_dir/sync-v1.code"
request POST /v1/sync "$payload_v1" "$body" "$code"
[[ "$(cat "$code")" == "200" ]] || fail "POST /v1/sync v1 returned HTTP $(cat "$code"): $(jq -c . "$body" 2>/dev/null || cat "$body")"
check_jq_bool "$body" --argjson next_version "$NEXT_VERSION" \
  '.ok == true and .changed == true and .applied_version == $next_version' \
  || fail "POST /v1/sync did not apply config_version=${NEXT_VERSION}"
pass "POST /v1/sync config_version=${NEXT_VERSION} applied"

body="$tmp_dir/sync-repeat-response.json"
code="$tmp_dir/sync-repeat.code"
request POST /v1/sync "$payload_repeat" "$body" "$code"
[[ "$(cat "$code")" == "200" ]] || fail "POST /v1/sync repeat returned HTTP $(cat "$code")"
check_jq_bool "$body" '.ok == true and (.changed == false or (.message // "" | test("already up to date"; "i")))' \
  || fail "POST /v1/sync repeat was not reported as no-op"
pass "POST /v1/sync same config is no-op"

body="$tmp_dir/sync-stale-response.json"
code="$tmp_dir/sync-stale.code"
request POST /v1/sync "$payload_stale" "$body" "$code"
[[ "$(cat "$code")" == "409" ]] || fail "POST /v1/sync stale returned HTTP $(cat "$code"), expected 409"
check_jq_bool "$body" '.ok == false and .status == "stale_version"' \
  || fail "POST /v1/sync stale did not return stale_version"
pass "POST /v1/sync stale config_version=${STALE_VERSION} is rejected"

body="$tmp_dir/stats.json"
code="$tmp_dir/stats.code"
request GET /v1/stats "" "$body" "$code"
[[ "$(cat "$code")" == "200" ]] || fail "GET /v1/stats returned HTTP $(cat "$code")"
check_jq_bool "$body" '.ok == true' || fail "GET /v1/stats did not return ok=true"
pass "GET /v1/stats returns ok=true"

body="$tmp_dir/telemetry.json"
code="$tmp_dir/telemetry.code"
request GET "/v1/telemetry/sessions" "" "$body" "$code"
[[ "$(cat "$code")" == "200" ]] || fail "GET /v1/telemetry/sessions returned HTTP $(cat "$code")"
check_jq_bool "$body" --arg protocol_type "$PROTOCOL_TYPE" '
  .ok == true
  and .protocol_type == $protocol_type
  and (.sessions | type == "array")
  and (.capabilities | type == "object")
  and (.generated_at | type == "string")
' || fail "GET /v1/telemetry/sessions did not return the expected schema"
check_jq_bool "$body" '
  (. | tostring | test("nodeSecret|subscriptionToken|passHash|password|authorization|hosts|uri|destination"; "i")) | not
' || fail "GET /v1/telemetry/sessions leaked a forbidden field name"
pass "GET /v1/telemetry/sessions returns bounded read-only telemetry schema"

body="$tmp_dir/reload.json"
code="$tmp_dir/reload.code"
request POST /v1/reload "" "$body" "$code"
if [[ "$(cat "$code")" == "200" ]]; then
  check_jq_bool "$body" '.ok == true' || fail "POST /v1/reload HTTP 200 without ok=true"
  pass "POST /v1/reload returns ok=true"
else
  check_jq_bool "$body" '.ok == false and ((.status // "") | length > 0) and ((.message // "") | length > 0)' \
    || fail "POST /v1/reload returned HTTP $(cat "$code") without a clear error"
  pass "POST /v1/reload returns a clear protocol-service error"
fi

echo "Manual Agent Smoke Test passed: ${pass_count} checks"
