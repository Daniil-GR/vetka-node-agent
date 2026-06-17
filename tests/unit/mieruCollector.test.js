'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  parseSizeToBytes,
  parseMitaUsersTable,
  collectMieruTelemetry
} = require('../../panel/server/telemetry/mieruCollector');

test('parseSizeToBytes supports IEC and decimal units', () => {
  assert.equal(parseSizeToBytes('1B'), 1);
  assert.equal(parseSizeToBytes('1KiB'), 1024);
  assert.equal(parseSizeToBytes('1MiB'), 1024 * 1024);
  assert.equal(parseSizeToBytes('1GiB'), 1024 * 1024 * 1024);
  assert.equal(parseSizeToBytes('1KB'), 1000);
  assert.equal(parseSizeToBytes('1MB'), 1000 * 1000);
});

test('parseMitaUsersTable parses the current mita get users table shape', () => {
  const parsed = parseMitaUsersTable([
    'User LastActive 1DayDownload 1DayUpload 30DaysDownload 30DaysUpload',
    'u_example 2026-06-15T12:04:30Z 1MiB 2MiB 3MiB 4MiB'
  ].join('\n'), '2026-06-15T12:05:00.000Z');

  assert.equal(parsed.rows.length, 1);
  assert.equal(parsed.rows[0].protocol_username, 'u_example');
  assert.equal(parsed.rows[0].client_ip, null);
  assert.equal(parsed.rows[0].ip_observed, false);
  assert.equal(parsed.rows[0].download_bytes, 3 * 1024 * 1024);
  assert.equal(parsed.rows[0].upload_bytes, 4 * 1024 * 1024);
});

test('parseMitaUsersTable ignores invalid LastActive instead of inventing activity', () => {
  const parsed = parseMitaUsersTable('u_example not-a-date 1MiB 2MiB 3MiB 4MiB', '2026-06-15T12:05:00.000Z');
  assert.equal(parsed.rows.length, 0);
  assert.equal(parsed.invalidLastActiveRows, 1);
});

test('collectMieruTelemetry reports partial status when LastActive is invalid', async () => {
  const result = await collectMieruTelemetry({
    nowIso: '2026-06-15T12:05:00.000Z',
    async runCommand() {
      return 'u_example not-a-date 1MiB 2MiB 3MiB 4MiB';
    }
  });

  assert.equal(result.status, 'partial');
  assert.equal(result.rows.length, 0);
  assert.equal(result.details.invalid_last_active_rows, 1);
  assert.equal(result.usableResult, false);
  assert.equal(result.lastSuccessfulCollectionAt, null);
});

test('collectMieruTelemetry treats header-only output as a successful empty result', async () => {
  const result = await collectMieruTelemetry({
    nowIso: '2026-06-15T12:05:00.000Z',
    async runCommand() {
      return 'User LastActive 1DayDownload 1DayUpload 30DaysDownload 30DaysUpload\n';
    }
  });

  assert.equal(result.status, 'ok');
  assert.equal(result.rows.length, 0);
  assert.equal(result.usableResult, true);
  assert.equal(result.lastSuccessfulCollectionAt, '2026-06-15T12:05:00.000Z');
});

test('collectMieruTelemetry keeps successful timestamp when at least one row is usable', async () => {
  const result = await collectMieruTelemetry({
    nowIso: '2026-06-15T12:05:00.000Z',
    async runCommand() {
      return [
        'User LastActive 1DayDownload 1DayUpload 30DaysDownload 30DaysUpload',
        'u_valid 2026-06-15T12:04:30Z 1MiB 2MiB 3MiB 4MiB',
        'u_invalid not-a-date 1MiB 2MiB 3MiB 4MiB'
      ].join('\n');
    }
  });

  assert.equal(result.status, 'partial');
  assert.equal(result.rows.length, 1);
  assert.equal(result.usableResult, true);
  assert.equal(result.lastSuccessfulCollectionAt, '2026-06-15T12:05:00.000Z');
});

test('collectMieruTelemetry reports unavailable command failures safely', async () => {
  const result = await collectMieruTelemetry({
    nowIso: '2026-06-15T12:05:00.000Z',
    async runCommand() {
      throw new Error('boom');
    }
  });

  assert.equal(result.status, 'unavailable');
  assert.equal(result.rows.length, 0);
  assert.match(result.warnings[0], /temporarily unavailable/i);
});
