'use strict';

function createLegacyMieruCompatibilityUpdater(options) {
  const db = options.db || null;
  const getAllUsers = typeof options.getAllUsers === 'function' ? options.getAllUsers : (() => []);
  const historyCutoffIso = typeof options.historyCutoffIso === 'function' ? options.historyCutoffIso : (() => new Date().toISOString());
  const nowMs = typeof options.nowMs === 'function' ? options.nowMs : (() => Date.now());
  const minUpdateIntervalMs = Number.isInteger(options.minUpdateIntervalMs) ? options.minUpdateIntervalMs : 60000;
  const cleanupIntervalMs = Number.isInteger(options.cleanupIntervalMs) ? options.cleanupIntervalMs : 3600000;

  let lastAppliedAtMs = -minUpdateIntervalMs;
  let lastCleanupAtMs = -cleanupIntervalMs;

  if (db) {
    try {
      db.exec(`
        CREATE INDEX IF NOT EXISTS idx_traffic_snapshots_ts
        ON traffic_snapshots(ts);
      `);
    } catch {}
  }

  function apply(rows, collectedAt) {
    if (!db || !Array.isArray(rows)) return { updatedUsers: 0, cleanedSnapshots: false, throttled: false };
    const now = nowMs();
    const shouldCleanup = now - lastCleanupAtMs >= cleanupIntervalMs;
    const shouldUpdate = now - lastAppliedAtMs >= minUpdateIntervalMs;
    const usersByUsername = new Map(getAllUsers().map((user) => [String(user.username || ''), user]));

    if (!shouldCleanup && !shouldUpdate) {
      return { updatedUsers: 0, cleanedSnapshots: false, throttled: true };
    }

    const updateStmt = db.prepare(`
      UPDATE users
      SET usedMB = ?, lastSeen = ?
      WHERE username = ?
    `);

    let updatedUsers = 0;
    const tx = db.transaction(() => {
      if (shouldCleanup) {
        db.prepare('DELETE FROM traffic_snapshots WHERE ts < ?').run(historyCutoffIso());
      }
      if (!shouldUpdate) return;
      for (const row of rows) {
        const username = String(row.protocol_username || '').trim();
        if (!username) continue;
        const current = usersByUsername.get(username);
        if (!current) continue;
        const usedMB = (Number(row.upload_bytes) + Number(row.download_bytes)) / 1048576;
        const lastSeen = row.last_seen_at || current.lastSeen || String(collectedAt || '');
        const nextUsed = Number.isFinite(usedMB) ? usedMB : Number(current.usedMB || 0);
        if (Number(current.usedMB || 0) === nextUsed && String(current.lastSeen || '') === String(lastSeen || '')) continue;
        updateStmt.run(nextUsed, lastSeen || null, username);
        updatedUsers += 1;
      }
    });

    tx();
    if (shouldCleanup) lastCleanupAtMs = now;
    if (shouldUpdate) lastAppliedAtMs = now;
    return { updatedUsers, cleanedSnapshots: shouldCleanup, throttled: !shouldUpdate };
  }

  return { apply };
}

function buildMieruUserStatsResponse(options) {
  const getAllUsers = typeof options.getAllUsers === 'function' ? options.getAllUsers : (() => []);
  const attachTrafficToUserPayload = options.attachTrafficToUserPayload;
  const telemetryService = options.telemetryService;
  const snapshot = telemetryService?.getLatestMieruSnapshot?.() || {
    rows: [],
    collected_at: null,
    collector_status: 'unavailable',
    stale: false
  };
  const liveByUsername = new Map((snapshot.rows || []).map((row) => [String(row.protocol_username || ''), row]));

  return getAllUsers().map((user) => {
    const live = liveByUsername.get(String(user.username || '')) || null;
    const mieruTraffic = live ? {
      username: user.username,
      uploadMB: Number(live.upload_bytes || 0) / 1048576,
      downloadMB: Number(live.download_bytes || 0) / 1048576,
      usedMB: (Number(live.upload_bytes || 0) + Number(live.download_bytes || 0)) / 1048576,
      lastSeen: live.last_seen_at || user.lastSeen || null
    } : {};

    return attachTrafficToUserPayload({
      username: user.username,
      email: user.email,
      expiry: user.expiry,
      protocols: JSON.parse(user.protocols || '[]'),
      quotaMB: user.quotaMB,
      usedMB: user.usedMB || 0,
      lastSeen: mieruTraffic.lastSeen || user.lastSeen || null
    }, { mieruTraffic });
  });
}

module.exports = {
  createLegacyMieruCompatibilityUpdater,
  buildMieruUserStatsResponse
};
