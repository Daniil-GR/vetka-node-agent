'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { panelRequire } = require('../helpers/panel-require');
const Database = panelRequire('better-sqlite3');

const { createLegacyMieruCompatibilityUpdater, buildMieruUserStatsResponse } = require('../../panel/server/mieruStats');

function makeDb() {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE users (
      id TEXT PRIMARY KEY,
      email TEXT,
      username TEXT UNIQUE,
      passHash TEXT,
      password TEXT,
      expiry TEXT,
      protocols TEXT,
      quotaMB REAL,
      usedMB REAL,
      enabled INTEGER,
      suspicious INTEGER,
      subscriptionToken TEXT,
      createdAt TEXT,
      updatedAt TEXT,
      lastSeen TEXT
    );
    CREATE TABLE traffic_snapshots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT NOT NULL,
      uploadMB REAL DEFAULT 0,
      downloadMB REAL DEFAULT 0,
      ts TEXT NOT NULL
    );
  `);
  db.prepare(`
    INSERT INTO users (id, email, username, passHash, password, expiry, protocols, quotaMB, usedMB, enabled, suspicious, subscriptionToken, createdAt, updatedAt, lastSeen)
    VALUES ('1', 'a@example.com', 'alice', 'hash', 'secret', '2030-01-01T00:00:00.000Z', '[]', 100, 1, 1, 0, 'tok', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')
  `).run();
  db.prepare(`
    INSERT INTO users (id, email, username, passHash, password, expiry, protocols, quotaMB, usedMB, enabled, suspicious, subscriptionToken, createdAt, updatedAt, lastSeen)
    VALUES ('2', 'b@example.com', 'bob', 'hash2', 'secret2', '2031-01-01T00:00:00.000Z', '[]', 200, 2, 0, 0, 'tok2', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')
  `).run();
  return db;
}

test('legacy updater does not insert new traffic_snapshots rows and updates only telemetry fields', () => {
  const db = makeDb();
  let now = 1000;
  const updater = createLegacyMieruCompatibilityUpdater({
    db,
    getAllUsers: () => db.prepare('SELECT * FROM users ORDER BY username').all(),
    historyCutoffIso: () => '2020-01-01T00:00:00.000Z',
    nowMs: () => now
  });

  const beforeSnapshots = db.prepare('SELECT COUNT(*) AS count FROM traffic_snapshots').get().count;
  updater.apply([{
    protocol_username: 'alice',
    upload_bytes: 1048576,
    download_bytes: 2097152,
    last_seen_at: '2026-06-15T12:00:00.000Z'
  }], '2026-06-15T12:00:00.000Z');

  const afterSnapshots = db.prepare('SELECT COUNT(*) AS count FROM traffic_snapshots').get().count;
  assert.equal(afterSnapshots, beforeSnapshots);
  const alice = db.prepare('SELECT * FROM users WHERE username = ?').get('alice');
  assert.equal(alice.usedMB, 3);
  assert.equal(alice.lastSeen, '2026-06-15T12:00:00.000Z');
  assert.equal(alice.updatedAt, '2026-01-01T00:00:00.000Z');
  assert.equal(alice.password, 'secret');
  assert.equal(alice.expiry, '2030-01-01T00:00:00.000Z');
  assert.equal(alice.enabled, 1);
});

test('legacy updater is throttled and does not run four batches in one minute', () => {
  const db = makeDb();
  let now = 0;
  const updater = createLegacyMieruCompatibilityUpdater({
    db,
    getAllUsers: () => db.prepare('SELECT * FROM users ORDER BY username').all(),
    historyCutoffIso: () => '2020-01-01T00:00:00.000Z',
    nowMs: () => now
  });

  const applyRow = () => updater.apply([{
    protocol_username: 'alice',
    upload_bytes: 1048576,
    download_bytes: 0,
    last_seen_at: `2026-06-15T12:00:${String(now / 1000).padStart(2, '0')}.000Z`
  }], '2026-06-15T12:00:00.000Z');

  const first = applyRow();
  now = 15000;
  const second = applyRow();
  now = 30000;
  const third = applyRow();
  now = 45000;
  const fourth = applyRow();

  assert.equal(first.throttled, false);
  assert.equal(second.throttled, true);
  assert.equal(third.throttled, true);
  assert.equal(fourth.throttled, true);
});

test('legacy updater performs bounded cleanup cadence', () => {
  const db = makeDb();
  db.prepare(`INSERT INTO traffic_snapshots (username, uploadMB, downloadMB, ts) VALUES ('alice', 1, 1, '2019-01-01T00:00:00.000Z')`).run();
  let now = 0;
  const updater = createLegacyMieruCompatibilityUpdater({
    db,
    getAllUsers: () => db.prepare('SELECT * FROM users ORDER BY username').all(),
    historyCutoffIso: () => '2020-01-01T00:00:00.000Z',
    nowMs: () => now
  });

  updater.apply([], '2026-06-15T12:00:00.000Z');
  assert.equal(db.prepare('SELECT COUNT(*) AS count FROM traffic_snapshots').get().count, 0);

  db.prepare(`INSERT INTO traffic_snapshots (username, uploadMB, downloadMB, ts) VALUES ('alice', 1, 1, '2019-01-01T00:00:00.000Z')`).run();
  now = 1000;
  updater.apply([], '2026-06-15T12:00:01.000Z');
  assert.equal(db.prepare('SELECT COUNT(*) AS count FROM traffic_snapshots').get().count, 1);

  now = 3600001;
  updater.apply([], '2026-06-15T13:00:01.000Z');
  assert.equal(db.prepare('SELECT COUNT(*) AS count FROM traffic_snapshots').get().count, 0);
});

test('legacy updater applies user telemetry updates in one transaction', () => {
  const db = makeDb();
  db.exec(`
    CREATE TRIGGER users_block_bob
    BEFORE UPDATE ON users
    WHEN NEW.username = 'bob'
    BEGIN
      SELECT RAISE(ABORT, 'blocked');
    END;
  `);
  const updater = createLegacyMieruCompatibilityUpdater({
    db,
    getAllUsers: () => db.prepare('SELECT * FROM users ORDER BY username').all(),
    historyCutoffIso: () => '2020-01-01T00:00:00.000Z',
    nowMs: () => 1000
  });

  assert.throws(() => updater.apply([
    { protocol_username: 'alice', upload_bytes: 1048576, download_bytes: 0, last_seen_at: '2026-06-15T12:00:00.000Z' },
    { protocol_username: 'bob', upload_bytes: 1048576, download_bytes: 0, last_seen_at: '2026-06-15T12:00:00.000Z' }
  ], '2026-06-15T12:00:00.000Z'), /blocked/);

  const alice = db.prepare('SELECT * FROM users WHERE username = ?').get('alice');
  assert.equal(alice.usedMB, 1);
  assert.equal(alice.lastSeen, '2026-01-01T00:00:00.000Z');
});

test('buildMieruUserStatsResponse uses the cached snapshot and is safe before first collection', () => {
  const payload = buildMieruUserStatsResponse({
    getAllUsers: () => [{
      username: 'alice',
      email: 'a@example.com',
      expiry: '2030-01-01T00:00:00.000Z',
      protocols: '[]',
      quotaMB: 100,
      usedMB: 2,
      lastSeen: '2026-01-01T00:00:00.000Z'
    }],
    attachTrafficToUserPayload(input, { mieruTraffic }) {
      return { ...input, usedMB: mieruTraffic.usedMB ?? input.usedMB, lastSeen: mieruTraffic.lastSeen ?? input.lastSeen };
    },
    telemetryService: {
      getLatestMieruSnapshot() {
        return { rows: [], collected_at: null, collector_status: 'unavailable', stale: false };
      }
    }
  });

  assert.equal(payload.length, 1);
  assert.equal(payload[0].usedMB, 2);
  assert.equal(payload[0].lastSeen, '2026-01-01T00:00:00.000Z');
});
