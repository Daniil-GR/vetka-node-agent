# Vetka Node Agent Notes

This repository contains only the node-side executor for Vetka reserve nodes.

The Backend Panel and PostgreSQL are the source of truth. The agent receives desired state through `/v1/sync`, applies the selected local protocol driver, and stores only applied state/cache.

## Runtime Paths

```text
PANEL_DIR=/opt/vetka-node-agent
PANEL_CONFIG=/etc/vetka-node-agent/config.json
VERSION_FILE=/etc/vetka-node-agent/version
BACKUP_DIR=/etc/vetka-node-agent/backups
DB_PATH=/var/lib/vetka-node-agent/cache.sqlite
MITA_STATE_FILE=/var/lib/vetka-node-agent/mita-state.json
APPLIED_STATE_FILE=/var/lib/vetka-node-agent/state.json
LOG_PANEL=/var/log/vetka-node-agent.log
INSTALL_LOG=/var/log/vetka-node-agent-install.log
```

Old `/etc/rixxx-panel`, `/var/lib/rixxx-panel`, and `/opt/panel-naive-mieru` paths are legacy migration/cleanup concerns only.

## Auth

Primary service API auth:

```http
Authorization: Bearer <NODE_SECRET>
X-Node-Id: <NODE_ID>
```

`X-Node-Id` is optional, but if it is present it must match local `NODE_ID`.

Deprecated `/internal/...` endpoints may use `nodeApiKey` for compatibility. New Backend sync must use `NODE_SECRET` / `cfg.nodeSecret`.

## Endpoints

```text
GET  /health
GET  /status
POST /v1/sync
POST /v1/reload
GET  /v1/stats
```

Agent service endpoints, including `GET /health`, require Bearer auth.

## Sync Contract

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

Rules:

- `protocol_type` must match local `cfg.protocolType`.
- stale `config_version` returns `stale_version`.
- same `config_version` and same state hash returns no-op.
- `applied_version` is written only after successful protocol apply.
- on apply failure, users cache is rolled back.
- `protocolType=naive` writes users with `protocols=["naive"]`.
- `protocolType=mieru` writes users with `protocols=["mieru"]`.

## Manual Agent Smoke Test

Use this before implementing Backend Panel to verify the Node Agent contract on a real node. The test talks only to the agent API and does not require Backend Panel, PostgreSQL, or a bot.

Requirements on the machine running the test:

```bash
curl
jq
bash
```

Naive example:

```bash
NODE_AGENT_URL=http://127.0.0.1:2222 \
NODE_ID=alps-naive-1 \
NODE_SECRET='<NODE_SECRET>' \
PROTOCOL_TYPE=naive \
bash tests/manual-agent-smoke.sh
```

Mieru example:

```bash
NODE_AGENT_URL=http://127.0.0.1:2222 \
NODE_ID=alps-mieru-1 \
NODE_SECRET='<NODE_SECRET>' \
PROTOCOL_TYPE=mieru \
bash tests/manual-agent-smoke.sh
```

The script verifies:

- `GET /health` without Bearer is rejected with `401` or `403`.
- `GET /health` with Bearer returns `ok=true`.
- `GET /status` returns `node_id`, `protocol_type`, and current applied version.
- `POST /v1/sync` with the next `config_version` applies desired state.
- repeating the same sync is a no-op.
- stale `config_version` is rejected as `stale_version`.
- `GET /v1/stats` returns `ok=true`.
- `POST /v1/reload` returns `ok=true` or a clear protocol-service error.

`manual-agent-smoke.sh` dynamically sets `config_version` based on current `/status`, so it can be safely re-run.

Payload examples:

```text
examples/sync-naive-v1.json
examples/sync-naive-v1-repeat.json
examples/sync-naive-stale.json
examples/sync-mieru-v1.json
```

The smoke test mutates the local agent users cache and protocol config. Run it on a fresh test node or a node prepared for this check.

## Local User Mutations

Local user mutations are disabled by default:

```env
ALLOW_LOCAL_USER_MUTATIONS=false
```

```json
{
  "allowLocalUserMutations": false
}
```

With the default setting, legacy mutation routes return:

```json
{
  "ok": false,
  "error": "Local user mutations are disabled; use Backend Panel /v1/sync"
}
```

Read-only local UI/API endpoints may remain available for debugging. Production writes must come from Backend Panel through `/v1/sync`. `ALLOW_LOCAL_USER_MUTATIONS=true` is only for local dev/debug mode.

## One Node, One Protocol

`PROTOCOL_TYPE` can be only:

```text
naive
mieru
```

Even if both services are installed, the agent applies only the configured driver.

## Managed Static Site

Keep these commands working after path migration:

```bash
panel/scripts/static-site.sh status
panel/scripts/static-site.sh deploy
panel/scripts/static-site.sh deploy --url https://example.com/dist.tar.gz
panel/scripts/static-site.sh rollback
```

Installed path:

```text
/opt/vetka-node-agent/scripts/static-site.sh
```
