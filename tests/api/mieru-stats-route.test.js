'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');

const { panelRequire } = require('../helpers/panel-require');
const express = panelRequire('express');

const { buildMieruUserStatsResponse } = require('../../panel/server/mieruStats');

async function startServer(app) {
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  return {
    server,
    url: `http://127.0.0.1:${address.port}`
  };
}

test('concurrent /api/stats/users requests use cached snapshot and do not launch a command', async () => {
  const app = express();
  let snapshotCalls = 0;
  app.get('/api/stats/users', (_req, res) => {
    res.json(buildMieruUserStatsResponse({
      getAllUsers: () => [{
        username: 'alice',
        email: 'a@example.com',
        expiry: '2030-01-01T00:00:00.000Z',
        protocols: '[]',
        quotaMB: 100,
        usedMB: 1,
        lastSeen: '2026-01-01T00:00:00.000Z'
      }],
      attachTrafficToUserPayload(input, { mieruTraffic }) {
        return { ...input, usedMB: mieruTraffic.usedMB ?? input.usedMB, lastSeen: mieruTraffic.lastSeen ?? input.lastSeen };
      },
      telemetryService: {
        getLatestMieruSnapshot() {
          snapshotCalls += 1;
          return {
            rows: [{
              protocol_username: 'alice',
              upload_bytes: 1048576,
              download_bytes: 2097152,
              last_seen_at: '2026-06-15T12:00:00.000Z'
            }],
            collected_at: '2026-06-15T12:00:00.000Z',
            collector_status: 'ok',
            stale: false
          };
        }
      }
    }));
  });

  const { server, url } = await startServer(app);
  try {
    const [a, b, c] = await Promise.all([
      fetch(`${url}/api/stats/users`),
      fetch(`${url}/api/stats/users`),
      fetch(`${url}/api/stats/users`)
    ]);
    const bodies = await Promise.all([a.json(), b.json(), c.json()]);
    assert.equal(snapshotCalls, 3);
    for (const body of bodies) {
      assert.equal(body[0].usedMB, 3);
      assert.equal(body[0].lastSeen, '2026-06-15T12:00:00.000Z');
    }
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
