'use strict';

const DEFAULT_SESSION_TTL_MINUTES = 10;
const DEFAULT_HISTORY_TTL_HOURS = 24;
const DEFAULT_COLLECT_INTERVAL_SECONDS = 15;
const MIN_COLLECT_INTERVAL_SECONDS = 5;
const MAX_COLLECT_INTERVAL_SECONDS = 300;
const TELEMETRY_HARD_SESSION_LIMIT = 5000;
const DEFAULT_MAX_BYTES_PER_CYCLE = 1024 * 1024;
const DEFAULT_BOOTSTRAP_BYTES = 1024 * 1024;
const DEFAULT_MAX_LINE_BYTES = 64 * 1024;
const DEFAULT_MAX_LINES_PER_CYCLE = 1025;

const COLLECTOR_STATUS = Object.freeze({
  OK: 'ok',
  PARTIAL: 'partial',
  UNAVAILABLE: 'unavailable',
  DISABLED: 'disabled'
});

function normalizeSessionTtlMinutes(value) {
  const parsed = parseInt(value, 10);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : DEFAULT_SESSION_TTL_MINUTES;
}

function normalizeHistoryTtlHours(value) {
  const parsed = parseInt(value, 10);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : DEFAULT_HISTORY_TTL_HOURS;
}

function normalizeCollectIntervalSeconds(value) {
  const parsed = parseInt(value, 10);
  if (!Number.isInteger(parsed)) return DEFAULT_COLLECT_INTERVAL_SECONDS;
  return Math.min(MAX_COLLECT_INTERVAL_SECONDS, Math.max(MIN_COLLECT_INTERVAL_SECONDS, parsed));
}

function sessionTtlSeconds(cfg) {
  return normalizeSessionTtlMinutes(cfg?.sessionTtlMinutes) * 60;
}

function historyTtlSeconds(cfg) {
  return normalizeHistoryTtlHours(cfg?.ipHistoryTtlHours) * 3600;
}

module.exports = {
  COLLECTOR_STATUS,
  DEFAULT_SESSION_TTL_MINUTES,
  DEFAULT_HISTORY_TTL_HOURS,
  DEFAULT_COLLECT_INTERVAL_SECONDS,
  MIN_COLLECT_INTERVAL_SECONDS,
  MAX_COLLECT_INTERVAL_SECONDS,
  TELEMETRY_HARD_SESSION_LIMIT,
  DEFAULT_MAX_BYTES_PER_CYCLE,
  DEFAULT_BOOTSTRAP_BYTES,
  DEFAULT_MAX_LINE_BYTES,
  DEFAULT_MAX_LINES_PER_CYCLE,
  normalizeSessionTtlMinutes,
  normalizeHistoryTtlHours,
  normalizeCollectIntervalSeconds,
  sessionTtlSeconds,
  historyTtlSeconds
};
