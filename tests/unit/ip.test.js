'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { normalizeAuditIp } = require('../../panel/server/ip');

test('normalizeAuditIp keeps valid IPv4 and strips IPv4 port', () => {
  assert.equal(normalizeAuditIp('192.0.2.1'), '192.0.2.1');
  assert.equal(normalizeAuditIp('192.0.2.1:1234'), '192.0.2.1');
  assert.equal(normalizeAuditIp('::ffff:192.0.2.1'), '192.0.2.1');
});

test('normalizeAuditIp keeps bare IPv6 intact and supports bracketed IPv6 with port', () => {
  assert.equal(normalizeAuditIp('2001:db8::1'), '2001:db8::1');
  assert.equal(normalizeAuditIp('2001:db8::1234'), '2001:db8::1234');
  assert.equal(normalizeAuditIp('[2001:db8::1]:443'), '2001:db8::1');
  assert.equal(normalizeAuditIp('::1'), '::1');
});

test('normalizeAuditIp rejects invalid values', () => {
  assert.equal(normalizeAuditIp('invalid'), '');
  assert.equal(normalizeAuditIp('example.com:443'), '');
});
