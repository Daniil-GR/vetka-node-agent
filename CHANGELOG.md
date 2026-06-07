# Changelog

## 1.2.6

- Rebranded the repository as Vetka Node Agent.
- Standardized runtime paths under `/opt/vetka-node-agent`, `/etc/vetka-node-agent`, and `/var/lib/vetka-node-agent`.
- Added the service API contract: `/health`, `/status`, `/v1/sync`, `/v1/reload`, `/v1/stats`.
- Added `NODE_ID`, `NODE_SECRET`, `NODE_PORT`, `NODE_LISTEN_HOST`, and `PROTOCOL_TYPE` based runtime identity.
- Implemented idempotent `/v1/sync` with `config_version`, desired-state hashing, stale-version rejection, and applied-state persistence.
- Kept the local users database as cache/applied state only.
- Preserved managed static site, Naive audit log, and Mieru service behavior.
- Marked legacy `/internal/...` and `nodeApiKey` flow as deprecated compatibility surface.

## Notes

Backend Panel, PostgreSQL, Telegram Bot, subscription builder, and business subscription logic intentionally live outside this repository.
