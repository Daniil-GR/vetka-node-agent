'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');

const { panelRequire } = require('../helpers/panel-require');
const Database = panelRequire('better-sqlite3');

const storage = require('../../panel/server/telemetry/storage');
const { createTelemetryService } = require('../../panel/server/telemetry/service');

async function makeTempFile(name, content) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'vetka-service-'));
  const file = path.join(dir, name);
  await fs.writeFile(file, content);
  return file;
}

function makeDb() {
  const db = new Database(':memory:');
  storage.initTelemetryTables(db);
  return db;
}

function minutesAgoIso(baseNowMs, minutes) {
  return new Date(baseNowMs - minutes * 60 * 1000).toISOString();
}

function secondsAgoIso(baseNowMs, seconds) {
  return new Date(baseNowMs - seconds * 1000).toISOString();
}

function makeNaiveService(db, authLog, trafficLog, overrides = {}) {
  const cfg = {
    protocolType: 'naive',
    telemetryEnabled: true,
    telemetryCollectIntervalSeconds: 15,
    sessionTtlMinutes: 10,
    ipHistoryTtlHours: 24,
    nodeId: 'node-1',
    ...overrides.cfg
  };
  return createTelemetryService({
    db,
    cfg,
    getAllUsers: overrides.getAllUsers || (() => [{ id: 'u-1', username: 'alice' }]),
    normalizeAuditIp: (value) => String(value || '').replace(/^::ffff:/, ''),
    authAuditLogPath: () => authLog,
    trafficAuditLogPath: () => trafficLog,
    logger: overrides.logger || { warn() {} },
    runMitaUsersCommand: overrides.runMitaUsersCommand,
    onMieruRowsCollected: overrides.onMieruRowsCollected
  });
}

test('service collects naive telemetry successfully and keeps cached sessions queryable', async () => {
  const baseNowMs = Date.now();
  const authLog = await makeTempFile('auth.log', JSON.stringify({
    ts: minutesAgoIso(baseNowMs, 2),
    username: 'alice',
    remote_ip: '::ffff:198.51.100.1'
  }) + '\n');
  const trafficLog = await makeTempFile('traffic.log', JSON.stringify({
    ts: minutesAgoIso(baseNowMs, 1),
    event: 'connect_closed',
    username: 'alice',
    remote_ip: '198.51.100.1',
    bytes_client_to_target: 12,
    bytes_target_to_client: 34
  }) + '\n');
  const db = makeDb();
  const service = makeNaiveService(db, authLog, trafficLog);

  await service.collectOnce();

  const state = service.currentCollectorState();
  assert.equal(state.status, 'ok');
  const response = service.buildSessionsResponse();
  assert.equal(response.sessions.length, 1);
  assert.equal(response.sessions[0].upload_bytes, 12);
  assert.equal(response.sessions[0].download_bytes, 34);
});

test('service rolls back checkpoint and observations when an upsert fails mid-batch', async () => {
  const baseNowMs = Date.now();
  const authLog = await makeTempFile('auth.log', [
    JSON.stringify({ ts: minutesAgoIso(baseNowMs, 2), username: 'alice', remote_ip: '198.51.100.1' }),
    JSON.stringify({ ts: secondsAgoIso(baseNowMs, 90), username: 'bob', remote_ip: '198.51.100.2' })
  ].join('\n') + '\n');
  const trafficLog = await makeTempFile('traffic.log', '');
  const db = makeDb();
  const originalUpsert = storage.upsertNaiveObservation;
  let upsertCalls = 0;
  storage.upsertNaiveObservation = (innerDb, observation) => {
    upsertCalls += 1;
    if (observation.protocol_username === 'bob') throw new Error('forced upsert failure');
    originalUpsert(innerDb, observation);
  };

  try {
    const service = makeNaiveService(db, authLog, trafficLog);
    await service.collectOnce();

    const state = service.currentCollectorState();
    assert.equal(state.status, 'unavailable');
    const checkpoint = storage.loadCheckpoint(db, authLog);
    assert.equal(checkpoint.offset, 0);
    const count = db.prepare('SELECT COUNT(*) AS count FROM telemetry_sessions').get().count;
    assert.equal(count, 0);

    storage.upsertNaiveObservation = originalUpsert;
    await service.collectOnce();

    const successState = service.currentCollectorState();
    assert.equal(successState.status, 'ok');
    const replayed = db.prepare('SELECT protocol_username FROM telemetry_sessions ORDER BY protocol_username').all().map((row) => row.protocol_username);
    assert.deepEqual(replayed, ['alice', 'bob']);
    assert.equal(upsertCalls, 2);
  } finally {
    storage.upsertNaiveObservation = originalUpsert;
  }
});

test('service preserves last_successful_collection_at across a later unavailable iteration', async () => {
  const baseNowMs = Date.now();
  const authLog = await makeTempFile('auth.log', JSON.stringify({
    ts: minutesAgoIso(baseNowMs, 1),
    username: 'alice',
    remote_ip: '198.51.100.1'
  }) + '\n');
  const trafficLog = await makeTempFile('traffic.log', '');
  const db = makeDb();
  const service = makeNaiveService(db, authLog, trafficLog);

  await service.collectOnce();
  const firstState = service.currentCollectorState();
  await fs.unlink(authLog);
  await fs.unlink(trafficLog);
  await service.collectOnce();
  const secondState = service.currentCollectorState();

  assert.equal(secondState.status, 'unavailable');
  assert.equal(secondState.last_successful_collection_at, firstState.last_successful_collection_at);
});

test('service does not create false mieru activity when LastActive is invalid', async () => {
  const db = makeDb();
  const service = createTelemetryService({
    db,
    cfg: {
      protocolType: 'mieru',
      telemetryEnabled: true,
      telemetryCollectIntervalSeconds: 15,
      sessionTtlMinutes: 10,
      ipHistoryTtlHours: 24,
      nodeId: 'node-1'
    },
    getAllUsers: () => [{ id: 'm-1', username: 'u_mieru' }],
    runMitaUsersCommand: async () => 'u_mieru not-a-date 1MiB 2MiB 3MiB 4MiB',
    logger: { warn() {} }
  });

  await service.collectOnce();

  const state = service.currentCollectorState();
  assert.equal(state.status, 'partial');
  const response = service.buildSessionsResponse({ includeRecent: true });
  assert.equal(response.sessions.length, 0);
});

test('service preserves previous successful timestamp when mieru output is fully invalid', async () => {
  const db = makeDb();
  const service = createTelemetryService({
    db,
    cfg: {
      protocolType: 'mieru',
      telemetryEnabled: true,
      telemetryCollectIntervalSeconds: 15,
      sessionTtlMinutes: 10,
      ipHistoryTtlHours: 24,
      nodeId: 'node-1'
    },
    getAllUsers: () => [],
    runMitaUsersCommand: async () => 'User LastActive 1DayDownload 1DayUpload 30DaysDownload 30DaysUpload\nu_bad not-a-date 1MiB 2MiB 3MiB 4MiB',
    logger: { warn() {} }
  });

  storage.updateCollectorState(db, {
    collector: 'telemetry',
    status: 'ok',
    warnings: [],
    details: { protocol_type: 'mieru', components: {} },
    last_successful_collection_at: '2026-06-15T09:00:00.000Z',
    last_attempted_collection_at: '2026-06-15T09:00:00.000Z',
    last_error: null
  });

  await service.collectOnce();
  const state = service.currentCollectorState();
  assert.equal(state.status, 'partial');
  assert.equal(state.last_successful_collection_at, '2026-06-15T09:00:00.000Z');
});

test('service returns cached sessions even when collector later degrades', async () => {
  const baseNowMs = Date.now();
  const authLog = await makeTempFile('auth.log', JSON.stringify({
    ts: minutesAgoIso(baseNowMs, 1),
    username: 'alice',
    remote_ip: '198.51.100.1'
  }) + '\n');
  const trafficLog = await makeTempFile('traffic.log', '');
  const db = makeDb();
  const service = makeNaiveService(db, authLog, trafficLog);

  await service.collectOnce();
  await fs.unlink(authLog);
  await service.collectOnce();

  const response = service.buildSessionsResponse({ includeRecent: true });
  assert.equal(response.sessions.length, 1);
  assert.equal(response.collector_status, 'partial');
});

test('service exposes disabled status without collecting when telemetry is disabled', async () => {
  const db = makeDb();
  const service = createTelemetryService({
    db,
    cfg: {
      protocolType: 'naive',
      telemetryEnabled: false,
      telemetryCollectIntervalSeconds: 15,
      sessionTtlMinutes: 10,
      ipHistoryTtlHours: 24,
      nodeId: 'node-1'
    },
    authAuditLogPath: () => '/missing-auth.log',
    trafficAuditLogPath: () => '/missing-traffic.log',
    logger: { warn() {} }
  });

  await service.collectOnce();
  const state = service.currentCollectorState();
  assert.equal(state.status, 'disabled');
});

test('service prevents overlapping collections and launches at most one mita get users per iteration', async () => {
  const db = makeDb();
  let calls = 0;
  const service = createTelemetryService({
    db,
    cfg: {
      protocolType: 'mieru',
      telemetryEnabled: true,
      telemetryCollectIntervalSeconds: 15,
      sessionTtlMinutes: 10,
      ipHistoryTtlHours: 24,
      nodeId: 'node-1'
    },
    getAllUsers: () => [],
    runMitaUsersCommand: async () => {
      calls += 1;
      await new Promise((resolve) => setTimeout(resolve, 40));
      return '';
    },
    logger: { warn() {} }
  });

  await Promise.all([service.collectOnce(), service.collectOnce(), service.collectOnce()]);
  assert.equal(calls, 1);
});

test('service updates legacy mieru compatibility cache from the shared collector result', async () => {
  const db = makeDb();
  let callbackCalls = 0;
  const service = createTelemetryService({
    db,
    cfg: {
      protocolType: 'mieru',
      telemetryEnabled: true,
      telemetryCollectIntervalSeconds: 15,
      sessionTtlMinutes: 10,
      ipHistoryTtlHours: 24,
      nodeId: 'node-1'
    },
    getAllUsers: () => [],
    runMitaUsersCommand: async () => 'u_example 2026-06-15T12:04:30Z 1MiB 2MiB 3MiB 4MiB',
    onMieruRowsCollected({ rows, usableResult }) {
      callbackCalls += 1;
      assert.equal(usableResult, true);
      assert.equal(rows.length, 1);
    },
    logger: { warn() {} }
  });

  await service.collectOnce();
  assert.equal(callbackCalls, 1);
});

test('service keeps the last usable mieru snapshot when a later collection is unavailable', async () => {
  const db = makeDb();
  let fail = false;
  const service = createTelemetryService({
    db,
    cfg: {
      protocolType: 'mieru',
      telemetryEnabled: true,
      telemetryCollectIntervalSeconds: 15,
      sessionTtlMinutes: 10,
      ipHistoryTtlHours: 24,
      nodeId: 'node-1'
    },
    getAllUsers: () => [],
    runMitaUsersCommand: async () => {
      if (fail) throw new Error('boom');
      return 'u_example 2026-06-15T12:04:30Z 1MiB 2MiB 3MiB 4MiB';
    },
    logger: { warn() {} }
  });

  await service.collectOnce();
  fail = true;
  await service.collectOnce();

  const snapshot = service.getLatestMieruSnapshot();
  assert.equal(snapshot.rows.length, 1);
  assert.equal(snapshot.collector_status, 'unavailable');
  assert.equal(snapshot.stale, true);
});

test('service contains unexpected collector exceptions and keeps responding', async () => {
  const db = makeDb();
  const warnings = [];
  const originalPrune = storage.pruneExpiredTelemetry;
  storage.pruneExpiredTelemetry = () => {
    throw new RangeError('timestamp blew up');
  };
  try {
    const authLog = await makeTempFile('auth.log', JSON.stringify({
      ts: '2026-06-15T10:00:00.000Z',
      username: 'alice',
      remote_ip: '198.51.100.1'
    }) + '\n');
    const trafficLog = await makeTempFile('traffic.log', '');
    const service = makeNaiveService(db, authLog, trafficLog, {
      logger: {
        warn(message) {
          warnings.push(message);
        }
      }
    });

    await assert.doesNotReject(() => service.collectOnce());
    const state = service.currentCollectorState();
    assert.equal(state.status, 'unavailable');
    assert.ok(warnings.length > 0);
    assert.equal(service.buildSessionsResponse().ok, true);
  } finally {
    storage.pruneExpiredTelemetry = originalPrune;
  }
});

test('service survives storage init failure and still returns a safe unavailable response', () => {
  const originalInit = storage.initTelemetryTables;
  storage.initTelemetryTables = () => {
    throw new Error('init failed');
  };
  try {
    const service = createTelemetryService({
      db: {},
      cfg: {
        protocolType: 'naive',
        telemetryEnabled: true,
        telemetryCollectIntervalSeconds: 15,
        sessionTtlMinutes: 10,
        ipHistoryTtlHours: 24,
        nodeId: 'node-1'
      },
      logger: { warn() {} }
    });
    const response = service.buildSessionsResponse();
    assert.equal(service.isStorageReady(), false);
    assert.equal(response.collector_status, 'unavailable');
    assert.deepEqual(response.sessions, []);
  } finally {
    storage.initTelemetryTables = originalInit;
  }
});

test('service survives getCollectorState and updateCollectorState failures', async () => {
  const db = makeDb();
  const originalGet = storage.getCollectorState;
  const originalUpdate = storage.updateCollectorState;
  storage.getCollectorState = () => {
    throw new Error('state read failed');
  };
  storage.updateCollectorState = () => {
    throw new Error('state write failed');
  };
  try {
    const service = createTelemetryService({
      db,
      cfg: {
        protocolType: 'mieru',
        telemetryEnabled: true,
        telemetryCollectIntervalSeconds: 15,
        sessionTtlMinutes: 10,
        ipHistoryTtlHours: 24,
        nodeId: 'node-1'
      },
      getAllUsers: () => [],
      runMitaUsersCommand: async () => { throw new Error('boom'); },
      logger: { warn() {} }
    });

    await assert.doesNotReject(() => service.collectOnce());
    assert.equal(service.buildSessionsResponse().ok, true);
  } finally {
    storage.getCollectorState = originalGet;
    storage.updateCollectorState = originalUpdate;
  }
});

test('service buildSessionsResponse returns safe JSON when telemetry table reads fail', () => {
  const db = makeDb();
  const originalList = storage.listTelemetrySessions;
  storage.listTelemetrySessions = () => {
    throw new Error('list failed');
  };
  try {
    const service = makeNaiveService(db, '/missing-auth.log', '/missing-traffic.log', {
      getAllUsers: () => []
    });
    const response = service.buildSessionsResponse({ includeRecent: true });
    assert.equal(response.collector_status, 'unavailable');
    assert.deepEqual(response.sessions, []);
    assert.ok(response.warnings.some((warning) => /temporarily unavailable/i.test(warning)));
  } finally {
    storage.listTelemetrySessions = originalList;
  }
});

test('service tolerates logger failures while handling collector failures', async () => {
  const db = makeDb();
  const originalPrune = storage.pruneExpiredTelemetry;
  storage.pruneExpiredTelemetry = () => {
    throw new Error('prune failed');
  };
  try {
    const service = createTelemetryService({
      db,
      cfg: {
        protocolType: 'naive',
        telemetryEnabled: true,
        telemetryCollectIntervalSeconds: 15,
        sessionTtlMinutes: 10,
        ipHistoryTtlHours: 24,
        nodeId: 'node-1'
      },
      authAuditLogPath: () => '/missing-auth.log',
      trafficAuditLogPath: () => '/missing-traffic.log',
      logger: {
        warn() {
          throw new Error('logger failed');
        }
      }
    });

    await assert.doesNotReject(() => service.collectOnce());
  } finally {
    storage.pruneExpiredTelemetry = originalPrune;
  }
});

test('service buildSessionsResponse applies the hard limit and warning', () => {
  const db = makeDb();
  for (let i = 0; i < 5002; i += 1) {
    storage.upsertNaiveObservation(db, {
      protocol_username: `user-${i}`,
      client_ip: `198.51.100.${i % 250}`,
      first_seen_at: '2099-06-15T10:00:00.000Z',
      last_seen_at: '2099-06-15T10:00:00.000Z',
      upload_bytes: 1,
      download_bytes: 1
    });
  }
  storage.updateCollectorState(db, {
    collector: 'telemetry',
    status: 'ok',
    warnings: [],
    details: { protocol_type: 'naive', components: {} },
    last_successful_collection_at: '2026-06-15T10:00:00.000Z',
    last_attempted_collection_at: '2026-06-15T10:00:00.000Z',
    last_error: null
  });
  const service = makeNaiveService(db, '/missing-auth.log', '/missing-traffic.log', {
    getAllUsers: () => []
  });

  const response = service.buildSessionsResponse({ includeRecent: true });
  assert.equal(response.sessions.length, 5000);
  assert.ok(response.warnings.some((warning) => /truncated/i.test(warning)));
});
