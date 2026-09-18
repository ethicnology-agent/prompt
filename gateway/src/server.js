import { createServer } from 'node:http';
import { Readable } from 'node:stream';
import { Fault, authenticate, privateAddress, bodyJson, allowedDirectory } from './security.js';
import { NativeModelCatalog, providerCatalog } from './model-catalog.js';
import { imageConstraints, imageRequestBytes } from './image-input.js';

function json(response, value, status = 200) {
  response.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' });
  response.end(JSON.stringify(value));
}

export function createGateway({ token, username = 'prompt', host = '127.0.0.1', roots, engines, openCode, worktrees, webOrigins = [] }) {
  if (!privateAddress(host)) throw new Fault(400, 'private_literal_bind_required');
  if (typeof token !== 'string' || token.length < 32 || username.includes(':')) throw new Fault(400, 'strong_token_required');
  if (openCode) {
    const url = new URL(openCode.url);
    if (!['http:', 'https:'].includes(url.protocol) || !privateAddress(url.hostname.replace(/^\[|\]$/g, '')) || url.username || url.password || url.search || url.hash || url.pathname !== '/') throw new Fault(400, 'private_opencode_origin_required');
  }
  const subscribers = new Set();
  const catalogs = new Map(Object.entries(engines).map(([engine, store]) => [engine, new NativeModelCatalog(store.adapter, roots[0])]));
  const server = createServer({ requestTimeout: 30000, headersTimeout: 10000, maxHeaderSize: 8192 }, async (request, response) => {
    try {
      const origin = request.headers.origin;
      if (origin) {
        if (!webOrigins.includes(origin) || !origin.startsWith('https://')) throw new Fault(403, 'origin_not_allowed');
        response.setHeader('Access-Control-Allow-Origin', origin);
        response.setHeader('Access-Control-Expose-Headers', 'x-next-cursor');
        response.setHeader('Vary', 'Origin');
        if (request.method === 'OPTIONS') {
          response.writeHead(204, { 'Access-Control-Allow-Methods': 'GET,POST,PATCH,DELETE,OPTIONS', 'Access-Control-Allow-Headers': 'authorization,content-type', 'Access-Control-Expose-Headers': 'x-next-cursor' });
          response.end(); return;
        }
      }
      if (!authenticate(request.headers.authorization, username, token)) throw new Fault(401, 'unauthorized');
      const url = new URL(request.url, 'http://gateway.invalid');
      if (url.pathname === '/prompt/worktrees') {
        if (!worktrees) throw new Fault(503, 'worktrees_unavailable');
        if (request.method === 'GET') { json(response, await worktrees.list(url.searchParams.get('directory'))); return; }
        if (request.method === 'POST') {
          const body = await bodyJson(request, 8192);
          if (Object.keys(body).some((key) => !['directory', 'name'].includes(key))) throw new Fault(400, 'unsupported_worktree_option');
          json(response, await worktrees.create(body), 201); return;
        }
        throw new Fault(405, 'unsupported_worktree_method');
      }
      if (url.pathname === '/prompt/capabilities' && request.method === 'GET') {
        json(response, { protocolVersion: 1, machine: { worktrees: Boolean(worktrees) }, engines: Object.fromEntries(['claude', 'codex', 'opencode'].map((name) => [name, {
          available: name === 'opencode' ? Boolean(openCode) : Boolean(engines[name]),
          features: name === 'opencode' ? (openCode ? ['sessions', 'text', 'abort', 'permissions', 'permissionAlways', 'questions', 'commands', 'attachments', 'sessionDelete', 'sessionRename', 'sessionFork', 'sessionRevert'] : []) : (engines[name] ? ['sessions', 'text', 'abort', 'permissions', 'attachments', 'imageAttachments', 'sessionDelete', 'sessionRename'] : []),
          ...(name !== 'opencode' && engines[name] ? { attachmentConstraints: imageConstraints } : {}),
          persistence: name === 'opencode' ? 'upstream' : 'gateway-lifetime',
        }])) }); return;
      }
      const match = /^\/prompt\/(claude|codex|opencode)(\/.*)$/.exec(url.pathname);
      if (!match) throw new Fault(404, 'route_not_found');
      const [, engine, path] = match;
      if (engine === 'opencode') {
        if (!openCode) throw new Fault(503, 'engine_unavailable');
        await proxyOpenCode(request, response, url, path, openCode, roots); return;
      }
      const store = engines[engine];
      if (!store) throw new Fault(503, 'engine_unavailable');
      if (request.method === 'GET' && path === '/global/event') {
        if (subscribers.size >= 16) throw new Fault(429, 'subscriber_limit');
        response.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-store', 'x-accel-buffering': 'no' });
        response.write(': connected\n\n');
        subscribers.add(response);
        const listener = (event) => {
          if (response.writableLength > 256 * 1024) { response.destroy(); return; }
          response.write(`data: ${JSON.stringify(event)}\n\n`);
        };
        store.on('event', listener);
        const heartbeat = setInterval(() => response.write(': heartbeat\n\n'), 25000);
        response.once('close', () => { clearInterval(heartbeat); store.off('event', listener); subscribers.delete(response); });
        return;
      }
      if (request.method === 'GET') {
        if (path === '/global/health') { json(response, { healthy: true, version: 'prompt-gateway/0.1.0' }); return; }
        if (path === '/project') { json(response, store.projects()); return; }
        if (path === '/provider') { json(response, providerCatalog(engine, await catalogs.get(engine).read())); return; }
        if (path === '/agent') { json(response, [{ name: engine, mode: 'primary', builtIn: true }]); return; }
        if (path === '/command' || path === '/question') { json(response, []); return; }
        if (path === '/permission') { json(response, [...store.permissions.values()].map((p) => p.record)); return; }
        if (path === '/session/status') { json(response, Object.fromEntries([...store.sessions.values()].map((s) => [s.id, { type: s.status }]))); return; }
        if (path === '/session') {
          const directory = url.searchParams.get('directory');
          if (directory) await allowedDirectory(directory, roots);
          json(response, [...store.sessions.values()].filter((s) => !directory || s.directory === directory).map((s) => store.record(s))); return;
        }
      }
      if (path === '/session' && request.method === 'POST') {
        const body = await bodyJson(request);
        if (Object.keys(body).some((key) => key !== 'title')) throw new Fault(400, 'unsupported_session_option');
        json(response, await store.create(url.searchParams.get('directory') || roots[0], body.title)); return;
      }
      const sessionMatch = /^\/session\/([^/]+)(?:\/(.*))?$/.exec(path);
      if (!sessionMatch) throw new Fault(404, 'unsupported_route');
      const session = store.get(sessionMatch[1]);
      const action = sessionMatch[2];
      if (!action && request.method === 'GET') { json(response, store.record(session)); return; }
      if (!action && request.method === 'DELETE') {
        if (session.active) throw new Fault(409, 'session_busy');
        session.runner?.close(); store.sessions.delete(session.id); json(response, true); return;
      }
      if (!action && request.method === 'PATCH') {
        const body = await bodyJson(request);
        if (Object.keys(body).some((key) => key !== 'title') || typeof body.title !== 'string' || !body.title.trim() || body.title.length > 256) throw new Fault(400, 'invalid_title');
        session.title = body.title; json(response, store.record(session)); return;
      }
      if (action === 'message' && request.method === 'GET') {
        const before = url.searchParams.get('before');
        let end = before ? session.messages.findIndex((m) => m.info.id === before) : session.messages.length;
        if (end < 0) throw new Fault(400, 'invalid_cursor');
        const count = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') || 100)));
        if (!Number.isInteger(count)) throw new Fault(400, 'invalid_limit');
        const start = Math.max(0, end - count);
        if (start) response.setHeader('x-next-cursor', session.messages[start].info.id);
        json(response, session.messages.slice(start, end)); return;
      }
      if (['todo', 'diff', 'children'].includes(action) && request.method === 'GET') { json(response, []); return; }
      if (action === 'prompt_async' && request.method === 'POST') { await store.submit(session, await bodyJson(request, imageRequestBytes), catalogs.get(engine)); response.writeHead(204); response.end(); return; }
      if (action === 'abort' && request.method === 'POST') { json(response, await store.abort(session)); return; }
      if (action?.startsWith('permissions/') && request.method === 'POST') {
        const body = await bodyJson(request);
        json(response, store.reply(action.slice('permissions/'.length), body.response, session.id)); return;
      }
      throw new Fault(404, 'unsupported_route');
    } catch (error) {
      if (response.headersSent) { response.destroy(); return; }
      json(response, { error: error instanceof Fault ? error.code : 'gateway_request_failed' }, error instanceof Fault ? error.status : 500);
    }
  });
  server.on('clientError', (_, socket) => socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n'));
  return {
    server,
    async listen(port = 4097) { await new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, host, resolve); }); return server.address(); },
    async close() {
      worktrees?.close();
      for (const catalog of catalogs.values()) catalog.close();
      for (const response of subscribers) response.destroy();
      for (const store of Object.values(engines)) store.close();
      server.closeAllConnections();
      await new Promise((resolve) => server.close(resolve));
    },
  };
}

async function proxyOpenCode(request, response, url, path, upstream, roots) {
  // No generic reverse proxy: exclude server configuration, external sharing,
  // PTYs, arbitrary file APIs, OAuth and process disposal from this MVP.
  const allowed = /^\/(global\/(health|event)|project|provider|agent|command|permission|question(?:\/[^/]+\/(reply|reject))?|session(?:\/[^/]+(?:\/(message|prompt_async|abort|status|todo|diff|children|command|fork|revert|permissions\/[^/]+))?)?)$/;
  if (!allowed.test(path)) throw new Fault(404, 'unsupported_route');
  const directory = url.searchParams.get('directory');
  if (directory) await allowedDirectory(directory, roots);
  const controller = new AbortController();
  response.once('close', () => controller.abort());
  const timeout = setTimeout(() => controller.abort(), path === '/global/event' ? 30 * 60 * 1000 : 30000);
  try {
    const target = new URL(path + url.search, upstream.url);
    const headers = { accept: request.headers.accept || 'application/json' };
    if (upstream.password) headers.authorization = `Basic ${Buffer.from(`${upstream.username || 'opencode'}:${upstream.password}`).toString('base64')}`;
    let body;
    if (['POST', 'PATCH', 'DELETE'].includes(request.method)) {
      body = JSON.stringify(await bodyJson(request, 36 * 1024 * 1024));
      headers['content-type'] = 'application/json';
    }
    const result = await fetch(target, { method: request.method, headers, body, signal: controller.signal, redirect: 'error' });
    response.writeHead(result.status, { 'content-type': result.headers.get('content-type') || 'application/json', 'cache-control': 'no-store', ...(result.headers.get('x-next-cursor') ? { 'x-next-cursor': result.headers.get('x-next-cursor') } : {}) });
    if (!result.body) { response.end(); return; }
    await new Promise((resolve, reject) => {
      const stream = Readable.fromWeb(result.body);
      stream.on('error', reject); response.on('error', reject); response.on('close', resolve);
      stream.pipe(response); response.on('finish', resolve);
    });
  } finally { clearTimeout(timeout); controller.abort(); }
}
