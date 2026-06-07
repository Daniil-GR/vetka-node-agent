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

`GET /health` can be used by local system checks. The other endpoints require Bearer auth.

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
