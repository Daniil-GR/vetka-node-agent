'use strict';

const path = require('node:path');
const fs = require('node:fs/promises');
const {
  DEFAULT_BOOTSTRAP_BYTES,
  DEFAULT_MAX_BYTES_PER_CYCLE,
  DEFAULT_MAX_LINE_BYTES,
  DEFAULT_MAX_LINES_PER_CYCLE,
  COLLECTOR_STATUS
} = require('./schema');

const DISCARD_REASON_FRAGMENT = 'fragment';
const DISCARD_REASON_OVERSIZED = 'oversized';

async function readJsonlIncremental(filePath, checkpoint = {}, options = {}) {
  const fsModule = options.fsModule || fs;
  const maxBytesPerCycle = options.maxBytesPerCycle || DEFAULT_MAX_BYTES_PER_CYCLE;
  const bootstrapBytes = options.bootstrapBytes || DEFAULT_BOOTSTRAP_BYTES;
  const maxLineBytes = options.maxLineBytes || DEFAULT_MAX_LINE_BYTES;
  const maxLinesPerCycle = options.maxLinesPerCycle || DEFAULT_MAX_LINES_PER_CYCLE;
  const rotationScanLimit = Number.isInteger(options.rotationScanLimit) && options.rotationScanLimit > 0
    ? options.rotationScanLimit
    : 64;
  const warnings = [];
  const counters = {
    linesRead: 0,
    linesSkippedMalformed: 0,
    linesSkippedOversized: 0,
    bootstrapClipped: false,
    rotationDetected: false,
    truncateDetected: false
  };
  const nextCheckpoint = {
    file_path: filePath,
    device: checkpoint.device || '',
    inode: checkpoint.inode || '',
    offset: Number.isFinite(checkpoint.offset) ? checkpoint.offset : 0,
    partial_trailing_line: '',
    discard_until_newline: checkpoint.discard_until_newline ? 1 : 0,
    discard_reason: checkpoint.discard_reason || '',
    rotated_source_path: checkpoint.rotated_source_path || '',
    last_successful_read_at: checkpoint.last_successful_read_at || null,
    last_error: null
  };

  if (!filePath) {
    nextCheckpoint.last_error = 'log path is not configured';
    return result(false, COLLECTOR_STATUS.UNAVAILABLE, warnings.concat('log path is not configured'), counters, nextCheckpoint, []);
  }

  const resolution = await resolveReadTarget({
    fsModule,
    filePath,
    checkpoint: nextCheckpoint,
    bootstrapBytes,
    rotationScanLimit,
    counters,
    warnings
  });

  if (!resolution.ok) {
    nextCheckpoint.last_error = resolution.error;
    return result(false, COLLECTOR_STATUS.UNAVAILABLE, warnings, counters, nextCheckpoint, []);
  }

  if (resolution.switchToCanonicalNext) {
    nextCheckpoint.device = '';
    nextCheckpoint.inode = '';
    nextCheckpoint.offset = 0;
    nextCheckpoint.discard_until_newline = 0;
    nextCheckpoint.discard_reason = '';
    nextCheckpoint.rotated_source_path = '';
    nextCheckpoint.last_successful_read_at = new Date().toISOString();
    return result(true, warnings.length ? COLLECTOR_STATUS.PARTIAL : COLLECTOR_STATUS.OK, warnings, counters, nextCheckpoint, []);
  }

  const {
    stat,
    sourcePath,
    startOffset,
    sourceIsRotatedTail
  } = resolution;
  const bytesAvailable = Math.max(0, stat.size - startOffset);
  const bytesToRead = Math.min(bytesAvailable, maxBytesPerCycle);
  if (bytesToRead <= 0) {
    if (sourceIsRotatedTail) {
      nextCheckpoint.device = '';
      nextCheckpoint.inode = '';
      nextCheckpoint.offset = 0;
      nextCheckpoint.discard_until_newline = 0;
      nextCheckpoint.discard_reason = '';
      nextCheckpoint.rotated_source_path = '';
    } else {
      nextCheckpoint.device = String(stat.dev ?? '');
      nextCheckpoint.inode = String(stat.ino ?? '');
      nextCheckpoint.offset = startOffset;
      nextCheckpoint.rotated_source_path = '';
    }
    nextCheckpoint.partial_trailing_line = '';
    nextCheckpoint.last_successful_read_at = new Date().toISOString();
    return result(true, warnings.length ? COLLECTOR_STATUS.PARTIAL : COLLECTOR_STATUS.OK, warnings, counters, nextCheckpoint, []);
  }

  let handle;
  let chunk = Buffer.alloc(0);
  try {
    handle = await fsModule.open(sourcePath, 'r');
    const buffer = Buffer.alloc(bytesToRead);
    const readResult = await handle.read(buffer, 0, bytesToRead, startOffset);
    chunk = buffer.subarray(0, readResult.bytesRead);
  } catch {
    nextCheckpoint.last_error = 'failed to read audit log incrementally';
    return result(false, COLLECTOR_STATUS.UNAVAILABLE, warnings.concat('failed to read audit log incrementally'), counters, nextCheckpoint, []);
  } finally {
    if (handle) {
      try { await handle.close(); } catch {}
    }
  }

  const scan = scanJsonlChunk(chunk, {
    startOffset,
    maxLineBytes,
    maxLinesPerCycle,
    discardUntilNewline: nextCheckpoint.discard_until_newline === 1,
    discardReason: nextCheckpoint.discard_reason,
    acceptTrailingRecordAtEof: sourceIsRotatedTail && startOffset + chunk.length >= stat.size
  });
  counters.linesRead = scan.lines.length;
  counters.linesSkippedOversized += scan.oversizedSkipped;
  if (scan.oversizedSkipped > 0) {
    warnings.push('one or more oversized audit log records were skipped');
  }
  warnings.push(...scan.warnings);

  nextCheckpoint.device = String(stat.dev ?? '');
  nextCheckpoint.inode = String(stat.ino ?? '');
  nextCheckpoint.offset = scan.nextOffset;
  nextCheckpoint.partial_trailing_line = '';
  nextCheckpoint.discard_until_newline = scan.discardUntilNewline ? 1 : 0;
  nextCheckpoint.discard_reason = scan.discardReason || '';
  nextCheckpoint.rotated_source_path = sourceIsRotatedTail ? sourcePath : '';
  nextCheckpoint.last_successful_read_at = new Date().toISOString();

  if (sourceIsRotatedTail && scan.nextOffset >= stat.size && !scan.discardUntilNewline) {
    nextCheckpoint.device = '';
    nextCheckpoint.inode = '';
    nextCheckpoint.offset = 0;
    nextCheckpoint.discard_until_newline = 0;
    nextCheckpoint.discard_reason = '';
    nextCheckpoint.rotated_source_path = '';
  }

  return result(true, warnings.length ? COLLECTOR_STATUS.PARTIAL : COLLECTOR_STATUS.OK, warnings, counters, nextCheckpoint, scan.lines);
}

async function resolveReadTarget({ fsModule, filePath, checkpoint, bootstrapBytes, rotationScanLimit, counters, warnings }) {
  const currentStat = await safeStat(fsModule, filePath);
  if (checkpoint.rotated_source_path) {
    const rotatedStat = await safeStat(fsModule, checkpoint.rotated_source_path);
    if (rotatedStat && matchesInode(checkpoint, rotatedStat)) {
      return {
        ok: true,
        stat: rotatedStat,
        sourcePath: checkpoint.rotated_source_path,
        startOffset: checkpoint.offset,
        sourceIsRotatedTail: true
      };
    }
    warnings.push('rotated audit tail could not be resumed; switching to current log path');
    checkpoint.rotated_source_path = '';
    checkpoint.device = '';
    checkpoint.inode = '';
    checkpoint.offset = 0;
    checkpoint.discard_until_newline = 0;
    checkpoint.discard_reason = '';
  }

  if (!currentStat) {
    return { ok: false, error: 'log file is unavailable' };
  }

  const currentDevice = String(currentStat.dev ?? '');
  const currentInode = String(currentStat.ino ?? '');
  let startOffset = checkpoint.offset;

  if (!checkpoint.last_successful_read_at && currentStat.size > bootstrapBytes) {
    startOffset = Math.max(0, currentStat.size - bootstrapBytes);
    checkpoint.discard_until_newline = startOffset > 0 ? 1 : 0;
    checkpoint.discard_reason = startOffset > 0 ? DISCARD_REASON_FRAGMENT : '';
    checkpoint.offset = startOffset;
    counters.bootstrapClipped = true;
    warnings.push('naive log bootstrap was clipped to a bounded tail window');
  } else if (checkpoint.device && checkpoint.inode && (checkpoint.device !== currentDevice || checkpoint.inode !== currentInode)) {
    counters.rotationDetected = true;
    warnings.push('audit log rotation detected');
    const rotatedPath = await findRotatedSourcePath(fsModule, filePath, checkpoint.device, checkpoint.inode, rotationScanLimit);
    if (rotatedPath) {
      checkpoint.rotated_source_path = rotatedPath;
      const rotatedStat = await safeStat(fsModule, rotatedPath);
      if (rotatedStat) {
        return {
          ok: true,
          stat: rotatedStat,
          sourcePath: rotatedPath,
          startOffset: checkpoint.offset,
          sourceIsRotatedTail: true
        };
      }
    }
    warnings.push('rotated audit tail was not found; unread rotated lines may be lost');
    checkpoint.device = '';
    checkpoint.inode = '';
    checkpoint.offset = 0;
    checkpoint.discard_until_newline = 0;
    checkpoint.discard_reason = '';
    startOffset = 0;
  } else if (currentStat.size < startOffset) {
    counters.truncateDetected = true;
    checkpoint.offset = 0;
    checkpoint.discard_until_newline = 0;
    checkpoint.discard_reason = '';
    startOffset = 0;
  }

  return {
    ok: true,
    stat: currentStat,
    sourcePath: filePath,
    startOffset,
    sourceIsRotatedTail: false
  };
}

function scanJsonlChunk(buffer, options) {
  const lines = [];
  const warnings = [];
  let oversizedSkipped = 0;
  let discardUntilNewline = options.discardUntilNewline === true;
  let discardReason = options.discardReason || '';
  let lineStartIndex = 0;
  let lineStartOffset = options.startOffset;
  let nextOffset = options.startOffset;
  let lineLimitHit = false;

  for (let index = 0; index < buffer.length; index += 1) {
    if (buffer[index] !== 0x0a) continue;

    const newlineOffset = options.startOffset + index + 1;
    const lineBytes = buffer.subarray(lineStartIndex, index);

    if (discardUntilNewline) {
      discardUntilNewline = false;
      discardReason = '';
      nextOffset = newlineOffset;
      lineStartIndex = index + 1;
      lineStartOffset = newlineOffset;
      continue;
    }

    if (lineBytes.length > options.maxLineBytes) {
      oversizedSkipped += 1;
      nextOffset = newlineOffset;
      lineStartIndex = index + 1;
      lineStartOffset = newlineOffset;
      continue;
    }

    if (lines.length >= options.maxLinesPerCycle) {
      warnings.push('naive log processing hit the per-cycle line limit');
      nextOffset = lineStartOffset;
      lineLimitHit = true;
      break;
    }

    if (lineBytes.length > 0) {
      lines.push(lineBytes.toString('utf8'));
    }
    nextOffset = newlineOffset;
    lineStartIndex = index + 1;
    lineStartOffset = newlineOffset;
  }

  if (!lineLimitHit) {
    const trailing = buffer.subarray(lineStartIndex);
    if (discardUntilNewline) {
      if (options.acceptTrailingRecordAtEof) {
        discardUntilNewline = false;
        discardReason = '';
      }
      nextOffset = options.startOffset + buffer.length;
    } else if (trailing.length > options.maxLineBytes) {
      oversizedSkipped += 1;
      if (options.acceptTrailingRecordAtEof) {
        discardUntilNewline = false;
        discardReason = '';
      } else {
        discardUntilNewline = true;
        discardReason = DISCARD_REASON_OVERSIZED;
      }
      nextOffset = options.startOffset + buffer.length;
    } else if (trailing.length > 0) {
      if (options.acceptTrailingRecordAtEof && lines.length < options.maxLinesPerCycle) {
        lines.push(trailing.toString('utf8'));
        nextOffset = options.startOffset + buffer.length;
      } else {
        nextOffset = lineStartOffset;
      }
    } else {
      nextOffset = options.startOffset + buffer.length;
    }
  }

  return {
    lines,
    warnings,
    oversizedSkipped,
    discardUntilNewline,
    discardReason,
    nextOffset
  };
}

async function findRotatedSourcePath(fsModule, filePath, expectedDevice, expectedInode, limit) {
  const dir = path.dirname(filePath);
  const basename = path.basename(filePath);
  let entries;
  try {
    entries = await fsModule.readdir(dir, { withFileTypes: true });
  } catch {
    return '';
  }

  let checked = 0;
  for (const entry of entries) {
    if (checked >= limit) break;
    if (!entry.isFile()) continue;
    if (entry.name === basename) continue;
    if (!entry.name.startsWith(basename)) continue;
    if (/\.gz$|\.xz$|\.bz2$|\.zip$/i.test(entry.name)) continue;
    const candidate = path.join(dir, entry.name);
    const stat = await safeStat(fsModule, candidate);
    checked += 1;
    if (!stat) continue;
    if (String(stat.dev ?? '') === String(expectedDevice || '') && String(stat.ino ?? '') === String(expectedInode || '')) {
      return candidate;
    }
  }
  return '';
}

async function safeStat(fsModule, filePath) {
  try {
    return await fsModule.stat(filePath);
  } catch {
    return null;
  }
}

function matchesInode(checkpoint, stat) {
  return String(checkpoint.device || '') === String(stat.dev ?? '')
    && String(checkpoint.inode || '') === String(stat.ino ?? '');
}

function parseNaiveAuthEvent(line, normalizeAuditIp) {
  let row;
  try { row = JSON.parse(line); } catch { return null; }
  const username = String(row.username || '').trim();
  if (!username) return null;
  const remoteIp = normalizeAuditIp(row.remote_ip || row.remoteIp || row.remote_addr);
  if (!remoteIp) return null;
  const ts = parseTimestamp(row.ts ?? row.time ?? row.timestamp);
  if (!ts) return null;
  return {
    protocol_username: username,
    client_ip: remoteIp,
    first_seen_at: ts,
    last_seen_at: ts,
    upload_bytes: 0,
    download_bytes: 0,
    source: 'naive-audit',
    traffic_scope: 'telemetry-retention-window',
    ip_observed: true,
    traffic_observed: false
  };
}

function parseNaiveTrafficEvent(line, normalizeAuditIp) {
  let row;
  try { row = JSON.parse(line); } catch { return null; }
  if (row.event && row.event !== 'connect_closed') return null;
  const username = String(row.username || '').trim();
  if (!username) return null;
  const remoteIp = normalizeAuditIp(row.remote_ip || row.remoteIp || row.remote_addr);
  if (!remoteIp) return null;
  const ts = parseTimestamp(row.ts ?? row.time ?? row.timestamp);
  if (!ts) return null;
  return {
    protocol_username: username,
    client_ip: remoteIp,
    first_seen_at: ts,
    last_seen_at: ts,
    upload_bytes: nonNegativeInt(row.bytes_client_to_target),
    download_bytes: nonNegativeInt(row.bytes_target_to_client),
    source: 'naive-audit',
    traffic_scope: 'telemetry-retention-window',
    ip_observed: true,
    traffic_observed: true
  };
}

function nonNegativeInt(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) return 0;
  return Math.trunc(parsed);
}

function parseTimestamp(value) {
  if (value === undefined || value === null || value === '') return null;
  const raw = String(value).trim();
  if (/^\d+(\.\d+)?$/.test(raw)) {
    const numeric = Number(raw);
    if (!Number.isFinite(numeric)) return null;
    return toIsoFromMillis(numeric < 1000000000000 ? numeric * 1000 : numeric);
  }
  const parsed = new Date(raw);
  return Number.isNaN(parsed.getTime()) ? null : toIsoFromMillis(parsed.getTime());
}

function toIsoFromMillis(value) {
  if (!Number.isFinite(value) || Math.abs(value) > 8640000000000000) return null;
  const date = new Date(value);
  const ms = date.getTime();
  return Number.isFinite(ms) ? date.toISOString() : null;
}

function combineNaiveStatuses(parts) {
  const statuses = parts.filter(Boolean);
  if (!statuses.length) return COLLECTOR_STATUS.UNAVAILABLE;
  if (statuses.every((status) => status === COLLECTOR_STATUS.OK)) return COLLECTOR_STATUS.OK;
  if (statuses.every((status) => status === COLLECTOR_STATUS.UNAVAILABLE)) return COLLECTOR_STATUS.UNAVAILABLE;
  return COLLECTOR_STATUS.PARTIAL;
}

function result(ok, status, warnings, counters, checkpoint, lines) {
  return { ok, status, warnings, counters, checkpoint, lines };
}

module.exports = {
  DISCARD_REASON_FRAGMENT,
  DISCARD_REASON_OVERSIZED,
  readJsonlIncremental,
  parseNaiveAuthEvent,
  parseNaiveTrafficEvent,
  parseTimestamp,
  combineNaiveStatuses
};
