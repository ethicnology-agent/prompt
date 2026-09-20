import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer, request } from 'node:http';
import { mkdtemp, chmod, lstat, rm, writeFile } from 'node:fs/promises';
import { createTailscaleServeProxy } from '../src/tailscale-serve-proxy.js';

const token = 'synthetic-private-gateway-token-at-least-32-chars';
async function fixture(t, handler) {
  const directory = await mkdtemp('/tmp/identity-proxy-');
  const upstream = createServer(handler ?? ((_, response) => response.end('{}')));
  await new Promise(resolve => upstream.listen(0, '127.0.0.1', resolve));
  const config = { socketPath: `${directory}/http.sock`, allowedLogins: ['owner'],
    target: `http://127.0.0.1:${upstream.address().port}`, username: 'prompt', token };
  // macOS /tmp is a symlink; production requires a canonical private parent.
  const { realpath } = await import('node:fs/promises');
  config.socketPath = `${await realpath(directory)}/http.sock`;
  const proxies = [];
  t.after(async () => {
    for (const proxy of proxies) await proxy.close();
    upstream.closeAllConnections();
    await new Promise(resolve => upstream.close(resolve));
    await rm(directory, { recursive: true });
  });
  return { config, directory, async start(value = config) {
    const proxy = await createTailscaleServeProxy(value); proxies.push(proxy); return proxy;
  }, call(headers = {}, path = '/prompt/capabilities', method = 'GET', body = null) {
    return new Promise((resolve, reject) => {
      const call = request({ socketPath: config.socketPath, path, method, headers }, response => {
        let body = ''; response.on('data', chunk => body += chunk);
        response.on('end', () => resolve({ status: response.statusCode, body, headers: response.headers }));
      });
      call.on('error', reject); call.end(body);
    });
  } };
}

test('only an explicit Serve identity reaches the authenticated gateway', async t => {
  let calls = 0;
  const f = await fixture(t, (request, response) => {
    calls++;
    assert.equal(request.headers.authorization, `Basic ${Buffer.from(`prompt:${token}`).toString('base64')}`);
    assert.equal(request.headers['tailscale-user-login'], undefined);
    assert.equal(request.headers['x-forwarded-for'], undefined);
    response.end('{"protocolVersion":1}');
  });
  await f.start();
  assert.equal((await lstat(f.config.socketPath)).mode & 0o777, 0o600);
  for (const headers of [{}, { 'tailscale-user-login': 'other' },
    { 'tailscale-user-login': 'owner,other' }, { authorization: 'Basic synthetic' },
    { 'tailscale-user-login': ['owner', 'owner'] }]) {
    assert.equal((await f.call(headers)).status, 403);
  }
  assert.equal(calls, 0);
  const accepted = await f.call({ 'tailscale-user-login': 'owner', authorization: 'malicious', 'x-forwarded-for': '100.64.0.5' });
  assert.equal(accepted.status, 200);
  assert.equal(calls, 1);
  assert.equal(accepted.body, '{"protocolVersion":1}');
});

test('identity access cannot create or exchange reusable credentials', async t => {
  let calls = 0;
  const f = await fixture(t, (_, response) => { calls++; response.end('{}'); });
  await f.start();
  for (const path of ['/prompt/pairings', '/prompt/pairings/exchange', '/global/health',
    '/prompt/other/../pairings', '/prompt/other/%2e%2e/pairings/exchange',
    'http://evil.invalid/prompt/capabilities', '//evil.invalid/prompt/capabilities']) {
    assert.equal((await f.call({ 'tailscale-user-login': 'owner' }, path, 'POST', '{}')).status, 403);
  }
  assert.equal(calls, 0);
});

test('preserves request bodies, CORS, SSE chunks and pagination', async t => {
  const f = await fixture(t, (request, response) => {
    assert.equal(request.headers.origin, 'https://private.example');
    let body = ''; request.on('data', chunk => body += chunk);
    request.on('end', () => {
      assert.equal(body, '{"response":"once"}');
      response.writeHead(200, { 'content-type': 'text/event-stream', 'x-next-cursor': 'cursor', 'set-cookie': 'not-forwarded' });
      response.write('data: one\n\n'); response.end('data: two\n\n');
    });
  });
  await f.start();
  const result = await f.call({ 'tailscale-user-login': 'owner', origin: 'https://private.example' },
    '/prompt/codex/session/test/permissions/test', 'POST', '{"response":"once"}');
  assert.equal(result.body, 'data: one\n\ndata: two\n\n');
  assert.equal(result.headers['x-next-cursor'], 'cursor');
  assert.equal(result.headers['set-cookie'], undefined);
});

test('redirects cannot move the gateway credential to another endpoint', async t => {
  const f = await fixture(t, (_, response) => { response.writeHead(302, { location: 'https://evil.invalid' }); response.end(); });
  await f.start();
  const result = await f.call({ 'tailscale-user-login': 'owner' });
  assert.equal(result.status, 502);
  assert.equal(result.headers.location, undefined);
});

test('unsafe configuration and occupied sockets fail closed', async t => {
  const f = await fixture(t);
  for (const patch of [{ allowedLogins: [] }, { allowedLogins: ['*'] }, { target: 'http://10.0.0.1:4097' },
    { target: 'http://127.0.0.1:4097/path' }, { token: 'short' }, { socketPath: 'relative' }]) {
    await assert.rejects(f.start({ ...f.config, ...patch }));
  }
  await chmod(f.directory, 0o755);
  await assert.rejects(f.start());
  await chmod(f.directory, 0o700);
  await writeFile(f.config.socketPath, 'preserve');
  await assert.rejects(f.start());
});
