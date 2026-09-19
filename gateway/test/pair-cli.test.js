import assert from 'node:assert/strict';
import test from 'node:test';
import { pairingOrigin, pairingUri } from '../src/pair-cli.js';

test('pairing URI carries only a private origin and short-lived ticket', () => {
  const value = pairingUri({
    origin: 'http://100.64.0.8:4097/',
    backend: 'claude',
    username: 'prompt',
    ticket: 'abcdefghijklmnopqrstuvwxyzABCDEFGH123456789',
  });
  const url = new URL(value);
  assert.equal(url.protocol, 'prompt:');
  assert.equal(url.hostname, 'connect');
  assert.equal(url.searchParams.get('origin'), 'http://100.64.0.8:4097/');
  assert.equal(url.searchParams.get('backend'), 'claude');
  assert.equal(url.searchParams.has('token'), false);
});

test('pairing CLI rejects loopback, public and decorated origins', () => {
  for (const value of [
    'http://127.0.0.1:4097/',
    'http://198.51.100.2:4097/',
    'http://user:secret@10.0.0.2:4097/',
    'http://10.0.0.2:4097/path',
    'http://10.0.0.2:4097/?token=value',
  ]) assert.throws(() => pairingOrigin(value), undefined, value);
});
