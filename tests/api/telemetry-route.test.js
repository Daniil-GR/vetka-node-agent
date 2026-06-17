'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');

const { panelRequire } = require('../helpers/panel-require');
const express = panelRequire('express');
const Database = panelRequire('better-sqlite3');

const storage = require('../../panel/server/telemetry/storage');
const { createTelemetryService } = require('../../panel/server/telemetry/service');
const {
  authorizeNodeRequest,
  createTelemetryRouteHandler
} = require('../../panel/server/telemetry/http');

function makeApp(cfg, db) {
  const app = express();
  const telemetryService = createTelemetryService({
    db,
    cfg,
    getAllUsers: () => [{ id: 'u-1', username: 'alice' }],
    logger: { warn() {} }
  });

  app.get('/v1/telemetry/sessions', (req, res, next) => {
    const auth = authorizeNodeRequest(req, cfg);
    if (!auth.ok) return res.status(auth.status).json(auth.payload);
    next();
  }, createTelemetryRouteHandler(telemetryService));

  return { app, telemetryService };
}

async function startServer(app) {
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  return {
    server,
    url: `http://127.0.0.1:${address.port}`
  };
}

function seedTelemetry(db) {
  const now = Date.now();
  const activeIso = new Date(now - 2 * 60 * 1000).toISOString();
  const recentIso = new Date(now - 20 * 60 * 1000).toISOString();
  storage.initTelemetryTables(db);
  storage.upsertNaiveObservation(db, {
    protocol_username: 'alice',
    client_ip: '198.51.100.1',
    first_seen_at: activeIso,
    last_seen_at: activeIso,
    upload_bytes: 10,
    download_bytes: 20,
    source: 'naive-audit',
    traffic_scope: 'telemetry-retention-window',
    ip_observed: true,
    traffic_observed: true
  });
  storage.upsertNaiveObservation(db, {
    protocol_username: 'alice',
    client_ip: '198.51.100.2',
    first_seen_at: recentIso,
    last_seen_at: recentIso,
    upload_bytes: 1,
    download_bytes: 2,
    source: 'naive-audit',
    traffic_scope: 'telemetry-retention-window',
    ip_observed: true,
    traffic_observed: true
  });
  storage.updateCollectorState(db, {
    collector: 'telemetry',
    status: 'ok',
    warnings: [],
    details: {
      protocol_type: 'naive',
      components: {
        auth: { available: true, status: 'ok' },
        traffic: { available: true, status: 'ok' }
      }
    },
    last_successful_collection_at: '2026-06-15T10:10:00.000Z',
    last_attempted_collection_at: '2026-06-15T10:10:00.000Z',
    last_error: null
  });
}

async function requestJson(url, options = {}) {
  const response = await fetch(url, options);
  const body = await response.json();
  return { response, body };
}

test('telemetry route returns active sessions by default and recent sessions when requested', async () => {
  const db = new Database(':memory:');
  seedTelemetry(db);
  const cfg = {
    nodeSecret: 'secret',
    nodeId: 'node-1',
    protocolType: 'naive',
    telemetryEnabled: true,
    sessionTtlMinutes: 10,
    ipHistoryTtlHours: 24,
    telemetryCollectIntervalSeconds: 15,
    backendAllowedIps: ['127.0.0.1'],
    allowAnyBackendIp: false
  };
  const { app } = makeApp(cfg, db);
  const { server, url } = await startServer(app);

  try {
    const headers = {
      authorization: 'Bearer secret',
      'x-node-id': 'node-1'
    };
    const activeOnly = await requestJson(`${url}/v1/telemetry/sessions`, { headers });
    assert.equal(activeOnly.response.status, 200);
    assert.equal(activeOnly.body.sessions.length, 1);
    assert.equal(activeOnly.body.sessions[0].client_ip, '198.51.100.1');
    assert.equal('nodeSecret' in activeOnly.body, false);
    assert.match(activeOnly.body.generated_at, /^\d{4}-\d{2}-\d{2}T/);

    const withRecent = await requestJson(`${url}/v1/telemetry/sessions?include_recent=true`, { headers });
    assert.equal(withRecent.body.sessions.length, 2);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('telemetry route enforces secret, IP allowlist, and node id checks', async () => {
  const db = new Database(':memory:');
  seedTelemetry(db);
  const cfg = {
    nodeSecret: 'secret',
    nodeId: 'node-1',
    protocolType: 'naive',
    telemetryEnabled: true,
    sessionTtlMinutes: 10,
    ipHistoryTtlHours: 24,
    telemetryCollectIntervalSeconds: 15,
    backendAllowedIps: ['127.0.0.1'],
    allowAnyBackendIp: false
  };
  const { app } = makeApp(cfg, db);
  const { server, url } = await startServer(app);

  try {
    const wrongSecret = await requestJson(`${url}/v1/telemetry/sessions`, {
      headers: { authorization: 'Bearer wrong' }
    });
    assert.equal(wrongSecret.response.status, 401);

    const wrongNode = await requestJson(`${url}/v1/telemetry/sessions`, {
      headers: { authorization: 'Bearer secret', 'x-node-id': 'node-2' }
    });
    assert.equal(wrongNode.response.status, 403);

    const ipDeniedCfg = { ...cfg, backendAllowedIps: ['203.0.113.1'] };
    const denied = makeApp(ipDeniedCfg, db);
    const deniedServer = await startServer(denied.app);
    try {
      const wrongIp = await requestJson(`${deniedServer.url}/v1/telemetry/sessions`, {
        headers: { authorization: 'Bearer secret', 'x-node-id': 'node-1' }
      });
      assert.equal(wrongIp.response.status, 403);
    } finally {
      await new Promise((resolve) => deniedServer.server.close(resolve));
    }
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('telemetry route returns safe JSON when telemetry storage reads fail', async () => {
  const db = new Database(':memory:');
  seedTelemetry(db);
  const originalList = storage.listTelemetrySessions;
  storage.listTelemetrySessions = () => {
    throw new Error('list failed');
  };
  const cfg = {
    nodeSecret: 'secret',
    nodeId: 'node-1',
    protocolType: 'naive',
    telemetryEnabled: true,
    sessionTtlMinutes: 10,
    ipHistoryTtlHours: 24,
    telemetryCollectIntervalSeconds: 15,
    backendAllowedIps: ['127.0.0.1'],
    allowAnyBackendIp: false
  };
  const { app } = makeApp(cfg, db);
  const { server, url } = await startServer(app);

  try {
    const result = await requestJson(`${url}/v1/telemetry/sessions`, {
      headers: { authorization: 'Bearer secret', 'x-node-id': 'node-1' }
    });
    assert.equal(result.response.status, 200);
    assert.equal(result.body.collector_status, 'unavailable');
    assert.deepEqual(result.body.sessions, []);
  } finally {
    storage.listTelemetrySessions = originalList;
    await new Promise((resolve) => server.close(resolve));
  }
});
