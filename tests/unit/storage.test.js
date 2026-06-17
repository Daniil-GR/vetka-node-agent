'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { panelRequire } = require('../helpers/panel-require');
const Database = panelRequire('better-sqlite3');

const storage = require('../../panel/server/telemetry/storage');

function makeDb() {
  const db = new Database(':memory:');
  storage.initTelemetryTables(db);
  return db;
}

test('storage init creates telemetry tables and the client_ip index', () => {
  const db = makeDb();
  const indexes = db.prepare(`PRAGMA index_list('telemetry_sessions')`).all();
  assert.ok(indexes.some((row) => row.name === 'idx_telemetry_sessions_client_ip'));
});

test('upsertNaiveObservation and listTelemetrySessions keep active and recent rows queryable', () => {
  const db = makeDb();
  storage.upsertNaiveObservation(db, {
    protocol_username: 'u_one',
    client_ip: '198.51.100.1',
    first_seen_at: '2026-06-15T10:00:00.000Z',
    last_seen_at: '2026-06-15T10:05:00.000Z',
    upload_bytes: 10,
    download_bytes: 20,
    source: 'naive-audit',
    traffic_scope: 'telemetry-retention-window',
    ip_observed: true,
    traffic_observed: true
  });
  storage.upsertNaiveObservation(db, {
    protocol_username: 'u_one',
    client_ip: '198.51.100.1',
    first_seen_at: '2026-06-15T10:01:00.000Z',
    last_seen_at: '2026-06-15T10:06:00.000Z',
    upload_bytes: 5,
    download_bytes: 7,
    source: 'naive-audit',
    traffic_scope: 'telemetry-retention-window',
    ip_observed: true,
    traffic_observed: true
  });

  const listed = storage.listTelemetrySessions(db, {
    includeRecent: false,
    activeCutoffIso: '2026-06-15T10:00:00.000Z',
    historyCutoffIso: '2026-06-15T09:00:00.000Z',
    limit: 10
  });
  assert.equal(listed.sessions.length, 1);
  assert.equal(listed.sessions[0].upload_bytes, 15);
  assert.equal(listed.sessions[0].download_bytes, 27);
});

test('upsertMieruObservation ignores rows without a valid last_seen_at', () => {
  const db = makeDb();
  storage.upsertMieruObservation(db, {
    protocol_username: 'u_mieru',
    first_seen_at: '2026-06-15T10:00:00.000Z',
    last_seen_at: null,
    upload_bytes: 10,
    download_bytes: 20,
    updated_at: '2026-06-15T10:10:00.000Z'
  });
  const count = db.prepare('SELECT COUNT(*) AS count FROM telemetry_sessions').get().count;
  assert.equal(count, 0);
});

test('saveCheckpoint participates in transaction rollback without advancing the stored offset', () => {
  const db = makeDb();
  storage.saveCheckpoint(db, {
    file_path: '/tmp/auth.log',
    device: '1',
    inode: '2',
    offset: 5,
    partial_trailing_line: '{"host":"x","uri":"/secret"}',
    discard_until_newline: 1,
    discard_reason: 'oversized',
    rotated_source_path: '/tmp/auth.log.1',
    last_successful_read_at: '2026-06-15T10:00:00.000Z',
    last_error: null
  });

  const tx = db.transaction(() => {
    storage.saveCheckpoint(db, {
      file_path: '/tmp/auth.log',
      device: '1',
      inode: '2',
      offset: 999,
      partial_trailing_line: '',
      discard_until_newline: 0,
      discard_reason: '',
      rotated_source_path: '',
      last_successful_read_at: '2026-06-15T10:05:00.000Z',
      last_error: null
    });
    throw new Error('boom');
  });

  assert.throws(() => tx(), /boom/);
  const checkpoint = storage.loadCheckpoint(db, '/tmp/auth.log');
  assert.equal(checkpoint.offset, 5);
  assert.equal(checkpoint.partial_trailing_line, '');
  assert.equal(checkpoint.discard_until_newline, 1);
  assert.equal(checkpoint.rotated_source_path, '/tmp/auth.log.1');
});

test('storage init scrubs legacy raw partial_trailing_line content without destructive migration', () => {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE telemetry_checkpoints (
      file_path TEXT PRIMARY KEY,
      device TEXT,
      inode TEXT,
      offset INTEGER NOT NULL DEFAULT 0,
      partial_trailing_line TEXT NOT NULL DEFAULT '',
      last_successful_read_at TEXT,
      last_error TEXT
    );
  `);
  db.prepare(`
    INSERT INTO telemetry_checkpoints (file_path, device, inode, offset, partial_trailing_line)
    VALUES (?, ?, ?, ?, ?)
  `).run('/tmp/legacy.log', '1', '2', 10, '{"host":"secret.example","uri":"/p"}');

  storage.initTelemetryTables(db);
  const row = storage.loadCheckpoint(db, '/tmp/legacy.log');
  assert.equal(row.partial_trailing_line, '');
  assert.equal(row.discard_until_newline, 0);
});

test('pruneExpiredTelemetry removes only rows older than the cutoff', () => {
  const db = makeDb();
  storage.upsertNaiveObservation(db, {
    protocol_username: 'old',
    client_ip: '198.51.100.10',
    first_seen_at: '2026-06-15T08:00:00.000Z',
    last_seen_at: '2026-06-15T08:00:00.000Z',
    upload_bytes: 1,
    download_bytes: 1
  });
  storage.upsertNaiveObservation(db, {
    protocol_username: 'new',
    client_ip: '198.51.100.11',
    first_seen_at: '2026-06-15T10:00:00.000Z',
    last_seen_at: '2026-06-15T10:00:00.000Z',
    upload_bytes: 1,
    download_bytes: 1
  });
  const removed = storage.pruneExpiredTelemetry(db, '2026-06-15T09:00:00.000Z');
  assert.equal(removed, 1);
  const usernames = db.prepare('SELECT protocol_username FROM telemetry_sessions ORDER BY protocol_username').all().map((row) => row.protocol_username);
  assert.deepEqual(usernames, ['new']);
});
