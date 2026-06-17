'use strict';

const { execFile } = require('node:child_process');
const storage = require('./storage');
const {
  COLLECTOR_STATUS,
  TELEMETRY_HARD_SESSION_LIMIT,
  normalizeCollectIntervalSeconds,
  normalizeHistoryTtlHours,
  normalizeSessionTtlMinutes,
  sessionTtlSeconds,
  historyTtlSeconds
} = require('./schema');
const {
  readJsonlIncremental,
  parseNaiveAuthEvent,
  parseNaiveTrafficEvent,
  combineNaiveStatuses
} = require('./naiveCollector');
const { collectMieruTelemetry } = require('./mieruCollector');

function createTelemetryService(options) {
  const db = options.db || null;
  const cfg = options.cfg || {};
  const getAllUsers = typeof options.getAllUsers === 'function' ? options.getAllUsers : (() => []);
  const normalizeAuditIp = typeof options.normalizeAuditIp === 'function' ? options.normalizeAuditIp : (value => String(value || '').trim());
  const authAuditLogPath = typeof options.authAuditLogPath === 'function' ? options.authAuditLogPath : (() => '');
  const trafficAuditLogPath = typeof options.trafficAuditLogPath === 'function' ? options.trafficAuditLogPath : (() => '');
  const runMitaUsersCommand = typeof options.runMitaUsersCommand === 'function'
    ? options.runMitaUsersCommand
    : defaultRunMitaUsersCommand;
  const onMieruRowsCollected = typeof options.onMieruRowsCollected === 'function'
    ? options.onMieruRowsCollected
    : null;
  const logger = options.logger || console;
  let storageReady = !!db;
  let fallbackState = {
    collector: 'telemetry',
    status: telemetryEnabledFromCfg(cfg) ? COLLECTOR_STATUS.UNAVAILABLE : COLLECTOR_STATUS.DISABLED,
    warnings: storageReady ? [] : ['telemetry storage is unavailable on this node'],
    details: { protocol_type: cfg.protocolType, components: {} },
    last_successful_collection_at: null,
    last_attempted_collection_at: null,
    last_error: storageReady ? null : 'telemetry storage initialization failed'
  };
  if (db) {
    try {
      storage.initTelemetryTables(db);
    } catch (err) {
      storageReady = false;
      fallbackState = {
        ...fallbackState,
        warnings: ['telemetry storage is unavailable on this node'],
        last_error: safeErrorMessage(err) || 'telemetry storage initialization failed'
      };
      safeWarn(logger, `[telemetry] storage init failed: ${fallbackState.last_error}`);
    }
  }

  let timer = null;
  let stopped = true;
  let inFlightPromise = null;
  let currentAbortController = null;
  let latestMieruSnapshot = {
    rows: [],
    collected_at: null,
    collector_status: COLLECTOR_STATUS.UNAVAILABLE,
    stale: false
  };

  function intervalMs() {
    return normalizeCollectIntervalSeconds(cfg.telemetryCollectIntervalSeconds) * 1000;
  }

  function telemetryEnabled() {
    return telemetryEnabledFromCfg(cfg);
  }

  function nowIso() {
    return new Date().toISOString();
  }

  function historyCutoffIso() {
    return new Date(Date.now() - normalizeHistoryTtlHours(cfg.ipHistoryTtlHours) * 3600000).toISOString();
  }

  function activeCutoffIso() {
    return new Date(Date.now() - normalizeSessionTtlMinutes(cfg.sessionTtlMinutes) * 60000).toISOString();
  }

  function safeCurrentCollectorState() {
    try {
      if (!storageReady || !db) return { ...fallbackState };
      const row = storage.getCollectorState(db, 'telemetry');
      if (row) {
        fallbackState = { ...row };
        return row;
      }
    } catch {}
    return { ...fallbackState };
  }

  function safePersistCollectorState(state) {
    const nextState = {
      collector: 'telemetry',
      ...state
    };
    fallbackState = {
      ...fallbackState,
      ...nextState,
      warnings: Array.isArray(nextState.warnings) ? [...nextState.warnings] : [],
      details: nextState.details || {}
    };
    try {
      if (!storageReady || !db) return false;
      storage.updateCollectorState(db, nextState);
      return true;
    } catch {
      return false;
    }
  }

  async function collectNaiveSource({ collectorName, filePath, parser, upsert }) {
    const checkpoint = storage.loadCheckpoint(db, filePath);
    const readResult = await readJsonlIncremental(filePath, checkpoint);
    const rows = [];
    for (const line of readResult.lines) {
      const parsed = parser(line, normalizeAuditIp);
      if (parsed) rows.push(parsed);
      else readResult.counters.linesSkippedMalformed += 1;
    }

    if (db && readResult.ok) {
      const commitBatch = db.transaction((observations, nextCheckpoint) => {
        for (const observation of observations) upsert(db, observation);
        storage.saveCheckpoint(db, nextCheckpoint);
      });
      commitBatch(rows, readResult.checkpoint);
    }

    return {
      readResult,
      rows,
      component: {
        status: readResult.status,
        available: readResult.ok,
        records_processed: rows.length,
        malformed_skipped: readResult.counters.linesSkippedMalformed,
        oversized_skipped: readResult.counters.linesSkippedOversized
      },
      warnings: readResult.warnings,
      collectorName
    };
  }

  async function collectNaive() {
    const authPath = authAuditLogPath();
    const trafficPath = trafficAuditLogPath();
    const authResult = await collectNaiveSource({
      collectorName: 'auth',
      filePath: authPath,
      parser: parseNaiveAuthEvent,
      upsert: storage.upsertNaiveObservation
    });
    const trafficResult = await collectNaiveSource({
      collectorName: 'traffic',
      filePath: trafficPath,
      parser: parseNaiveTrafficEvent,
      upsert: storage.upsertNaiveObservation
    });

    return {
      status: combineNaiveStatuses([authResult.readResult.status, trafficResult.readResult.status]),
      warnings: uniqWarnings([...authResult.warnings, ...trafficResult.warnings]),
      components: {
        auth: authResult.component,
        traffic: trafficResult.component
      },
      usableResult: true
    };
  }

  async function collectMieru() {
    currentAbortController = new AbortController();
    try {
      const result = await collectMieruTelemetry({
        runCommand: runMitaUsersCommand,
        nowIso: nowIso(),
        abortSignal: currentAbortController.signal
      });
      if (onMieruRowsCollected && (result.status === COLLECTOR_STATUS.OK || result.status === COLLECTOR_STATUS.PARTIAL)) {
        try {
          await Promise.resolve(onMieruRowsCollected({
            rows: result.rows,
            collectedAt: result.lastSuccessfulCollectionAt || nowIso(),
            usableResult: result.usableResult === true
          }));
        } catch (err) {
          result.warnings = uniqWarnings([...(result.warnings || []), 'legacy mieru metrics cache update failed']);
          result.status = COLLECTOR_STATUS.PARTIAL;
        }
      }
      if (db && result.rows.length) {
        const commitRows = db.transaction((rows) => {
          for (const row of rows) storage.upsertMieruObservation(db, row);
        });
        commitRows(result.rows);
      }
      if (result.usableResult === true) {
        latestMieruSnapshot = {
          rows: result.rows.map((row) => ({ ...row })),
          collected_at: result.lastSuccessfulCollectionAt || nowIso(),
          collector_status: result.status,
          stale: result.status !== COLLECTOR_STATUS.OK
        };
      } else {
        latestMieruSnapshot = {
          ...latestMieruSnapshot,
          collector_status: result.status,
          stale: true
        };
      }
      return {
        status: result.status,
        warnings: uniqWarnings(result.warnings),
        components: {
          mieru: {
            status: result.status,
            available: result.status !== COLLECTOR_STATUS.UNAVAILABLE,
            ...result.details
          }
        },
        lastSuccessfulCollectionAt: result.lastSuccessfulCollectionAt || null,
        lastError: result.lastError || null,
        usableResult: result.usableResult === true
      };
    } finally {
      currentAbortController = null;
    }
  }

  async function collectOnce() {
    const attemptedAt = nowIso();
    const previousState = currentCollectorState();

    if (!db || !storageReady) {
      latestMieruSnapshot = {
        ...latestMieruSnapshot,
        collector_status: COLLECTOR_STATUS.UNAVAILABLE,
        stale: true
      };
      safePersistCollectorState({
        status: COLLECTOR_STATUS.UNAVAILABLE,
        warnings: ['telemetry cache is unavailable on this node'],
        details: { protocol_type: cfg.protocolType, components: {} },
        last_attempted_collection_at: attemptedAt,
        last_successful_collection_at: previousState.last_successful_collection_at || null,
        last_error: 'sqlite cache is unavailable'
      });
      return;
    }

    if (!telemetryEnabled()) {
      latestMieruSnapshot = {
        ...latestMieruSnapshot,
        collector_status: COLLECTOR_STATUS.DISABLED,
        stale: latestMieruSnapshot.rows.length > 0
      };
      safePersistCollectorState({
        status: COLLECTOR_STATUS.DISABLED,
        warnings: [],
        details: { protocol_type: cfg.protocolType, components: {} },
        last_attempted_collection_at: attemptedAt,
        last_successful_collection_at: previousState.last_successful_collection_at || null,
        last_error: null
      });
      return;
    }

    const result = cfg.protocolType === 'mieru'
      ? await collectMieru()
      : await collectNaive();

    const prunedSessions = storage.pruneExpiredTelemetry(db, historyCutoffIso());
    safePersistCollectorState({
      status: result.status,
      warnings: result.warnings,
      details: {
        protocol_type: cfg.protocolType,
        components: result.components,
        cleanup: {
          telemetry_sessions_removed: prunedSessions,
          traffic_snapshots_removed: 0
        }
      },
      last_attempted_collection_at: attemptedAt,
      last_successful_collection_at: result.status === COLLECTOR_STATUS.UNAVAILABLE || result.usableResult === false
        ? (previousState.last_successful_collection_at || null)
        : (result.lastSuccessfulCollectionAt || attemptedAt),
      last_error: result.lastError || null
    });
  }

  function recordUnexpectedFailure(err) {
    const attemptedAt = nowIso();
    const previousState = safeCurrentCollectorState();
    const message = safeErrorMessage(err);
    latestMieruSnapshot = {
      ...latestMieruSnapshot,
      collector_status: COLLECTOR_STATUS.UNAVAILABLE,
      stale: true
    };
    try {
      safePersistCollectorState({
        status: COLLECTOR_STATUS.UNAVAILABLE,
        warnings: ['telemetry collector hit a temporary internal error'],
        details: previousState.details || { protocol_type: cfg.protocolType, components: {} },
        last_attempted_collection_at: attemptedAt,
        last_successful_collection_at: previousState.last_successful_collection_at || null,
        last_error: message
      });
    } catch {}
    safeWarn(logger, `[telemetry] collection failed: ${message}`);
  }

  async function collectOnceSafe() {
    if (inFlightPromise) return inFlightPromise;
    inFlightPromise = (async () => {
      try {
        await collectOnce();
      } catch (err) {
        try {
          recordUnexpectedFailure(err);
        } catch {}
      } finally {
        inFlightPromise = null;
        if (!stopped) scheduleNext(intervalMs());
      }
    })();
    return inFlightPromise.catch(() => {});
  }

  function scheduleNext(delayMs) {
    if (stopped) return;
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => {
      void collectOnceSafe().catch(() => {});
    }, delayMs);
    if (typeof timer.unref === 'function') timer.unref();
  }

  function start() {
    stopped = false;
    if (timer) clearTimeout(timer);
    timer = null;
    setImmediate(() => {
      if (!stopped) void collectOnceSafe().catch(() => {});
    });
  }

  async function stop(options = {}) {
    stopped = true;
    if (timer) clearTimeout(timer);
    timer = null;
    if (currentAbortController) {
      try { currentAbortController.abort(); } catch {}
    }
    const timeoutMs = Number.isInteger(options.timeoutMs) && options.timeoutMs > 0 ? options.timeoutMs : 6000;
    if (!inFlightPromise) return;
    await Promise.race([
      inFlightPromise.catch(() => {}),
      sleep(timeoutMs)
    ]);
  }

  function refresh() {
    return stop().catch(() => {}).finally(() => start());
  }

  function currentCollectorState() {
    return safeCurrentCollectorState();
  }

  function buildCapabilities(state) {
    if (!telemetryEnabled()) {
      return {
        client_ip: false,
        per_user_activity: false,
        traffic_counters: false,
        first_seen: false,
        last_seen: false
      };
    }
    if (cfg.protocolType === 'mieru') {
      const available = state.status === COLLECTOR_STATUS.OK || state.status === COLLECTOR_STATUS.PARTIAL;
      return {
        client_ip: false,
        per_user_activity: available,
        traffic_counters: available,
        first_seen: available,
        last_seen: available
      };
    }
    const components = state.details?.components || {};
    const authAvailable = components.auth?.available === true;
    const trafficAvailable = components.traffic?.available === true;
    const anyAvailable = authAvailable || trafficAvailable;
    return {
      client_ip: anyAvailable,
      per_user_activity: anyAvailable,
      traffic_counters: trafficAvailable,
      first_seen: anyAvailable,
      last_seen: anyAvailable
    };
  }

  function buildSessionsResponse(options = {}) {
    const generatedAt = nowIso();
    const state = safeCurrentCollectorState();
    const capabilities = buildCapabilities(state);
    let users = [];
    try {
      users = getAllUsers();
    } catch {}
    const usersByUsername = new Map(users.map((user) => [String(user.username || ''), user]));
    const response = {
      ok: true,
      node_id: cfg.nodeId || null,
      protocol_type: cfg.protocolType,
      generated_at: generatedAt,
      collector_status: state.status,
      session_ttl_seconds: sessionTtlSeconds(cfg),
      history_ttl_seconds: historyTtlSeconds(cfg),
      last_successful_collection_at: state.last_successful_collection_at || null,
      capabilities,
      sessions: [],
      warnings: uniqWarnings(state.warnings || [])
    };

    if (!telemetryEnabled()) return response;
    const listed = safeListTelemetrySessions({
      includeRecent: options.includeRecent === true,
      activeCutoffIso: activeCutoffIso(),
      historyCutoffIso: historyCutoffIso(),
      limit: TELEMETRY_HARD_SESSION_LIMIT
    });
    if (listed.error) {
      response.collector_status = COLLECTOR_STATUS.UNAVAILABLE;
      response.sessions = [];
      response.warnings = uniqWarnings([...response.warnings, 'telemetry cache read is temporarily unavailable']);
      return response;
    }
    if (listed.overflow) {
      response.warnings.push('telemetry response was truncated to a bounded safety limit');
    }

    const activeCutoff = Date.parse(activeCutoffIso());
    response.sessions = listed.sessions.map((row) => {
      const user = usersByUsername.get(String(row.protocol_username || '')) || null;
      const lastSeenMs = Date.parse(row.last_seen_at || '');
      return {
        user_id: user ? user.id : null,
        protocol_username: row.protocol_username,
        user_present_in_cache: !!user,
        protocol: row.protocol,
        client_ip: row.client_ip || null,
        first_seen_at: row.first_seen_at,
        last_seen_at: row.last_seen_at,
        upload_bytes: Math.max(0, Number(row.upload_bytes) || 0),
        download_bytes: Math.max(0, Number(row.download_bytes) || 0),
        active: Number.isFinite(lastSeenMs) ? lastSeenMs >= activeCutoff : false,
        ip_observed: !!row.ip_observed && !!row.client_ip,
        traffic_observed: !!row.traffic_observed,
        source: row.source,
        traffic_scope: row.traffic_scope
      };
    });
    return response;
  }

  return {
    start,
    stop,
    refresh,
    collectOnce: collectOnceSafe,
    buildSessionsResponse,
    currentCollectorState,
    isStorageReady: () => storageReady,
    getLatestMieruSnapshot() {
      return {
        rows: latestMieruSnapshot.rows.map((row) => ({ ...row })),
        collected_at: latestMieruSnapshot.collected_at || null,
        collector_status: latestMieruSnapshot.collector_status,
        stale: latestMieruSnapshot.stale === true
      };
    }
  };

  function safeListTelemetrySessions(listOptions) {
    try {
      if (!storageReady || !db) return { sessions: [], overflow: false, error: 'storage unavailable' };
      return storage.listTelemetrySessions(db, listOptions);
    } catch {
      return { sessions: [], overflow: false, error: 'storage read failed' };
    }
  }
}

function defaultRunMitaUsersCommand(abortSignal) {
  return new Promise((resolve, reject) => {
    const child = execFile('mita', ['get', 'users'], {
      timeout: 5000,
      maxBuffer: 1024 * 1024
    }, (err, stdout) => {
      if (abortSignal) abortSignal.removeEventListener('abort', onAbort);
      if (err) return reject(err);
      resolve(stdout);
    });

    function onAbort() {
      try { child.kill('SIGTERM'); } catch {}
      const abortError = new Error('mita get users aborted');
      abortError.code = 'ABORT_ERR';
      reject(abortError);
    }

    if (abortSignal) {
      if (abortSignal.aborted) return onAbort();
      abortSignal.addEventListener('abort', onAbort, { once: true });
    }
  });
}

function safeErrorMessage(err) {
  const message = String(err?.message || err || 'telemetry collection failed').replace(/\s+/g, ' ').trim();
  return message || 'telemetry collection failed';
}

function safeWarn(logger, message) {
  try {
    if (logger && typeof logger.warn === 'function') logger.warn(message);
  } catch {}
}

function telemetryEnabledFromCfg(cfg) {
  return cfg?.telemetryEnabled !== false;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function uniqWarnings(items) {
  return [...new Set((items || []).filter(Boolean).map((value) => String(value).trim()).filter(Boolean))];
}

module.exports = {
  createTelemetryService,
  defaultRunMitaUsersCommand,
  safeErrorMessage
};
