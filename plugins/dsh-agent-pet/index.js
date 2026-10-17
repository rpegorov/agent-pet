/** agent-pet for DeepSeek Harness, host half: mirrors session state into the agent-pet event log and serves a loopback command queue. */
import { createServer } from 'node:http';
import { appendFileSync, existsSync, mkdirSync, renameSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { homedir } from 'node:os';
import { randomUUID } from 'node:crypto';

const HOST = '127.0.0.1';
const DEFAULT_PORTS = [50399, 50400, 50401];
const PORTS_ENV = 'AGENT_PET_DSH_PORTS';
const NONCE_ENV = 'AGENT_PET_DSH_NONCE';
const SERVICE = 'agent-pet';
const MAX_BODY = 4096;
const COMMAND_TTL_MS = 20000;
const MAX_QUEUE = 8;
// Origins the Harness web UI is served from; only these pages may read the queue.
const UI_ORIGINS = new Set(['http://127.0.0.1:50306', 'http://localhost:50306']);
const COMMAND_TYPES = new Set(['new-chat', 'open-session']);

const MOODS = { thinking: 'working', done: 'complete', error: 'attention', idle: 'idle' };
const LABEL_MAX = 40;
const TITLE_MAX = 60;
const TITLE_EVENT_WINDOW = 400;
const ROTATE_BYTES = 512 * 1024;
const DIR_MODE = 0o700;
const FILE_MODE = 0o600;

/** Ports the bridge tries in order; the overlay and the client probe the defaults. */
function bridgePorts() {
  const raw = process.env[PORTS_ENV];
  const ports = raw ? raw.split(',').map((item) => Number.parseInt(item, 10)).filter((n) => Number.isInteger(n) && n >= 0) : [];
  return ports.length ? ports : DEFAULT_PORTS;
}

function logPath() {
  return process.env.AGENT_PET_LOG || join(homedir(), '.agent-pet', 'events.jsonl');
}

/** The pet must never break the Harness, so every failure here is swallowed. */
function emit(entry, cwd) {
  try {
    const event = {
      v: 1,
      agent: 'dsh',
      session: entry.id,
      mood: MOODS[entry.status] || 'idle',
      label: String(entry.title || entry.project || entry.short || '').slice(0, LABEL_MAX),
      app: 'dsh',
      ts: Date.now() / 1000,
    };
    if (cwd) event.cwd = String(cwd);
    const file = logPath();
    mkdirSync(dirname(file), { recursive: true, mode: DIR_MODE });
    if (existsSync(file) && statSync(file).size > ROTATE_BYTES) renameSync(file, `${file}.1`);
    appendFileSync(file, `${JSON.stringify(event)}\n`, { flag: 'a', mode: FILE_MODE });
  } catch {
    /* ignored on purpose */
  }
}

function messageText(message) {
  const content = message && message.content;
  if (typeof content === 'string') return content.replace(/\s+/g, ' ').trim();
  if (Array.isArray(content)) {
    for (const block of content) {
      if (block && block.type === 'text' && typeof block.text === 'string') {
        return block.text.replace(/\s+/g, ' ').trim();
      }
    }
  }
  return '';
}

/** Harness names sessions itself; otherwise the first user line is the closest thing. */
function sessionTitle(session) {
  try {
    if (!session || typeof session.snapshotEvents !== 'function') return null;
    let named = null;
    let firstUser = null;
    for (const event of session.snapshotEvents(0, TITLE_EVENT_WINDOW)) {
      if (!event) continue;
      if (event.type === 'session/title') {
        const title = event.data && event.data.title;
        if (typeof title === 'string' && title.trim()) named = title.trim();
      } else if (!firstUser && event.type === 'user/message') {
        firstUser = messageText(event.data && event.data.message) || null;
      }
    }
    return (named || firstUser || '').slice(0, TITLE_MAX) || null;
  } catch {
    return null;
  }
}

function describe(store, sessionId) {
  let session = null;
  try {
    session = store && typeof store.get === 'function' ? store.get(sessionId) : null;
  } catch {
    session = null;
  }
  const cwd = (session && session.header && session.header.cwd) || null;
  const parts = cwd ? String(cwd).split('/').filter(Boolean) : [];
  return {
    cwd,
    project: parts.length ? parts[parts.length - 1] : null,
    title: sessionTitle(session),
    short: String(sessionId).replace(/[^0-9a-zA-Z]/g, '').slice(-6).toLowerCase() || null,
  };
}

function mediaType(header) {
  return String(header || '').split(';')[0].trim().toLowerCase();
}

function reply(res, status, body, corsOrigin) {
  const text = JSON.stringify(body);
  const headers = {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(text),
    'cache-control': 'no-store',
  };
  if (corsOrigin) {
    headers['access-control-allow-origin'] = corsOrigin;
    headers.vary = 'Origin';
  }
  res.writeHead(status, headers);
  res.end(text);
}

function readBody(req) {
  return new Promise((resolve) => {
    let size = 0;
    const chunks = [];
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY) {
        req.destroy();
        resolve(null);
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      try {
        const parsed = chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {};
        resolve(parsed && typeof parsed === 'object' ? parsed : null);
      } catch {
        resolve(null);
      }
    });
    req.on('error', () => resolve(null));
  });
}

export const inject = ['sessions'];

export function apply(ctx) {
  const sessions = new Map();
  const ports = bridgePorts();
  const nonce = process.env[NONCE_ENV] || randomUUID();
  let boundPort = 0;
  let queue = [];
  let server = null;

  const sessionStore = () => {
    try {
      if (ctx.sessions) return ctx.sessions;
      return typeof ctx.get === 'function' ? ctx.get('sessions') : null;
    } catch {
      return null;
    }
  };

  const track = (sessionId, status) => {
    if (!sessionId) return;
    const info = describe(sessionStore(), sessionId);
    const entry = { ...(sessions.get(sessionId) || { id: sessionId }), status };
    entry.title = info.title || entry.title || null;
    entry.project = info.project || entry.project || null;
    entry.short = info.short || entry.short || null;
    sessions.set(sessionId, entry);
    emit(entry, info.cwd);
  };

  const running = new Set();

  ctx.on('api-session/status', (sessionId, isRunning) => {
    if (!sessionId) return;
    if (isRunning) {
      running.add(sessionId);
      track(sessionId, 'thinking');
    } else if (running.delete(sessionId)) {
      track(sessionId, 'done');
    } else {
      track(sessionId, 'idle');
    }
  });

  ctx.on('api-session/error', (sessionId) => {
    running.delete(sessionId);
    track(sessionId, 'error');
  });

  ctx.on('api-session/activity', (sessionId) => {
    if (sessionId && !sessions.has(sessionId)) track(sessionId, 'idle');
  });

  const hostAllowed = (req) => {
    const host = String(req.headers.host || '');
    return host === `${HOST}:${boundPort}` || host === `localhost:${boundPort}`;
  };

  // Browsers always announce a cross-origin caller with Origin or Sec-Fetch-Site; local processes send neither.
  const pageOrigin = (req) => req.headers.origin || null;
  const foreignBrowser = (req) => {
    const origin = pageOrigin(req);
    if (origin) return !UI_ORIGINS.has(origin);
    return Boolean(req.headers['sec-fetch-site']);
  };

  const handler = async (req, res) => {
    if (!hostAllowed(req)) return reply(res, 403, { error: 'forbidden host' });
    const path = new URL(req.url || '/', `http://${HOST}`).pathname;
    if (req.method === 'GET') {
      if (foreignBrowser(req)) return reply(res, 403, { error: 'forbidden origin' });
      const cors = pageOrigin(req);
      if (path === '/health') return reply(res, 200, { ok: true, service: SERVICE, nonce }, cors);
      if (path === '/cmd') {
        const now = Date.now();
        const batch = queue.filter((command) => now - command.at <= COMMAND_TTL_MS);
        queue = [];
        return reply(res, 200, { commands: batch }, cors);
      }
    }
    if (req.method === 'POST' && path === '/cmd') {
      // Commands come from local processes only: a page cannot forge a JSON content type without a preflight.
      if (pageOrigin(req) || req.headers['sec-fetch-site']) return reply(res, 403, { error: 'forbidden origin' });
      if (mediaType(req.headers['content-type']) !== 'application/json') {
        return reply(res, 415, { error: 'application/json required' });
      }
      const body = await readBody(req);
      if (!body || !COMMAND_TYPES.has(body.type)) return reply(res, 400, { error: 'unknown command' });
      const sessionId = typeof body.sessionId === 'string' && body.sessionId ? body.sessionId : null;
      if (body.type === 'open-session' && !sessionId) return reply(res, 400, { error: 'sessionId required' });
      queue.push({ type: body.type, sessionId, at: Date.now() });
      queue = queue.slice(-MAX_QUEUE);
      return reply(res, 200, { ok: true, queued: queue.length });
    }
    return reply(res, 404, { error: 'not found' });
  };

  const listen = (index) => {
    if (index >= ports.length) return;
    const candidate = createServer((req, res) => {
      handler(req, res).catch(() => {
        try {
          reply(res, 500, { error: 'internal' });
        } catch {
          /* the socket is already gone */
        }
      });
    });
    candidate.once('error', () => {
      try {
        candidate.close();
      } catch {
        /* already closed */
      }
      listen(index + 1);
    });
    candidate.listen(ports[index], HOST, () => {
      server = candidate;
      boundPort = candidate.address().port;
      candidate.on('error', () => {});
    });
  };
  listen(0);

  ctx.effect(
    () => () => {
      if (server) {
        try {
          server.close();
        } catch {
          /* already closed */
        }
        server = null;
      }
    },
    'agent-pet:loopback-bridge',
  );
}
