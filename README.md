# Vetka Node Agent

`vetka-node-agent` - сервисный агент для резервных нод Vetka VPN.

Этот репозиторий не является Backend Panel, Telegram Bot или основной базой пользователей. Source of truth находится во внешнем Backend Panel API и PostgreSQL. Node Agent только принимает desired state, применяет локальный конфиг выбранного протокола и отдает health/status/stats.

```text
Backend Panel / PostgreSQL = source of truth
Node Agent = executor that applies desired state
```

## Роль агента

- устанавливается на сервер ноды;
- получает `NODE_ID`, `NODE_SECRET`, `PROTOCOL_TYPE`, `NODE_PORT` извне;
- проверяет `Authorization: Bearer <NODE_SECRET>`;
- принимает полный desired state через `POST /v1/sync`;
- хранит только applied state/cache, а не бизнес-БД пользователей;
- работает в режиме one-node-one-protocol: `naive` или `mieru`;
- применяет конфиг Caddy/NaiveProxy или Mieru;
- сохраняет managed static site;
- сохраняет Naive `auth_audit_log` и `traffic_audit_log`.

## Архитектура

```text
Bot / Admin / Panel UI
        |
Backend Panel API
        |
PostgreSQL
        |
Node Manager
        |
Node Agent API
        |
Protocol Driver: naive or mieru
        |
Caddy / NaiveProxy / Mieru service
```

## Конфигурация

Минимальные переменные окружения:

```env
NODE_ID=node-1
NODE_SECRET=replace-with-long-random-secret
NODE_PORT=2222
NODE_LISTEN_HOST=0.0.0.0
PROTOCOL_TYPE=naive
BACKEND_ALLOWED_IPS=203.0.113.20
```

Для Mieru:

```env
PROTOCOL_TYPE=mieru
```

`PROTOCOL_TYPE` может быть только `naive` или `mieru`. Одна нода применяет только один активный protocol driver, даже если на сервере технически установлены оба компонента.

Служебный порт по умолчанию: `2222`. Он должен быть доступен только Backend Panel IP.

## API

Служебные endpoint'ы агента, включая `GET /health`, требуют:

```http
Authorization: Bearer <NODE_SECRET>
X-Node-Id: <NODE_ID>
```

Если `X-Node-Id` передан и не совпадает с локальным `NODE_ID`, агент вернет `403`.

Основные endpoint'ы:

```http
GET  /health
GET  /status
POST /v1/sync
POST /v1/reload
GET  /v1/stats
```

Старые `/internal/...` маршруты оставлены как deprecated compatibility/debug surface. Новый Backend должен использовать `/v1/sync`.

## Manual Agent Smoke Test

Use this before implementing Backend Panel to verify the Node Agent contract on a real node. The test talks only to the agent API and does not require Backend Panel, PostgreSQL, or a bot.

Requirements on the machine running the test:

```bash
curl
jq
bash
```

Run:

```bash
NODE_AGENT_URL=http://127.0.0.1:2222 \
NODE_ID=alps-naive-1 \
NODE_SECRET='<NODE_SECRET>' \
PROTOCOL_TYPE=naive \
bash tests/manual-agent-smoke.sh
```

For Mieru:

```bash
NODE_AGENT_URL=http://127.0.0.1:2222 \
NODE_ID=alps-mieru-1 \
NODE_SECRET='<NODE_SECRET>' \
PROTOCOL_TYPE=mieru \
bash tests/manual-agent-smoke.sh
```

The script verifies:

- `GET /health` without Bearer is rejected with `401` or `403`;
- `GET /health` with Bearer returns `ok=true`;
- `GET /status` returns `node_id`, `protocol_type`, and current applied version;
- `POST /v1/sync` with the next `config_version` applies desired state;
- repeating the same sync is a no-op;
- stale `config_version` is rejected as `stale_version`;
- `GET /v1/stats` returns `ok=true`;
- `POST /v1/reload` returns `ok=true` or a clear protocol-service error.

`manual-agent-smoke.sh` dynamically sets `config_version` based on current `/status`, so it can be safely re-run.

Payload examples live in `examples/`:

- `examples/sync-naive-v1.json`
- `examples/sync-naive-v1-repeat.json`
- `examples/sync-naive-stale.json`
- `examples/sync-mieru-v1.json`

The smoke test mutates the local agent users cache and protocol config. Run it on a fresh test node or a node prepared for this check.

## Local UI Is Read-Only By Default

Локальный UI в этом репозитории является debug/maintenance UI, а не Backend Panel.

По умолчанию локальные изменения пользователей отключены:

```env
ALLOW_LOCAL_USER_MUTATIONS=false
```

Эквивалент в config:

```json
{
  "allowLocalUserMutations": false
}
```

Когда `allowLocalUserMutations=false`, legacy endpoints вроде `POST /api/users`, `PATCH /api/users/:id`, `DELETE /api/users/:id`, reset sessions и rotate token возвращают:

```json
{
  "ok": false,
  "error": "Local user mutations are disabled; use Backend Panel /v1/sync"
}
```

Production flow должен использовать Backend Panel + `POST /v1/sync`. Включать `ALLOW_LOCAL_USER_MUTATIONS=true` можно только для локального dev/debug режима. Node Agent не является source of truth.

## POST /v1/sync

Backend отправляет полный desired state для конкретной ноды:

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
      "quota_mb": 0,
      "meta": {
        "backend_user_id": 123,
        "telegram_id": 123456789
      }
    }
  ]
}
```

Агент:

- проверяет Bearer token;
- проверяет `node_id`;
- проверяет `protocol_type`;
- сравнивает `config_version` с локальным `current_version`;
- возвращает `stale_version`, если версия ниже примененной;
- возвращает no-op, если версия и hash desired state уже применены;
- заменяет локальный users cache payload'ом Backend;
- атомарно применяет конфиг выбранного driver;
- обновляет `applied_version` только после успешного reload/apply.

Applied state хранится локально:

```text
/var/lib/vetka-node-agent/state.json
```

Это cache, а не бизнес-база.

## Firewall

Если используется UFW, порт агента не должен открываться всему интернету. Разрешайте только Backend Panel IP:

```bash
ufw allow from <BACKEND_PANEL_IP> to any port 2222 proto tcp
```

Если Backend IP не задан, установщик должен предупреждать оператора и не открывать `NODE_PORT` публично без явного подтверждения.

## Managed Static Site

Функция managed static site сохраняется. Скрипт:

```bash
bash /opt/vetka-node-agent/scripts/static-site.sh status
bash /opt/vetka-node-agent/scripts/static-site.sh deploy
bash /opt/vetka-node-agent/scripts/static-site.sh deploy --url https://example.com/dist.tar.gz
bash /opt/vetka-node-agent/scripts/static-site.sh rollback
```

Пути могут быть переименованы в будущей миграции, но команды `status`, `deploy`, `deploy --url`, `rollback` должны остаться рабочими.

## Проверки

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

Если доступны npm-зависимости:

```bash
cd panel
npm test
```
