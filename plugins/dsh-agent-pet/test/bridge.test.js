import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import net from 'node:net';
import { randomUUID } from 'node:crypto';
import { apply } from '../index.js';

const UI_ORIGIN = 'http://127.0.0.1:50306';
const DEFAULT_PORTS = [50399, 50400, 50401];

function request(port, { method = 'GET', path = '/health', headers = {}, body } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, method, path, headers }, (res) => {
      let text = '';
      res.on('data', (chunk) => { text += chunk; });
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, text }));
    });
    req.on('error', reject);
    if (body !== undefined) req.write(body);
    req.end();
  });
}

function freePort() {
  return new Promise((resolve, reject) => {
    const probe = net.createServer();
    probe.once('error', reject);
    probe.listen(0, '127.0.0.1', () => {
      const { port } = probe.address();
      probe.close(() => resolve(port));
    });
  });
}

// Binds the bridge to a private port so the tests never touch a Harness bridge that is already running.
async function startBridge() {
  const port = await freePort();
  assert.ok(!DEFAULT_PORTS.includes(port));
  const nonce = randomUUID();
  process.env.AGENT_PET_LOG = `${process.env.TMPDIR || '/tmp'}/agent-pet-bridge-test-${process.pid}.jsonl`;
  process.env.AGENT_PET_DSH_PORTS = String(port);
  process.env.AGENT_PET_DSH_NONCE = nonce;
  let dispose;
  apply({ sessions: null, on() {}, effect(fn) { dispose = fn(); } });
  await new Promise((resolve) => setTimeout(resolve, 200));
  const health = JSON.parse((await request(port)).text);
  assert.equal(health.nonce, nonce, 'talking to a different bridge instance');
  console.log(`bridge test port: ${port}`);
  return { port, stop: dispose };
}

const json = (type, extra = {}) => JSON.stringify({ type, ...extra });

test('bridge access control', async (t) => {
  const { port, stop } = await startBridge();
  t.after(() => stop());

  await t.test('JSON without Origin is queued', async () => {
    const res = await request(port, { method: 'POST', path: '/cmd', headers: { 'content-type': 'application/json' }, body: json('new-chat') });
    assert.equal(res.status, 200);
    const drained = await request(port, { path: '/cmd' });
    assert.deepEqual(JSON.parse(drained.text).commands.map((c) => c.type), ['new-chat']);
  });

  await t.test('text/plain POST from a foreign page is refused and not queued', async () => {
    const res = await request(port, { method: 'POST', path: '/cmd', headers: { 'content-type': 'text/plain', origin: 'http://evil.example' }, body: json('new-chat') });
    assert.equal(res.status, 403);
    assert.equal(JSON.parse((await request(port, { path: '/cmd' })).text).commands.length, 0);
  });

  await t.test('text/plain POST without Origin is refused', async () => {
    const res = await request(port, { method: 'POST', path: '/cmd', headers: { 'content-type': 'text/plain' }, body: json('new-chat') });
    assert.equal(res.status, 415);
  });

  await t.test('content type must match exactly, parameters aside', async () => {
    const wrong = await request(port, { method: 'POST', path: '/cmd', headers: { 'content-type': 'application/jsonx' }, body: json('new-chat') });
    assert.equal(wrong.status, 415);
    const ok = await request(port, { method: 'POST', path: '/cmd', headers: { 'content-type': ' Application/JSON ; charset=utf-8' }, body: json('new-chat') });
    assert.equal(ok.status, 200);
    await request(port, { path: '/cmd' });
  });

  await t.test('POST from the UI origin is still refused', async () => {
    const res = await request(port, { method: 'POST', path: '/cmd', headers: { 'content-type': 'application/json', origin: UI_ORIGIN }, body: json('new-chat') });
    assert.equal(res.status, 403);
  });

  await t.test('wrong Host is refused (DNS rebinding)', async () => {
    const res = await request(port, { path: '/health', headers: { host: 'rebind.example' } });
    assert.equal(res.status, 403);
  });

  await t.test('GET from the UI origin gets exactly that CORS origin', async () => {
    const res = await request(port, { path: '/cmd', headers: { origin: UI_ORIGIN } });
    assert.equal(res.status, 200);
    assert.equal(res.headers['access-control-allow-origin'], UI_ORIGIN);
  });

  await t.test('GET from a foreign origin is refused and does not drain the queue', async () => {
    await request(port, { method: 'POST', path: '/cmd', headers: { 'content-type': 'application/json' }, body: json('open-session', { sessionId: 's1' }) });
    const res = await request(port, { path: '/cmd', headers: { origin: 'http://evil.example' } });
    assert.equal(res.status, 403);
    assert.equal(res.headers['access-control-allow-origin'], undefined);
    const drained = await request(port, { path: '/cmd' });
    assert.equal(JSON.parse(drained.text).commands.length, 1);
  });

  await t.test('no-cors browser GET is refused', async () => {
    const res = await request(port, { path: '/cmd', headers: { 'sec-fetch-site': 'cross-site' } });
    assert.equal(res.status, 403);
  });
});
