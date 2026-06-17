'use strict';

function requestClientIp(req) {
  const raw = (req.headers?.['x-forwarded-for'] || req.socket?.remoteAddress || req.ip || '')
    .toString()
    .split(',')[0]
    .trim();
  return raw.replace(/^::ffff:/, '').replace(/^::1$/, '127.0.0.1');
}

function isRequestIpAllowed(req, cfg) {
  const allowed = Array.isArray(cfg?.backendAllowedIps) ? cfg.backendAllowedIps.filter(Boolean) : [];
  if (!allowed.length) return cfg?.allowAnyBackendIp === true;
  return allowed.includes(requestClientIp(req));
}

function authorizeNodeRequest(req, cfg) {
  const expected = String(cfg?.nodeSecret || '').trim();
  const auth = String(req.headers?.authorization || '').trim();
  const nodeId = String(req.headers?.['x-node-id'] || '').trim();
  if (!expected) return { ok: false, status: 503, payload: { ok: false, error: 'NODE_SECRET is not configured' } };
  if (!isRequestIpAllowed(req, cfg)) return { ok: false, status: 403, payload: { ok: false, error: 'source IP is not allowed' } };
  if (auth !== `Bearer ${expected}`) return { ok: false, status: 401, payload: { ok: false, error: 'invalid bearer token' } };
  if (nodeId && nodeId !== cfg?.nodeId) return { ok: false, status: 403, payload: { ok: false, error: 'X-Node-Id does not match this node' } };
  return { ok: true };
}

function createTelemetryRouteHandler(telemetryService) {
  return (req, res) => {
    const includeRecent = String(req.query?.include_recent || '').trim().toLowerCase() === 'true';
    res.json(telemetryService.buildSessionsResponse({ includeRecent }));
  };
}

module.exports = {
  requestClientIp,
  isRequestIpAllowed,
  authorizeNodeRequest,
  createTelemetryRouteHandler
};
