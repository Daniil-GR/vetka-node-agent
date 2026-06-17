'use strict';

function toIso(value) {
  if (!value) return null;
  if (value instanceof Date) return value.toISOString();
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function initTelemetryTables(db) {
  if (!db) return;
  db.exec(`
    CREATE TABLE IF NOT EXISTS telemetry_sessions (
      session_key TEXT PRIMARY KEY,
      protocol TEXT NOT NULL,
      protocol_username TEXT NOT NULL,
      client_ip TEXT,
      first_seen_at TEXT NOT NULL,
      last_seen_at TEXT NOT NULL,
      upload_bytes INTEGER NOT NULL DEFAULT 0,
      download_bytes INTEGER NOT NULL DEFAULT 0,
      source TEXT NOT NULL,
      traffic_scope TEXT NOT NULL,
      ip_observed INTEGER NOT NULL DEFAULT 0,
      traffic_observed INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_telemetry_sessions_last_seen
      ON telemetry_sessions(last_seen_at DESC);
    CREATE INDEX IF NOT EXISTS idx_telemetry_sessions_protocol_username
      ON telemetry_sessions(protocol, protocol_username, last_seen_at DESC);
    CREATE INDEX IF NOT EXISTS idx_telemetry_sessions_client_ip
      ON telemetry_sessions(client_ip, last_seen_at DESC);

    CREATE TABLE IF NOT EXISTS telemetry_checkpoints (
      file_path TEXT PRIMARY KEY,
      device TEXT,
      inode TEXT,
      offset INTEGER NOT NULL DEFAULT 0,
      partial_trailing_line TEXT NOT NULL DEFAULT '',
      discard_until_newline INTEGER NOT NULL DEFAULT 0,
      discard_reason TEXT NOT NULL DEFAULT '',
      rotated_source_path TEXT NOT NULL DEFAULT '',
      last_successful_read_at TEXT,
      last_error TEXT
    );

    CREATE TABLE IF NOT EXISTS telemetry_collector_state (
      collector TEXT PRIMARY KEY,
      status TEXT NOT NULL,
      warnings_json TEXT NOT NULL DEFAULT '[]',
      details_json TEXT NOT NULL DEFAULT '{}',
      last_successful_collection_at TEXT,
      last_attempted_collection_at TEXT,
      last_error TEXT
    );
  `);
  ensureCheckpointColumns(db);
  scrubLegacyCheckpointPayloads(db);
}

function sessionKey(protocol, username, clientIp) {
  return [String(protocol || ''), String(username || ''), String(clientIp || '')].join('\n');
}

function loadCheckpoint(db, filePath) {
  if (!db || !filePath) {
    return {
      file_path: filePath || '',
      device: '',
      inode: '',
      offset: 0,
      partial_trailing_line: '',
      last_successful_read_at: null,
      last_error: null
    };
  }
  const row = db.prepare(`
    SELECT file_path, device, inode, offset, partial_trailing_line, discard_until_newline,
           discard_reason, rotated_source_path, last_successful_read_at, last_error
    FROM telemetry_checkpoints
    WHERE file_path = ?
  `).get(filePath);
  return row || {
    file_path: filePath,
    device: '',
    inode: '',
    offset: 0,
    partial_trailing_line: '',
    discard_until_newline: 0,
    discard_reason: '',
    rotated_source_path: '',
    last_successful_read_at: null,
    last_error: null
  };
}

function saveCheckpoint(db, checkpoint) {
  if (!db || !checkpoint?.file_path) return;
  db.prepare(`
    INSERT INTO telemetry_checkpoints
      (file_path, device, inode, offset, partial_trailing_line, discard_until_newline,
       discard_reason, rotated_source_path, last_successful_read_at, last_error)
    VALUES
      (@file_path, @device, @inode, @offset, @partial_trailing_line, @discard_until_newline,
       @discard_reason, @rotated_source_path, @last_successful_read_at, @last_error)
    ON CONFLICT(file_path) DO UPDATE SET
      device = excluded.device,
      inode = excluded.inode,
      offset = excluded.offset,
      partial_trailing_line = excluded.partial_trailing_line,
      discard_until_newline = excluded.discard_until_newline,
      discard_reason = excluded.discard_reason,
      rotated_source_path = excluded.rotated_source_path,
      last_successful_read_at = excluded.last_successful_read_at,
      last_error = excluded.last_error
  `).run({
    file_path: checkpoint.file_path,
    device: checkpoint.device || '',
    inode: checkpoint.inode || '',
    offset: Number.isFinite(checkpoint.offset) ? checkpoint.offset : 0,
    partial_trailing_line: '',
    discard_until_newline: checkpoint.discard_until_newline ? 1 : 0,
    discard_reason: checkpoint.discard_reason || '',
    rotated_source_path: checkpoint.rotated_source_path || '',
    last_successful_read_at: checkpoint.last_successful_read_at || null,
    last_error: checkpoint.last_error || null
  });
}

function updateCollectorState(db, state) {
  if (!db || !state?.collector) return;
  db.prepare(`
    INSERT INTO telemetry_collector_state
      (collector, status, warnings_json, details_json, last_successful_collection_at, last_attempted_collection_at, last_error)
    VALUES
      (@collector, @status, @warnings_json, @details_json, @last_successful_collection_at, @last_attempted_collection_at, @last_error)
    ON CONFLICT(collector) DO UPDATE SET
      status = excluded.status,
      warnings_json = excluded.warnings_json,
      details_json = excluded.details_json,
      last_successful_collection_at = excluded.last_successful_collection_at,
      last_attempted_collection_at = excluded.last_attempted_collection_at,
      last_error = excluded.last_error
  `).run({
    collector: state.collector,
    status: state.status || 'unavailable',
    warnings_json: JSON.stringify(Array.isArray(state.warnings) ? state.warnings : []),
    details_json: JSON.stringify(state.details || {}),
    last_successful_collection_at: state.last_successful_collection_at || null,
    last_attempted_collection_at: state.last_attempted_collection_at || null,
    last_error: state.last_error || null
  });
}

function getCollectorState(db, collector = 'telemetry') {
  if (!db) return null;
  const row = db.prepare(`
    SELECT collector, status, warnings_json, details_json, last_successful_collection_at, last_attempted_collection_at, last_error
    FROM telemetry_collector_state
    WHERE collector = ?
  `).get(collector);
  if (!row) return null;
  return {
    collector: row.collector,
    status: row.status,
    warnings: safeJson(row.warnings_json, []),
    details: safeJson(row.details_json, {}),
    last_successful_collection_at: row.last_successful_collection_at || null,
    last_attempted_collection_at: row.last_attempted_collection_at || null,
    last_error: row.last_error || null
  };
}

function safeJson(value, fallback) {
  try { return JSON.parse(value); } catch { return fallback; }
}

function ensureCheckpointColumns(db) {
  const columns = db.prepare(`PRAGMA table_info('telemetry_checkpoints')`).all().map((row) => row.name);
  if (!columns.includes('discard_until_newline')) {
    db.exec(`ALTER TABLE telemetry_checkpoints ADD COLUMN discard_until_newline INTEGER NOT NULL DEFAULT 0`);
  }
  if (!columns.includes('discard_reason')) {
    db.exec(`ALTER TABLE telemetry_checkpoints ADD COLUMN discard_reason TEXT NOT NULL DEFAULT ''`);
  }
  if (!columns.includes('rotated_source_path')) {
    db.exec(`ALTER TABLE telemetry_checkpoints ADD COLUMN rotated_source_path TEXT NOT NULL DEFAULT ''`);
  }
}

function scrubLegacyCheckpointPayloads(db) {
  db.prepare(`
    UPDATE telemetry_checkpoints
    SET partial_trailing_line = ''
    WHERE partial_trailing_line <> ''
  `).run();
}

function upsertNaiveObservation(db, observation) {
  if (!db || !observation?.protocol_username) return;
  const nowIso = toIso(observation.updated_at) || new Date().toISOString();
  const firstSeen = toIso(observation.first_seen_at) || nowIso;
  const lastSeen = toIso(observation.last_seen_at) || firstSeen;
  const key = sessionKey('naive', observation.protocol_username, observation.client_ip);
  db.prepare(`
    INSERT INTO telemetry_sessions
      (session_key, protocol, protocol_username, client_ip, first_seen_at, last_seen_at,
       upload_bytes, download_bytes, source, traffic_scope, ip_observed, traffic_observed, updated_at)
    VALUES
      (@session_key, 'naive', @protocol_username, @client_ip, @first_seen_at, @last_seen_at,
       @upload_bytes, @download_bytes, @source, @traffic_scope, @ip_observed, @traffic_observed, @updated_at)
    ON CONFLICT(session_key) DO UPDATE SET
      first_seen_at = CASE
        WHEN excluded.first_seen_at < telemetry_sessions.first_seen_at THEN excluded.first_seen_at
        ELSE telemetry_sessions.first_seen_at
      END,
      last_seen_at = CASE
        WHEN excluded.last_seen_at > telemetry_sessions.last_seen_at THEN excluded.last_seen_at
        ELSE telemetry_sessions.last_seen_at
      END,
      upload_bytes = telemetry_sessions.upload_bytes + excluded.upload_bytes,
      download_bytes = telemetry_sessions.download_bytes + excluded.download_bytes,
      source = excluded.source,
      traffic_scope = excluded.traffic_scope,
      ip_observed = CASE WHEN telemetry_sessions.ip_observed = 1 OR excluded.ip_observed = 1 THEN 1 ELSE 0 END,
      traffic_observed = CASE WHEN telemetry_sessions.traffic_observed = 1 OR excluded.traffic_observed = 1 THEN 1 ELSE 0 END,
      updated_at = excluded.updated_at
  `).run({
    session_key: key,
    protocol_username: observation.protocol_username,
    client_ip: observation.client_ip || null,
    first_seen_at: firstSeen,
    last_seen_at: lastSeen,
    upload_bytes: Math.max(0, Math.trunc(observation.upload_bytes || 0)),
    download_bytes: Math.max(0, Math.trunc(observation.download_bytes || 0)),
    source: observation.source || 'naive-audit',
    traffic_scope: observation.traffic_scope || 'telemetry-retention-window',
    ip_observed: observation.ip_observed === false ? 0 : 1,
    traffic_observed: observation.traffic_observed === true ? 1 : 0,
    updated_at: nowIso
  });
}

function upsertMieruObservation(db, observation) {
  if (!db || !observation?.protocol_username) return;
  const lastSeen = toIso(observation.last_seen_at);
  if (!lastSeen) return;
  const nowIso = toIso(observation.updated_at) || new Date().toISOString();
  const firstSeen = toIso(observation.first_seen_at) || nowIso;
  const key = sessionKey('mieru', observation.protocol_username, null);
  db.prepare(`
    INSERT INTO telemetry_sessions
      (session_key, protocol, protocol_username, client_ip, first_seen_at, last_seen_at,
       upload_bytes, download_bytes, source, traffic_scope, ip_observed, traffic_observed, updated_at)
    VALUES
      (@session_key, 'mieru', @protocol_username, NULL, @first_seen_at, @last_seen_at,
       @upload_bytes, @download_bytes, @source, @traffic_scope, 0, @traffic_observed, @updated_at)
    ON CONFLICT(session_key) DO UPDATE SET
      first_seen_at = CASE
        WHEN excluded.first_seen_at < telemetry_sessions.first_seen_at THEN excluded.first_seen_at
        ELSE telemetry_sessions.first_seen_at
      END,
      last_seen_at = CASE
        WHEN excluded.last_seen_at > telemetry_sessions.last_seen_at THEN excluded.last_seen_at
        ELSE telemetry_sessions.last_seen_at
      END,
      upload_bytes = CASE WHEN excluded.upload_bytes >= 0 THEN excluded.upload_bytes ELSE telemetry_sessions.upload_bytes END,
      download_bytes = CASE WHEN excluded.download_bytes >= 0 THEN excluded.download_bytes ELSE telemetry_sessions.download_bytes END,
      source = excluded.source,
      traffic_scope = excluded.traffic_scope,
      traffic_observed = excluded.traffic_observed,
      updated_at = excluded.updated_at
  `).run({
    session_key: key,
    protocol_username: observation.protocol_username,
    first_seen_at: firstSeen,
    last_seen_at: lastSeen,
    upload_bytes: Math.max(0, Math.trunc(observation.upload_bytes || 0)),
    download_bytes: Math.max(0, Math.trunc(observation.download_bytes || 0)),
    source: observation.source || 'mita-get-users',
    traffic_scope: observation.traffic_scope || 'mieru-30-day-counter',
    traffic_observed: observation.traffic_observed === false ? 0 : 1,
    updated_at: nowIso
  });
}

function pruneExpiredTelemetry(db, cutoffIso) {
  if (!db || !cutoffIso) return 0;
  const result = db.prepare(`
    DELETE FROM telemetry_sessions
    WHERE last_seen_at < ?
  `).run(cutoffIso);
  return result.changes || 0;
}

function pruneLegacyTrafficSnapshots(db, cutoffIso) {
  if (!db || !cutoffIso) return 0;
  try {
    const result = db.prepare(`
      DELETE FROM traffic_snapshots
      WHERE ts < ?
    `).run(cutoffIso);
    return result.changes || 0;
  } catch {
    return 0;
  }
}

function listTelemetrySessions(db, options = {}) {
  if (!db) return { sessions: [], overflow: false };
  const cutoff = options.includeRecent ? options.historyCutoffIso : options.activeCutoffIso;
  const limit = Number.isInteger(options.limit) && options.limit > 0 ? options.limit : 5000;
  const rows = db.prepare(`
    SELECT
      protocol,
      protocol_username,
      client_ip,
      first_seen_at,
      last_seen_at,
      upload_bytes,
      download_bytes,
      source,
      traffic_scope,
      ip_observed,
      traffic_observed,
      updated_at
    FROM telemetry_sessions
    WHERE last_seen_at >= ?
    ORDER BY last_seen_at DESC, updated_at DESC, protocol_username ASC
    LIMIT ?
  `).all(cutoff, limit + 1);
  return {
    sessions: rows.slice(0, limit),
    overflow: rows.length > limit
  };
}

module.exports = {
  initTelemetryTables,
  loadCheckpoint,
  saveCheckpoint,
  updateCollectorState,
  getCollectorState,
  upsertNaiveObservation,
  upsertMieruObservation,
  pruneExpiredTelemetry,
  pruneLegacyTrafficSnapshots,
  listTelemetrySessions,
  sessionKey,
  toIso
};
