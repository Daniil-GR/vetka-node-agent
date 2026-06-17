'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fsp = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const net = require('node:net');
const { spawn } = require('node:child_process');

async function makeTempDir(prefix = 'vetka-startup-') {
  return fsp.mkdtemp(path.join(os.tmpdir(), prefix));
}

async function getFreePort() {
  return await new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      const port = address && typeof address === 'object' ? address.port : 0;
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        resolve(port);
      });
    });
  });
}

async function canConnect(port) {
  return await new Promise((resolve) => {
    const socket = net.connect({ host: '127.0.0.1', port });
    const finish = (value) => {
      socket.removeAllListeners();
      socket.destroy();
      resolve(value);
    };
    socket.once('connect', () => finish(true));
    socket.once('error', () => finish(false));
    socket.setTimeout(1000, () => finish(false));
  });
}

async function isPortAvailable(port) {
  return await new Promise((resolve) => {
    const server = net.createServer();
    const finish = (value) => {
      server.removeAllListeners();
      try { server.close(); } catch {}
      resolve(value);
    };
    server.once('error', () => finish(false));
    server.listen(port, '127.0.0.1', () => finish(true));
  });
}

async function writeStartupConfig(dir, protocolType, port) {
  const dbPath = path.join(dir, 'cache.sqlite');
  const configPath = path.join(dir, 'config.json');
  const config = {
    domain: 'localhost',
    serverIp: '127.0.0.1',
    adminUser: 'admin',
    adminPassHash: 'test-hash',
    naivePort: 443,
    mieruPortStart: 2012,
    mieruPortEnd: 2022,
    panelPort: port,
    panelHost: '127.0.0.1',
    exposePanel: false,
    dbPath,
    caddyBin: '/usr/local/bin/caddy-naive',
    caddyFile: path.join(dir, 'Caddyfile'),
    caddyConfigDir: dir,
    fakeSiteDir: path.join(dir, 'fake-site'),
    staticSite: {
      enabled: false,
      root: '',
      sourceType: 'archive_url',
      sourceUrl: '',
      deployOnInstall: true,
      deployOnUpdate: 'missing-only',
      createIfMissing: true
    },
    fakeSiteUrl: 'https://www.example.com',
    probeSecret: '',
    probeMode: 'bare',
    mitaStateFile: path.join(dir, 'mita-state.json'),
    trafficPattern: 'NOOP',
    mtu: 1400,
    udpEnabled: false,
    cascadeEnabled: false,
    cascadeNaiveUpstream: '',
    cascadeMieru: { host: '', portStart: 2012, portEnd: 2022, user: '', pass: '' },
    cascadeMieruEgress: {},
    nodeApiKey: '',
    nodeId: 'startup-node',
    nodeSecret: 'startup-secret',
    nodePort: port,
    nodeListenHost: '127.0.0.1',
    protocolType,
    appliedStateFile: path.join(dir, 'state.json'),
    backendAllowedIps: ['127.0.0.1'],
    allowAnyBackendIp: false,
    sessionTtlMinutes: 10,
    authAuditLogPath: path.join(dir, 'auth.log'),
    trafficAuditLogPath: path.join(dir, 'traffic.log'),
    ipHistoryTtlHours: 24,
    telemetryEnabled: false,
    telemetryCollectIntervalSeconds: 15,
    maxUniqueIpsPerUser: 5,
    enforceIpLimit: false,
    allowLocalUserMutations: false,
    subscriptionBaseUrl: '',
    language: 'en',
    version: '1.2.6'
  };
  await fsp.writeFile(configPath, JSON.stringify(config, null, 2));
  return configPath;
}

function removeListenerSafe(emitter, eventName, listener) {
  if (listener) emitter.removeListener(eventName, listener);
}

async function waitForChildExit(child, timeoutMs) {
  if (!child || child.exitCode !== null) return true;
  return await new Promise((resolve) => {
    const timer = setTimeout(() => {
      cleanup();
      resolve(false);
    }, timeoutMs);
    function onExit() {
      cleanup();
      resolve(true);
    }
    function cleanup() {
      clearTimeout(timer);
      removeListenerSafe(child, 'exit', onExit);
      removeListenerSafe(child, 'close', onExit);
    }
    child.once('exit', onExit);
    child.once('close', onExit);
  });
}

async function stopChild(child) {
  if (!child || child.exitCode !== null) return { exited: true, forced: false };
  try {
    child.kill('SIGTERM');
  } catch {}
  let exited = await waitForChildExit(child, 3000);
  if (!exited && child.exitCode === null) {
    try {
      child.kill('SIGKILL');
    } catch {}
    exited = await waitForChildExit(child, 3000);
    return { exited, forced: true };
  }
  return { exited, forced: false };
}

async function startAgent(protocolType, options = {}) {
  const port = options.port || await getFreePort();
  const dir = await makeTempDir();
  const configPath = await writeStartupConfig(dir, protocolType, port);
  const child = spawn(process.execPath, ['panel/server/index.js'], {
    cwd: path.resolve(__dirname, '../..'),
    env: {
      ...process.env,
      VETKA_PANEL_CONFIG: configPath,
      VETKA_DB_PATH: path.join(dir, 'cache.sqlite'),
      VETKA_MITA_STATE_FILE: path.join(dir, 'mita-state.json'),
      NODE_ID: 'startup-node',
      NODE_SECRET: 'startup-secret',
      PROTOCOL_TYPE: protocolType,
      NODE_LISTEN_HOST: '127.0.0.1',
      NODE_PORT: String(port)
    },
    stdio: ['ignore', 'pipe', 'pipe']
  });

  let output = '';
  let timer = null;
  let settled = false;
  let stdoutListener;
  let stderrListener;
  let exitListener;
  let errorListener;

  const startup = new Promise((resolve, reject) => {
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      removeListenerSafe(child.stdout, 'data', stdoutListener);
      removeListenerSafe(child.stderr, 'data', stderrListener);
      removeListenerSafe(child, 'exit', exitListener);
      removeListenerSafe(child, 'error', errorListener);
      if (error) reject(error);
      else resolve(value);
    };

    stdoutListener = (chunk) => {
      output += chunk.toString();
      if (new RegExp(`http://127\\.0\\.0\\.1:${port}/`).test(output)) {
        finish(null, { marker: 'banner' });
      }
    };
    stderrListener = (chunk) => {
      output += chunk.toString();
    };
    exitListener = (code, signal) => {
      finish(new Error(`agent exited before startup for ${protocolType} (code=${code}, signal=${signal})\n${output}`));
    };
    errorListener = (error) => {
      finish(new Error(`agent failed to start for ${protocolType}: ${error.message}\n${output}`));
    };

    child.stdout.on('data', stdoutListener);
    child.stderr.on('data', stderrListener);
    child.once('exit', exitListener);
    child.once('error', errorListener);
    timer = setTimeout(() => {
      finish(new Error(`startup timeout for ${protocolType}\n${output}`));
    }, options.startupTimeoutMs || 10000);
  });

  try {
    await startup;
    const connected = await canConnect(port);
    if (!connected) {
      throw new Error(`agent did not open TCP port ${port}\n${output}`);
    }
    assert.equal(child.exitCode, null);
    return { child, output, port, dir };
  } catch (error) {
    await stopChild(child);
    await fsp.rm(dir, { recursive: true, force: true });
    throw error;
  }
}

async function cleanupAgent(run) {
  if (!run) return;
  await stopChild(run.child);
  await fsp.rm(run.dir, { recursive: true, force: true });
}

test('panel/server/index.js starts successfully for naive on a free port and shuts down cleanly', async () => {
  const run = await startAgent('naive');
  try {
    assert.match(run.output, /Vetka Node Agent v/);
    assert.doesNotMatch(run.output, /ReferenceError: historyCutoffIso is not defined/);
    assert.notEqual(run.port, 2222);
  } finally {
    await cleanupAgent(run);
    assert.equal(await canConnect(run.port), false);
    assert.equal(await fsp.stat(run.dir).then(() => true, () => false), false);
  }
});

test('panel/server/index.js starts successfully for mieru on a free port and shuts down cleanly', async () => {
  const run = await startAgent('mieru');
  try {
    assert.match(run.output, /Vetka Node Agent v/);
    assert.doesNotMatch(run.output, /ReferenceError: historyCutoffIso is not defined/);
    assert.notEqual(run.port, 2222);
  } finally {
    await cleanupAgent(run);
    assert.equal(await canConnect(run.port), false);
    assert.equal(await fsp.stat(run.dir).then(() => true, () => false), false);
  }
});

test('startup helper does not depend on port 2222 being free', async () => {
  let blocker = null;
  const portWasFree = await isPortAvailable(2222);
  if (portWasFree) {
    blocker = net.createServer();
    await new Promise((resolve, reject) => {
      blocker.once('error', reject);
      blocker.listen(2222, '127.0.0.1', resolve);
    });
  }

  let run;
  try {
    run = await startAgent('naive');
    assert.notEqual(run.port, 2222);
    assert.doesNotMatch(run.output, /EADDRINUSE.*127\.0\.0\.1:2222/);
  } finally {
    await cleanupAgent(run);
    if (blocker) {
      await new Promise((resolve) => blocker.close(resolve));
    }
  }
});

test('startup helper kills the child and removes temp files when startup times out', async () => {
  const dir = await makeTempDir();
  const child = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], {
    cwd: path.resolve(__dirname, '../..'),
    stdio: ['ignore', 'pipe', 'pipe']
  });
  let output = '';
  child.stdout.on('data', (chunk) => { output += chunk.toString(); });
  child.stderr.on('data', (chunk) => { output += chunk.toString(); });

  let timer = null;
  let settled = false;
  const startup = new Promise((resolve, reject) => {
    const finish = (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (error) reject(error);
      else resolve();
    };
    timer = setTimeout(() => finish(new Error('startup timeout for timeout-fixture')), 100);
    child.once('exit', (code, signal) => finish(new Error(`fixture exited early (code=${code}, signal=${signal})\n${output}`)));
    child.once('error', (error) => finish(error));
  });

  try {
    await assert.rejects(startup, /startup timeout/);
  } finally {
    const stop = await stopChild(child);
    await fsp.rm(dir, { recursive: true, force: true });
    assert.equal(stop.exited, true);
    assert.equal(await fsp.stat(dir).then(() => true, () => false), false);
  }
});

test('startup helper handles early child exit and removes temp files', async () => {
  const dir = await makeTempDir();
  const child = spawn(process.execPath, ['-e', 'process.exit(3)'], {
    cwd: path.resolve(__dirname, '../..'),
    stdio: ['ignore', 'pipe', 'pipe']
  });
  let output = '';
  child.stdout.on('data', (chunk) => { output += chunk.toString(); });
  child.stderr.on('data', (chunk) => { output += chunk.toString(); });

  const startup = new Promise((resolve, reject) => {
    child.once('exit', (code, signal) => {
      reject(new Error(`fixture exited early (code=${code}, signal=${signal})\n${output}`));
    });
    child.once('error', reject);
    setTimeout(resolve, 1000);
  });

  try {
    await assert.rejects(startup, /fixture exited early \(code=3/);
  } finally {
    await stopChild(child);
    await fsp.rm(dir, { recursive: true, force: true });
    assert.equal(await fsp.stat(dir).then(() => true, () => false), false);
  }
});
