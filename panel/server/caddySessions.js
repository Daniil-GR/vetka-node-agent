'use strict';

const { normalizeAuditIp: defaultNormalizeAuditIp } = require('./ip');

function parseAccessLogTimestamp(value) {
  if (value === undefined || value === null || value === '') return new Date();
  const raw = String(value).trim();
  if (/^\d+(\.\d+)?$/.test(raw)) {
    const numeric = Number(raw);
    if (!Number.isFinite(numeric)) return null;
    return new Date(numeric < 1000000000000 ? numeric * 1000 : numeric);
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function parseLegacyCaddySessionRecord(line, options = {}) {
  if (!String(line || '').trim()) return null;
  const normalizeAuditIp = typeof options.normalizeAuditIp === 'function'
    ? options.normalizeAuditIp
    : defaultNormalizeAuditIp;

  let row;
  try {
    row = JSON.parse(line);
  } catch {
    return null;
  }

  const req = row.request || {};
  const method = row.method || req.method || '';
  if (method && method !== 'CONNECT') return null;

  const remoteIp = normalizeAuditIp(req.remote_ip || row.remote_ip || row.remote_addr);
  if (!remoteIp) return null;

  const parsedTs = parseAccessLogTimestamp(row.ts ?? row.time ?? row.timestamp);
  if (!parsedTs) return null;

  return {
    remoteIp,
    seen: parsedTs.toISOString(),
    host: row.host || req.host || req.uri || ''
  };
}

function collectLegacyCaddySessionsFromContent(content, options = {}) {
  const byIp = new Map();
  for (const line of String(content || '').split('\n')) {
    const parsed = parseLegacyCaddySessionRecord(line, options);
    if (!parsed) continue;
    const existing = byIp.get(parsed.remoteIp) || {
      remoteIp: parsed.remoteIp,
      firstSeen: parsed.seen,
      lastSeen: parsed.seen,
      requestCount: 0,
      hosts: new Set(),
      protocol: 'naive',
      username: null
    };
    existing.requestCount += 1;
    if (parsed.host) existing.hosts.add(String(parsed.host));
    if (parsed.seen < existing.firstSeen) existing.firstSeen = parsed.seen;
    if (parsed.seen > existing.lastSeen) existing.lastSeen = parsed.seen;
    byIp.set(parsed.remoteIp, existing);
  }
  return Array.from(byIp.values());
}

module.exports = {
  collectLegacyCaddySessionsFromContent,
  parseLegacyCaddySessionRecord
};
