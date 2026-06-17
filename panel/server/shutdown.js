'use strict';

function createGracefulShutdown(options) {
  const server = options.server;
  const telemetryService = options.telemetryService;
  const logger = options.logger || console;
  const exitFn = typeof options.exitFn === 'function' ? options.exitFn : ((code) => process.exit(code));
  const timeoutMs = Number.isInteger(options.timeoutMs) && options.timeoutMs > 0 ? options.timeoutMs : 10000;
  let inFlight = null;

  return function shutdown(signal = 'SIGTERM') {
    if (inFlight) return inFlight;
    inFlight = (async () => {
      let forced = null;
      try {
        forced = setTimeout(() => {
          try { logger.warn(`[shutdown] forcing exit after ${timeoutMs}ms (${signal})`); } catch {}
          exitFn(1);
        }, timeoutMs);
        if (typeof forced.unref === 'function') forced.unref();

        await Promise.resolve(telemetryService?.stop?.({ timeoutMs: Math.max(1000, timeoutMs - 1000) }));
        await closeServer(server);

        clearTimeout(forced);
        exitFn(0);
      } catch (err) {
        if (forced) clearTimeout(forced);
        try {
          logger.warn(`[shutdown] graceful shutdown failed: ${String(err?.message || err || 'unknown error')}`);
        } catch {}
        exitFn(1);
      }
    })();
    return inFlight;
  };
}

function closeServer(server) {
  if (!server || typeof server.close !== 'function') return Promise.resolve();
  return new Promise((resolve, reject) => {
    server.close((err) => {
      if (err) reject(err);
      else resolve();
    });
  });
}

module.exports = {
  createGracefulShutdown,
  closeServer
};
