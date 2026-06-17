'use strict';

const net = require('node:net');

function normalizeAuditIp(value) {
  const raw = String(value || '').trim();
  if (!raw) return '';

  if (/^::ffff:\d{1,3}(?:\.\d{1,3}){3}$/i.test(raw)) {
    const mapped = raw.slice('::ffff:'.length);
    return net.isIP(mapped) === 4 ? mapped : '';
  }

  if (net.isIP(raw)) return raw;

  const bracketed = raw.match(/^\[([^\]]+)\]:(\d+)$/);
  if (bracketed && net.isIP(bracketed[1])) return bracketed[1];

  const ipv4WithPort = raw.match(/^(\d{1,3}(?:\.\d{1,3}){3}):(\d+)$/);
  if (ipv4WithPort && net.isIP(ipv4WithPort[1]) === 4) return ipv4WithPort[1];

  return '';
}

module.exports = {
  normalizeAuditIp
};
