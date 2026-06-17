'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fsp = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');

const {
  readJsonlIncremental,
  parseNaiveAuthEvent,
  parseNaiveTrafficEvent,
  parseTimestamp
} = require('../../panel/server/telemetry/naiveCollector');

function normalizeAuditIp(value) {
  return String(value || '').trim().replace(/^::ffff:/, '');
}

async function makeTempDir(prefix = 'vetka-naive-') {
  return fsp.mkdtemp(path.join(os.tmpdir(), prefix));
}

async function makeTempFile(name, content) {
  const dir = await makeTempDir();
  const file = path.join(dir, name);
  await fsp.writeFile(file, content);
  return file;
}

test('parseNaiveAuthEvent creates an observation from auth audit JSON', () => {
  const row = parseNaiveAuthEvent(JSON.stringify({
    ts: '2026-06-15T12:00:00.000Z',
    username: 'u_example',
    remote_ip: '::ffff:45.15.112.21',
    host: 'example.com:443'
  }), normalizeAuditIp);

  assert.equal(row.protocol_username, 'u_example');
  assert.equal(row.client_ip, '45.15.112.21');
  assert.equal(row.traffic_observed, false);
  assert.equal(row.ip_observed, true);
});

test('parseNaiveTrafficEvent maps upload/download bytes correctly', () => {
  const row = parseNaiveTrafficEvent(JSON.stringify({
    ts: '2026-06-15T12:04:30.000Z',
    event: 'connect_closed',
    username: 'u_example',
    remote_ip: '45.15.112.21',
    bytes_client_to_target: 123,
    bytes_target_to_client: 456
  }), normalizeAuditIp);

  assert.equal(row.upload_bytes, 123);
  assert.equal(row.download_bytes, 456);
  assert.equal(row.traffic_observed, true);
});

test('parseTimestamp rejects out-of-range numeric timestamps', () => {
  assert.equal(parseTimestamp(String(8640000000000001)), null);
  assert.equal(parseTimestamp('99999999999999999999999'), null);
});

test('readJsonlIncremental does not store raw partial JSON in checkpoint and replays it on the next iteration', async () => {
  const file = await makeTempFile('auth.log', '{"host":"example.com","uri":"/a","username":"a"}\n{"user');
  const first = await readJsonlIncremental(file, { file_path: file, offset: 0 });

  assert.deepEqual(first.lines, ['{"host":"example.com","uri":"/a","username":"a"}']);
  assert.equal(first.checkpoint.partial_trailing_line, '');
  assert.equal(first.checkpoint.offset, Buffer.byteLength('{"host":"example.com","uri":"/a","username":"a"}\n', 'utf8'));
  assert.equal(JSON.stringify(first.checkpoint).includes('host'), false);
  assert.equal(JSON.stringify(first.checkpoint).includes('uri'), false);

  await fsp.appendFile(file, 'name":"b"}\n');
  const second = await readJsonlIncremental(file, first.checkpoint);
  assert.deepEqual(second.lines, ['{"username":"b"}']);
});

test('readJsonlIncremental does not lose lines when maxLinesPerCycle is smaller than the chunk', async () => {
  const rows = Array.from({ length: 30 }, (_, id) => JSON.stringify({ id, note: `line-${id}` })).join('\n') + '\n';
  const file = await makeTempFile('bulk.log', rows);
  let checkpoint = { file_path: file, offset: 0 };
  const seen = [];

  for (let i = 0; i < 3; i += 1) {
    const result = await readJsonlIncremental(file, checkpoint, {
      maxLinesPerCycle: 10,
      maxBytesPerCycle: 1024 * 1024
    });
    seen.push(...result.lines.map((line) => JSON.parse(line).id));
    checkpoint = result.checkpoint;
    assert.equal(result.lines.length, 10);
  }

  const empty = await readJsonlIncremental(file, checkpoint, {
    maxLinesPerCycle: 10,
    maxBytesPerCycle: 1024 * 1024
  });
  assert.equal(empty.lines.length, 0);
  assert.deepEqual(seen, Array.from({ length: 30 }, (_, id) => id));
});

test('readJsonlIncremental preserves UTF-8 across a split inside the first emoji byte', async () => {
  await assertUtf8Split('{"text":"Привет 🙂"}\n', 1);
});

test('readJsonlIncremental preserves UTF-8 across a split inside the second emoji byte', async () => {
  await assertUtf8Split('{"text":"Привет 🙂"}\n', 2);
});

test('readJsonlIncremental preserves UTF-8 across a split inside a Cyrillic byte sequence', async () => {
  await assertUtf8Split('{"text":"Привет 🙂"}\n', -1, 'П');
});

test('readJsonlIncremental detects truncation and starts from the beginning again', async () => {
  const file = await makeTempFile('traffic.log', '{"n":1}\n{"n":2}\n');
  const initial = await readJsonlIncremental(file, { file_path: file, offset: 0 });
  assert.equal(initial.lines.length, 2);

  await fsp.writeFile(file, '{"n":3}\n');
  const truncated = await readJsonlIncremental(file, initial.checkpoint);
  assert.equal(truncated.counters.truncateDetected, true);
  assert.deepEqual(truncated.lines, ['{"n":3}']);
});

test('readJsonlIncremental drains unread rotated tail before the new file', async () => {
  const dir = await makeTempDir('vetka-rotate-');
  const file = path.join(dir, 'audit.log');
  const rotated = path.join(dir, 'audit.log-20260615');
  await fsp.writeFile(file, '{"id":1}\n{"id":2}\n{"id":3}\n');

  const first = await readJsonlIncremental(file, { file_path: file, offset: 0 }, {
    maxLinesPerCycle: 1
  });
  assert.deepEqual(first.lines, ['{"id":1}']);

  await fsp.rename(file, rotated);
  await fsp.writeFile(file, '{"id":4}\n');

  const second = await readJsonlIncremental(file, first.checkpoint, {
    maxLinesPerCycle: 10
  });
  assert.equal(second.counters.rotationDetected, true);
  assert.deepEqual(second.lines, ['{"id":2}', '{"id":3}']);

  const third = await readJsonlIncremental(file, second.checkpoint, {
    maxLinesPerCycle: 10
  });
  assert.deepEqual(third.lines, ['{"id":4}']);
});

test('readJsonlIncremental drains a valid final rotated record without terminal newline and then switches to the new file', async () => {
  const dir = await makeTempDir('vetka-rotate-final-');
  const file = path.join(dir, 'audit.log');
  const rotated = path.join(dir, 'audit.log.1');
  await fsp.writeFile(file, '{"id":1}\n{"id":2}');
  const first = await readJsonlIncremental(file, { file_path: file, offset: 0 }, { maxLinesPerCycle: 1 });
  await fsp.rename(file, rotated);
  await fsp.writeFile(file, '{"id":3}\n');

  const second = await readJsonlIncremental(file, first.checkpoint, { maxLinesPerCycle: 10 });
  assert.deepEqual(second.lines, ['{"id":2}']);
  assert.equal(second.checkpoint.rotated_source_path, '');

  const third = await readJsonlIncremental(file, second.checkpoint, { maxLinesPerCycle: 10 });
  assert.deepEqual(third.lines, ['{"id":3}']);
});

test('readJsonlIncremental drops a malformed final rotated record without terminal newline and then switches to the new file', async () => {
  const dir = await makeTempDir('vetka-rotate-malformed-');
  const file = path.join(dir, 'audit.log');
  const rotated = path.join(dir, 'audit.log.1');
  await fsp.writeFile(file, '{"id":1}\n{"id":2');
  const first = await readJsonlIncremental(file, { file_path: file, offset: 0 }, { maxLinesPerCycle: 1 });
  await fsp.rename(file, rotated);
  await fsp.writeFile(file, '{"id":3}\n');

  const second = await readJsonlIncremental(file, first.checkpoint, { maxLinesPerCycle: 10 });
  assert.deepEqual(second.lines, ['{"id":2']);
  const third = await readJsonlIncremental(file, second.checkpoint, { maxLinesPerCycle: 10 });
  assert.deepEqual(third.lines, ['{"id":3}']);
});

test('readJsonlIncremental drops an oversized final rotated record without terminal newline and then switches to the new file', async () => {
  const dir = await makeTempDir('vetka-rotate-oversized-final-');
  const file = path.join(dir, 'audit.log');
  const rotated = path.join(dir, 'audit.log.1');
  await fsp.writeFile(file, `{"id":1}\n${'x'.repeat(80)}`);
  const first = await readJsonlIncremental(file, { file_path: file, offset: 0 }, {
    maxLinesPerCycle: 1,
    maxLineBytes: 32,
    maxBytesPerCycle: Buffer.byteLength('{"id":1}\n', 'utf8')
  });
  await fsp.rename(file, rotated);
  await fsp.writeFile(file, '{"id":3}\n');

  const second = await readJsonlIncremental(file, first.checkpoint, { maxLinesPerCycle: 10, maxLineBytes: 32 });
  assert.equal(second.status, 'partial');
  assert.ok(second.warnings.some((warning) => /oversized audit log records were skipped/i.test(warning)));
  assert.equal(second.checkpoint.rotated_source_path, '');
  assert.equal(first.counters.linesSkippedOversized + second.counters.linesSkippedOversized, 1);
  const third = await readJsonlIncremental(file, second.checkpoint, { maxLinesPerCycle: 10, maxLineBytes: 32 });
  assert.deepEqual(third.lines, ['{"id":3}']);
});

test('readJsonlIncremental does not switch away from rotated tail early when line limit is hit', async () => {
  const dir = await makeTempDir('vetka-rotate-line-limit-');
  const file = path.join(dir, 'audit.log');
  const rotated = path.join(dir, 'audit.log.1');
  await fsp.writeFile(file, '{"id":1}\n{"id":2}\n{"id":3}\n');
  const first = await readJsonlIncremental(file, { file_path: file, offset: 0 }, { maxLinesPerCycle: 1 });
  await fsp.rename(file, rotated);
  await fsp.writeFile(file, '{"id":4}\n');

  const second = await readJsonlIncremental(file, first.checkpoint, { maxLinesPerCycle: 1 });
  assert.deepEqual(second.lines, ['{"id":2}']);
  assert.ok(second.checkpoint.rotated_source_path.endsWith('audit.log.1'));

  const third = await readJsonlIncremental(file, second.checkpoint, { maxLinesPerCycle: 10 });
  assert.deepEqual(third.lines, ['{"id":3}']);
  const fourth = await readJsonlIncremental(file, third.checkpoint, { maxLinesPerCycle: 10 });
  assert.deepEqual(fourth.lines, ['{"id":4}']);
});

test('readJsonlIncremental warns and continues when rotated tail file is already gone', async () => {
  const dir = await makeTempDir('vetka-rotate-missing-');
  const file = path.join(dir, 'audit.log');
  const rotated = path.join(dir, 'audit.log-20260615');
  await fsp.writeFile(file, '{"id":1}\n{"id":2}\n');
  const first = await readJsonlIncremental(file, { file_path: file, offset: 0 }, {
    maxLinesPerCycle: 1
  });
  await fsp.rename(file, rotated);
  await fsp.unlink(rotated);
  await fsp.writeFile(file, '{"id":3}\n');
  first.checkpoint.inode = 'missing-inode';

  const second = await readJsonlIncremental(file, first.checkpoint);
  assert.ok(second.warnings.some((warning) => /rotated .*tail|unread rotated lines/i.test(warning)));
  assert.deepEqual(second.lines, ['{"id":3}']);
});

test('readJsonlIncremental skips oversized lines safely even when they span multiple chunks', async () => {
  const oversized = `${'x'.repeat(80)}\n{"ok":1}\n`;
  const file = await makeTempFile('oversized.log', oversized);
  let checkpoint = { file_path: file, offset: 0 };

  const first = await readJsonlIncremental(file, checkpoint, {
    maxLineBytes: 32,
    maxBytesPerCycle: 24
  });
  checkpoint = first.checkpoint;

  const second = await readJsonlIncremental(file, checkpoint, {
    maxLineBytes: 32,
    maxBytesPerCycle: 24
  });
  checkpoint = second.checkpoint;

  const third = await readJsonlIncremental(file, checkpoint, {
    maxLineBytes: 32,
    maxBytesPerCycle: 64
  });
  checkpoint = third.checkpoint;
  const fourth = await readJsonlIncremental(file, checkpoint, {
    maxLineBytes: 32,
    maxBytesPerCycle: 64
  });

  assert.equal(first.counters.linesSkippedOversized + second.counters.linesSkippedOversized + third.counters.linesSkippedOversized + fourth.counters.linesSkippedOversized, 1);
  const warningCount = [first, second, third, fourth]
    .flatMap((result) => result.warnings)
    .filter((warning) => /oversized audit log records were skipped/i.test(warning))
    .length;
  assert.equal(warningCount, 1);
  assert.deepEqual(fourth.lines, ['{"ok":1}']);
});

test('readJsonlIncremental marks oversized newline-terminated records as partial, advances offset, and does not reread them', async () => {
  const file = await makeTempFile('oversized-newline.log', `${'x'.repeat(80)}\n{"ok":1}\n`);
  const first = await readJsonlIncremental(file, { file_path: file, offset: 0 }, {
    maxLineBytes: 32,
    maxBytesPerCycle: 256
  });

  assert.equal(first.status, 'partial');
  assert.ok(first.warnings.some((warning) => /oversized audit log records were skipped/i.test(warning)));
  assert.deepEqual(first.lines, ['{"ok":1}']);
  assert.equal(first.counters.linesSkippedOversized, 1);
  assert.ok(first.checkpoint.offset > 0);

  const second = await readJsonlIncremental(file, first.checkpoint, {
    maxLineBytes: 32,
    maxBytesPerCycle: 256
  });
  assert.equal(second.lines.length, 0);
  assert.equal(second.counters.linesSkippedOversized, 0);
});

test('readJsonlIncremental emits one bounded warning even when multiple oversized records are skipped in one iteration', async () => {
  const file = await makeTempFile('oversized-many.log', `${'x'.repeat(80)}\n${'y'.repeat(90)}\n{"ok":1}\n`);
  const result = await readJsonlIncremental(file, { file_path: file, offset: 0 }, {
    maxLineBytes: 32,
    maxBytesPerCycle: 512
  });

  const warnings = result.warnings.filter((warning) => /oversized audit log records were skipped/i.test(warning));
  assert.equal(result.status, 'partial');
  assert.equal(result.counters.linesSkippedOversized, 2);
  assert.equal(warnings.length, 1);
  assert.deepEqual(result.lines, ['{"ok":1}']);
});

test('readJsonlIncremental clips bootstrap reads to a bounded tail window and keeps dropping the opening fragment until newline', async () => {
  const file = await makeTempFile('bootstrap.log', `${'x'.repeat(256)}\n{"id":1}\n`);
  const first = await readJsonlIncremental(file, {}, {
    bootstrapBytes: 40,
    maxBytesPerCycle: 10
  });
  assert.equal(first.counters.bootstrapClipped, true);
  assert.equal(first.lines.length, 0);
  assert.equal(first.checkpoint.discard_until_newline, 1);

  const second = await readJsonlIncremental(file, first.checkpoint, {
    bootstrapBytes: 40,
    maxBytesPerCycle: 64
  });
  assert.deepEqual(second.lines, ['{"id":1}']);
});

test('readJsonlIncremental can return a bounded chunk smaller than the file', async () => {
  const file = await makeTempFile('bounded.log', '{"a":1}\n{"a":2}\n{"a":3}\n');
  const result = await readJsonlIncremental(file, { file_path: file, offset: 0 }, {
    maxBytesPerCycle: Buffer.byteLength('{"a":1}\n{"a":2}\n', 'utf8')
  });

  assert.deepEqual(result.lines, ['{"a":1}', '{"a":2}']);
});

async function assertUtf8Split(line, emojiByteIndex = -1, cyrillicChar = '') {
  const file = await makeTempFile('utf8.log', line);
  const bytes = Buffer.from(line, 'utf8');
  let splitAt = -1;
  if (emojiByteIndex > 0) {
    const emojiIndex = bytes.indexOf(Buffer.from('🙂', 'utf8'));
    splitAt = emojiIndex + emojiByteIndex;
  } else {
    const charIndex = bytes.indexOf(Buffer.from(cyrillicChar, 'utf8'));
    splitAt = charIndex + 1;
  }

  const first = await readJsonlIncremental(file, { file_path: file, offset: 0 }, {
    maxBytesPerCycle: splitAt
  });
  assert.equal(first.lines.length, 0);
  assert.equal(first.checkpoint.partial_trailing_line, '');

  const second = await readJsonlIncremental(file, first.checkpoint, {
    maxBytesPerCycle: bytes.length
  });
  const parsed = JSON.parse(second.lines[0]);
  assert.equal(parsed.text, 'Привет 🙂');
}
