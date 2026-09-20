import { createServer, request as httpRequest } from 'node:http';
import { chmod, lstat, realpath } from 'node:fs/promises';
import { dirname, isAbsolute, normalize } from 'node:path';

// Identity headers are trusted ONLY on an operator-owned Unix socket behind
// Tailscale Serve. Never expose this listener on TCP or trust these headers on
// the ordinary gateway. Serve strips client-supplied identity headers.
export async function createTailscaleServeProxy({ socketPath, allowedLogins, target, username, token }) {
  if (typeof socketPath !== 'string' || !isAbsolute(socketPath) || normalize(socketPath) !== socketPath ||
      Buffer.byteLength(socketPath) > 100) throw Error('invalid_identity_socket');
  const parent = dirname(socketPath);
  const stat = await lstat(parent);
  if (!stat.isDirectory() || await realpath(parent) !== parent ||
      stat.uid !== process.getuid() || (stat.mode & 0o077) !== 0) throw Error('private_socket_directory_required');
  try { await lstat(socketPath); throw Error('identity_socket_already_exists'); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  if (!Array.isArray(allowedLogins) || allowedLogins.length < 1 || allowedLogins.length > 32 ||
      allowedLogins.some(value => typeof value !== 'string' || !/^[\x21-\x7e]{1,254}$/.test(value) || /[,*?\s]/.test(value))) {
    throw Error('explicit_identity_allowlist_required');
  }
  const upstream = new URL(target);
  if (upstream.protocol !== 'http:' || upstream.hostname !== '127.0.0.1' ||
      upstream.username || upstream.password || upstream.pathname !== '/' || upstream.search || upstream.hash ||
      typeof username !== 'string' || !/^[A-Za-z0-9._-]{1,64}$/.test(username) ||
      typeof token !== 'string' || token.length < 32 || token.length > 256) throw Error('invalid_local_gateway');
  const permitted = new Set(allowedLogins);
  const authorization = `Basic ${Buffer.from(`${username}:${token}`).toString('base64')}`;
  const clients = new Set();
  const fail = (response, status) => {
    if (response.headersSent) { response.destroy(); return; }
    response.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' });
    response.end(JSON.stringify({ error: status === 403 ? 'tailnet_identity_not_allowed' : 'private_gateway_unavailable' }));
  };
  const server = createServer({ requestTimeout: 30000, headersTimeout: 10000, maxHeaderSize: 8192 }, (request, response) => {
    const identityHeaders = request.rawHeaders.filter((_, index) => index % 2 === 0)
      .filter(name => name.toLowerCase() === 'tailscale-user-login');
    const login = request.headers['tailscale-user-login'];
    if (identityHeaders.length !== 1 || typeof login !== 'string' || !permitted.has(login)) {
      request.resume(); fail(response, 403); return;
    }
    // An identity-authorized connection must not mint portable credentials
    // which would outlive the tailnet identity/access policy.
    let normalizedPath;
    try { normalizedPath = new URL(request.url, 'http://gateway.invalid').pathname; }
    catch { request.resume(); fail(response, 403); return; }
    if (!request.url?.startsWith('/prompt/') || !normalizedPath.startsWith('/prompt/') || normalizedPath.startsWith('/prompt/pairings') ||
        /[\\\x00-\x20\x7f]/.test(request.url) ||
        !['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'].includes(request.method)) {
      request.resume(); fail(response, 403); return;
    }
    const headers = { authorization };
    for (const key of ['accept', 'content-type', 'origin', 'last-event-id']) {
      if (typeof request.headers[key] === 'string') headers[key] = request.headers[key];
    }
    const outgoing = httpRequest({
      hostname: upstream.hostname, port: upstream.port || 80,
      method: request.method, path: request.url, headers,
    }, result => {
      if (result.statusCode >= 300 && result.statusCode < 400) {
        result.resume(); fail(response, 502); return;
      }
      const responseHeaders = { 'cache-control': 'no-store' };
      for (const key of ['content-type', 'x-next-cursor', 'access-control-allow-origin',
        'access-control-expose-headers', 'access-control-allow-methods', 'access-control-allow-headers', 'vary']) {
        if (result.headers[key]) responseHeaders[key] = result.headers[key];
      }
      response.writeHead(result.statusCode, responseHeaders);
      result.on('error', () => response.destroy());
      result.pipe(response);
    });
    outgoing.setTimeout(35000, () => outgoing.destroy());
    outgoing.on('error', () => fail(response, 502));
    request.on('aborted', () => outgoing.destroy());
    request.on('error', () => outgoing.destroy());
    response.on('close', () => outgoing.destroy());
    request.pipe(outgoing);
  });
  server.on('connection', socket => {
    clients.add(socket);
    socket.once('close', () => clients.delete(socket));
  });
  server.on('clientError', (_, socket) => socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n'));
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(socketPath, resolve);
  });
  try { await chmod(socketPath, 0o600); }
  catch (error) { server.close(); throw error; }
  return { async close() {
    for (const socket of clients) socket.destroy();
    await new Promise(resolve => server.close(resolve));
  } };
}
