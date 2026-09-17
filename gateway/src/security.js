import { timingSafeEqual, createHash } from 'node:crypto';
import { realpath, stat } from 'node:fs/promises';
import { isIP } from 'node:net';
import { isAbsolute, relative, sep } from 'node:path';

export class Fault extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}

export function privateAddress(address) {
  if (isIP(address) === 4) {
    const [a, b] = address.split('.').map(Number);
    return a === 127 || a === 10 || (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && b === 168) || (a === 100 && b >= 64 && b <= 127);
  }
  return isIP(address) === 6 && (address === '::1' || /^f[cd]/i.test(address));
}

export function authenticate(header, username, token) {
  const expected = `Basic ${Buffer.from(`${username}:${token}`).toString('base64')}`;
  const digest = (value) => createHash('sha256').update(value).digest();
  return typeof header === 'string' && timingSafeEqual(digest(header), digest(expected));
}

export async function resolveRoots(roots) {
  if (!Array.isArray(roots) || roots.length === 0 || roots.length > 32) throw new Fault(400, 'roots_required');
  const result = [];
  for (const root of roots) {
    if (typeof root !== 'string' || !isAbsolute(root)) throw new Fault(400, 'invalid_root');
    const path = await realpath(root);
    if (path === sep || !(await stat(path)).isDirectory()) throw new Fault(400, 'invalid_root');
    result.push(path);
  }
  return [...new Set(result)];
}

export async function allowedDirectory(value, roots) {
  if (typeof value !== 'string' || !isAbsolute(value)) throw new Fault(403, 'directory_not_allowed');
  let path;
  try { path = await realpath(value); } catch { throw new Fault(403, 'directory_not_allowed'); }
  if (!roots.some((root) => {
    const rel = relative(root, path);
    return rel === '' || (!rel.startsWith(`..${sep}`) && rel !== '..' && !isAbsolute(rel));
  }) || !(await stat(path)).isDirectory()) throw new Fault(403, 'directory_not_allowed');
  return path;
}

export async function bodyJson(request, maximum = 256 * 1024) {
  let length = 0;
  const chunks = [];
  for await (const chunk of request) {
    length += chunk.length;
    if (length > maximum) throw new Fault(413, 'request_too_large');
    chunks.push(chunk);
  }
  if (!length) return {};
  try {
    const value = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw Error();
    return value;
  } catch { throw new Fault(400, 'invalid_json'); }
}
