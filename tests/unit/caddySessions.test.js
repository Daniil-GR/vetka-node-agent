'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { normalizeAuditIp } = require('../../panel/server/ip');
const { parseNaiveAuthEvent } = require('../../panel/server/telemetry/naiveCollector');
const { parseLegacyCaddySessionRecord, collectLegacyCaddySessionsFromContent } = require('../../panel/server/caddySessions');

function makeLegacyLine(remote, extra = {}) {
  return JSON.stringify({
    ts: '2026-06-15T12:00:00.000Z',
    request: {
      method: 'CONNECT',
      remote_ip: remote,
      host: 'example.com:443',
      uri: 'example.com:443'
    },
    ...extra
  });
}

function makeTelemetryLine(remote) {
  return JSON.stringify({
    ts: '2026-06-15T12:00:00.000Z',
    username: 'alice',
    remote_ip: remote
  });
}

test('legacy Caddy parser normalizes IPv4 and IPv6 variants and rejects invalid IPs', () => {
  const cases = [
    ['192.0.2.1', '192.0.2.1'],
    ['192.0.2.1:1234', '192.0.2.1'],
    ['::ffff:192.0.2.1', '192.0.2.1'],
    ['2001:db8::1', '2001:db8::1'],
    ['[2001:db8::1]:443', '2001:db8::1'],
    ['::1', '::1'],
    ['invalid', null]
  ];

  for (const [input, expected] of cases) {
    const parsed = parseLegacyCaddySessionRecord(makeLegacyLine(input), { normalizeAuditIp });
    if (expected === null) {
      assert.equal(parsed, null);
    } else {
      assert.equal(parsed.remoteIp, expected);
    }
  }
});

test('legacy Caddy parser and telemetry parser normalize the same client IPs the same way', () => {
  const cases = [
    '192.0.2.1',
    '192.0.2.1:1234',
    '::ffff:192.0.2.1',
    '2001:db8::1',
    '[2001:db8::1]:443',
    '::1',
    'invalid'
  ];

  for (const input of cases) {
    const legacy = parseLegacyCaddySessionRecord(makeLegacyLine(input), { normalizeAuditIp });
    const telemetry = parseNaiveAuthEvent(makeTelemetryLine(input), normalizeAuditIp);
    assert.equal(legacy?.remoteIp || null, telemetry?.client_ip || null);
  }
});

test('legacy Caddy parser aggregates sessions and drops invalid rows from the explorer path', () => {
  const sessions = collectLegacyCaddySessionsFromContent([
    makeLegacyLine('192.0.2.1'),
    makeLegacyLine('192.0.2.1:1234'),
    makeLegacyLine('invalid'),
    JSON.stringify({ ts: '2026-06-15T12:01:00.000Z', request: { method: 'GET', remote_ip: '198.51.100.1' } })
  ].join('\n'), { normalizeAuditIp });

  assert.equal(sessions.length, 1);
  assert.equal(sessions[0].remoteIp, '192.0.2.1');
  assert.equal(sessions[0].requestCount, 2);
});
