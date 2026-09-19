import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import qrcode from 'qrcode-terminal';
import { privateAddress } from './security.js';

export function pairingOrigin(value) {
  const url = new URL(value);
  const host = url.hostname.replace(/^\[|\]$/g, '');
  if (!['http:', 'https:'].includes(url.protocol) ||
      !privateAddress(host) || host === '::1' || host.startsWith('127.') ||
      url.username || url.password || url.search || url.hash || url.pathname !== '/') {
    throw Error('private_phone_origin_required');
  }
  return url;
}

export function pairingUri({ origin, backend, username, ticket }) {
  if (!['claude', 'codex', 'opencode'].includes(backend) ||
      !/^[A-Za-z0-9._-]{1,64}$/.test(username) ||
      !/^[A-Za-z0-9_-]{43}$/.test(ticket)) throw Error('invalid_pairing_response');
  const url = new URL('prompt://connect');
  url.searchParams.set('v', '1');
  url.searchParams.set('origin', pairingOrigin(origin).toString());
  url.searchParams.set('backend', backend);
  url.searchParams.set('username', username);
  url.searchParams.set('ticket', ticket);
  return url.toString();
}

async function main(args, env) {
  if (args.length !== 3) throw Error('usage');
  const [configPath, originValue, backend] = args;
  const config = JSON.parse(await readFile(configPath, 'utf8'));
  const origin = pairingOrigin(originValue);
  const username = config.username ?? 'prompt';
  const token = env.PROMPT_GATEWAY_TOKEN;
  if (typeof token !== 'string' || token.length < 32) throw Error('missing_token');
  const authorization = `Basic ${Buffer.from(`${username}:${token}`).toString('base64')}`;
  const response = await fetch(new URL('/prompt/pairings', origin), {
    method: 'POST',
    redirect: 'error',
    headers: { authorization, 'content-type': 'application/json' },
    body: JSON.stringify({ backend }),
  });
  if (response.status !== 201) throw Error('pairing_rejected');
  const body = await response.json();
  const value = pairingUri({ origin: origin.toString(), backend, username, ticket: body.ticket });
  process.stdout.write('Scan this short-lived pairing code from Prompt settings.\n');
  qrcode.generate(value, { small: true }, (code) => process.stdout.write(`${code}\n`));
  process.stdout.write('The code expires in two minutes and can be exchanged once. Do not capture or share it.\n');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2), process.env).catch(() => {
    process.stderr.write('Could not create a pairing code. Check the private origin, engine, token and gateway.\n');
    process.exitCode = 1;
  });
}
