'use strict';

const { COLLECTOR_STATUS } = require('./schema');

function parseSizeToBytes(value) {
  const match = String(value || '').trim().match(/^([\d.]+)\s*([KMGT]?i?B|B)$/i);
  if (!match) return null;
  const amount = Number(match[1]);
  if (!Number.isFinite(amount) || amount < 0) return null;
  const unit = match[2].toUpperCase();
  switch (unit) {
    case 'B': return Math.trunc(amount);
    case 'KB': return Math.trunc(amount * 1000);
    case 'KIB': return Math.trunc(amount * 1024);
    case 'MB': return Math.trunc(amount * 1000 * 1000);
    case 'MIB': return Math.trunc(amount * 1024 * 1024);
    case 'GB': return Math.trunc(amount * 1000 * 1000 * 1000);
    case 'GIB': return Math.trunc(amount * 1024 * 1024 * 1024);
    case 'TB': return Math.trunc(amount * 1000 * 1000 * 1000 * 1000);
    case 'TIB': return Math.trunc(amount * 1024 * 1024 * 1024 * 1024);
    default: return null;
  }
}

function parseMitaUsersTable(raw, nowIso = new Date().toISOString()) {
  const rows = [];
  let skippedRows = 0;
  let invalidLastActiveRows = 0;
  if (!raw) return { rows, skippedRows, invalidLastActiveRows };
  for (const rawLine of String(raw).split('\n')) {
    const line = rawLine.trim();
    if (!line) continue;
    if (/^user\b/i.test(line) || /^[-=\s]+$/.test(line)) continue;
    const cols = line.split(/\s+/);
    if (cols.length < 6) {
      skippedRows += 1;
      continue;
    }
    const username = cols[0];
    const lastActiveRaw = cols[1];
    const sizeCols = cols.slice(-4);
    const parsedSizes = sizeCols.map(parseSizeToBytes);
    if (!username || parsedSizes.some(v => v === null)) {
      skippedRows += 1;
      continue;
    }
    const lastSeenAt = parseLastActive(lastActiveRaw);
    if (!lastSeenAt) {
      invalidLastActiveRows += 1;
      continue;
    }
    rows.push({
      protocol_username: username,
      client_ip: null,
      first_seen_at: nowIso,
      last_seen_at: lastSeenAt,
      download_bytes: parsedSizes[2],
      upload_bytes: parsedSizes[3],
      ip_observed: false,
      traffic_observed: true,
      source: 'mita-get-users',
      traffic_scope: 'mieru-30-day-counter'
    });
  }
  return { rows, skippedRows, invalidLastActiveRows };
}

function parseLastActive(value) {
  const raw = String(value || '').trim();
  if (!/^\d{4}-\d{2}-\d{2}T/.test(raw)) return null;
  const parsed = new Date(raw);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

async function collectMieruTelemetry(options) {
  const runCommand = options.runCommand;
  const nowIso = options.nowIso || new Date().toISOString();
  try {
    const raw = await runCommand(options.abortSignal);
    const parsed = parseMitaUsersTable(raw, nowIso);
    const warnings = [];
    if (parsed.skippedRows > 0) warnings.push('some unrecognized rows from mita get users were skipped');
    if (parsed.invalidLastActiveRows > 0) warnings.push('some mita rows had invalid LastActive and were ignored');
    const usableResult = parsed.rows.length > 0 || (parsed.rows.length === 0 && parsed.skippedRows === 0 && parsed.invalidLastActiveRows === 0);
    return {
      status: (parsed.skippedRows > 0 || parsed.invalidLastActiveRows > 0) ? COLLECTOR_STATUS.PARTIAL : COLLECTOR_STATUS.OK,
      rows: parsed.rows,
      warnings,
      details: {
        records_processed: parsed.rows.length,
        rows_skipped: parsed.skippedRows,
        invalid_last_active_rows: parsed.invalidLastActiveRows
      },
      lastSuccessfulCollectionAt: usableResult ? nowIso : null,
      usableResult
    };
  } catch (err) {
    return {
      status: COLLECTOR_STATUS.UNAVAILABLE,
      rows: [],
      warnings: ['mita runtime telemetry is temporarily unavailable'],
      details: {
        records_processed: 0,
        rows_skipped: 0
      },
      lastError: 'mita get users failed',
      usableResult: false
    };
  }
}

module.exports = {
  parseSizeToBytes,
  parseLastActive,
  parseMitaUsersTable,
  collectMieruTelemetry
};
