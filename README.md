# Vetka Node Agent

`vetka-node-agent` is the service-side executor for Vetka VPN reserve nodes.

This repository is not the Backend Panel, Telegram Bot, or primary user database. The external Backend Panel API and PostgreSQL are the source of truth. The Node Agent only receives desired state, applies local protocol configuration, and exposes health/status/stats.

```text
Backend Panel / PostgreSQL = source of truth
Node Agent = executor that applies desired state
```

## Terminal Compatibility

`install.sh`, `update.sh`, and `uninstall.sh` default to English/ASCII output so they remain readable over SSH from Windows PowerShell and terminals without a UTF-8 locale. If you want UTF-8 in Windows PowerShell before SSH, you can run:

```powershell
chcp 65001
```

## Installation Layout

Clone the source repository into a separate source directory. Do not run `install.sh` from the runtime directory `/opt/vetka-node-agent`.

Correct install flow:

```bash
git clone https://github.com/Daniil-GR/vetka-node-agent.git /opt/vetka-node-agent-src
cd /opt/vetka-node-agent-src
sudo env NODE_ID=node-1 NODE_SECRET=replace-with-long-random-secret PROTOCOL_TYPE=naive bash install.sh
```

Runtime files are installed into:

```text
/opt/vetka-node-agent
```

After install:

- `/opt/vetka-node-agent-src` remains the source repo checkout;
- `/opt/vetka-node-agent` contains the runtime app used by PM2;
- the runtime app does not depend on `.git`;
- `update.sh` refreshes runtime files through a temporary GitHub checkout instead of treating `/opt/vetka-node-agent` as a git repository.

## Agent Role

- installed on a node server;
- receives `NODE_ID`, `NODE_SECRET`, `PROTOCOL_TYPE`, and `NODE_PORT` from the environment or local config;
- validates `Authorization: Bearer <NODE_SECRET>`;
- accepts full desired state through `POST /v1/sync`;
- stores only applied state/cache, not a business user database;
- uses one-node-one-protocol: `naive` or `mieru`;
- applies Caddy/NaiveProxy or Mieru config;
- keeps the managed static site feature;
- keeps Naive `auth_audit_log` and `traffic_audit_log`.

## Runtime Config

```env
NODE_ID=node-1
NODE_SECRET=replace-with-long-random-secret
NODE_PORT=2222
NODE_LISTEN_HOST=0.0.0.0
PROTOCOL_TYPE=naive
BACKEND_ALLOWED_IPS=203.0.113.20
```

For Mieru:

```env
PROTOCOL_TYPE=mieru
```

`PROTOCOL_TYPE` must be exactly `naive` or `mieru`. A node applies only the selected driver, even if both components are installed on the host.

The default service port is `2222`. It should be reachable only from the Backend Panel IP.

## API

`GET /health` may be used by local health checks. Service endpoints require:

```http
Authorization: Bearer <NODE_SECRET>
X-Node-Id: <NODE_ID>
```

If `X-Node-Id` is present and does not match local `NODE_ID`, the agent returns `403`.

```http
GET  /health
GET  /status
POST /v1/sync
POST /v1/reload
GET  /v1/stats
GET  /v1/telemetry/sessions
```

Legacy `/internal/...` routes are kept only as deprecated compatibility/debug endpoints. New Backend integrations should use `/v1/sync`.

## Read-Only Telemetry

The Node Agent exposes a bounded read-only telemetry contract for Backend polling:

```http
GET /v1/telemetry/sessions
GET /v1/telemetry/sessions?include_recent=true
```

This endpoint uses the same `Authorization: Bearer <NODE_SECRET>` and optional `X-Node-Id` checks as the other `/v1` routes.

Telemetry notes:

- default response returns only active observations inside `sessionTtlMinutes`;
- `include_recent=true` also returns inactive retained observations inside `ipHistoryTtlHours`;
- Naive telemetry comes from incremental processing of `auth_audit_log` and `traffic_audit_log`;
- Mieru telemetry comes from `mita get users`;
- Mieru returns `client_ip=null` because reliable per-user remote IP correlation is not available there;
- `traffic_scope` is `telemetry-retention-window` for Naive and `mieru-30-day-counter` for Mieru;
- SQLite on the node remains a disposable local cache, not the source of truth;
- destination history, raw events, passwords, pass hashes, node secret, authorization headers, and subscription tokens are intentionally not stored or returned.

Telemetry config defaults:

```json
{
  "telemetryEnabled": true,
  "telemetryCollectIntervalSeconds": 15
}
```

This patch does not add enforcement. It does not disconnect users, block IPs, change credentials, enable `enforceIpLimit`, or automatically apply `maxUniqueIpsPerUser`.

## Local UI Is Read-Only By Default

The local UI in this repository is a debug/maintenance UI, not the Backend Panel.

Local user mutations are disabled by default:

```env
ALLOW_LOCAL_USER_MUTATIONS=false
```

Config equivalent:

```json
{
  "allowLocalUserMutations": false
}
```

When `allowLocalUserMutations=false`, legacy endpoints such as `POST /api/users`, `PATCH /api/users/:id`, `DELETE /api/users/:id`, reset sessions, and rotate token return:

```json
{
  "ok": false,
  "error": "Local user mutations are disabled; use Backend Panel /v1/sync"
}
```

Production flow must use Backend Panel + `POST /v1/sync`. Set `ALLOW_LOCAL_USER_MUTATIONS=true` only for local dev/debug mode. The Node Agent is not the source of truth.

## POST /v1/sync

Backend sends the full desired state for one node:

```json
{
  "node_id": "alps-naive-1",
  "config_version": 3,
  "protocol_type": "naive",
  "users": [
    {
      "id": "u_123",
      "username": "user_123",
      "password": "secret",
      "enabled": true,
      "expires_at": "2026-07-02T00:00:00Z",
      "quota_mb": 0
    }
  ]
}
```

The agent rejects stale `config_version`, returns no-op for an already applied version and state hash, replaces the local users cache from Backend payload, applies the selected protocol driver atomically, and writes `applied_version` only after a successful reload/apply.

Applied state is stored locally:

```text
/var/lib/vetka-node-agent/state.json
```

This file is cache, not a business database.

## Checks

```bash
bash -n install.sh
bash -n update.sh
bash -n tests/e2e.sh
bash -n panel/scripts/static-site.sh 2>/dev/null || true

node --check panel/server/index.js
node --check panel/server/caddyTemplate.js
node --check panel/public/app.js

git diff --check
```
