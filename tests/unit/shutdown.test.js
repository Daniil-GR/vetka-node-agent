'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { createGracefulShutdown } = require('../../panel/server/shutdown');

test('graceful shutdown stops telemetry, closes server, and is idempotent', async () => {
  const calls = [];
  const shutdown = createGracefulShutdown({
    telemetryService: {
      async stop() {
        calls.push('stop');
      }
    },
    server: {
      close(cb) {
        calls.push('close');
        cb();
      }
    },
    exitFn(code) {
      calls.push(`exit:${code}`);
    },
    logger: { warn() {} },
    timeoutMs: 100
  });

  await Promise.all([shutdown('SIGTERM'), shutdown('SIGINT')]);
  assert.deepEqual(calls, ['stop', 'close', 'exit:0']);
});

test('graceful shutdown has a timeout fallback', async () => {
  const codes = [];
  const shutdown = createGracefulShutdown({
    telemetryService: {
      async stop() {}
    },
    server: {
      close() {}
    },
    exitFn(code) {
      codes.push(code);
    },
    logger: { warn() {} },
    timeoutMs: 25
  });

  shutdown('SIGTERM');
  await new Promise((resolve) => setTimeout(resolve, 60));
  assert.ok(codes.includes(1));
});
