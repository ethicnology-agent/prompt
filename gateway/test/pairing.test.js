import assert from 'node:assert/strict';
import test from 'node:test';
import { PairingAuthority } from '../src/pairing.js';

const master = 'fixture-master-token-with-32-characters';

test('pairing tickets expire, are backend-bound and single-use', () => {
  let now = 1000;
  let fill = 1;
  const authority = new PairingAuthority('prompt', master, {
    now: () => now,
    bytes: (length) => Buffer.alloc(length, fill++),
  });
  const first = authority.create('codex');
  assert.equal(authority.exchange(first.ticket, 'claude'), null);
  const credential = authority.exchange(first.ticket, 'codex');
  assert.match(credential, /^p1\.[A-Za-z0-9_-]{24}\.[A-Za-z0-9_-]{43}$/);
  assert.equal(authority.exchange(first.ticket, 'codex'), null);

  const expired = authority.create('codex');
  now = expired.expiresAt;
  assert.equal(authority.exchange(expired.ticket, 'codex'), null);
});

test('derived device credential authenticates without revealing master token', () => {
  const authority = new PairingAuthority('prompt', master, {
    bytes: (length) => Buffer.alloc(length, 7),
  });
  const pending = authority.create('opencode');
  const credential = authority.exchange(pending.ticket, 'opencode');
  const header = `Basic ${Buffer.from(`prompt:${credential}`).toString('base64')}`;
  assert.equal(authority.authenticate(header), true);
  assert.equal(credential.includes(master), false);
  assert.equal(authority.authenticate(`Basic ${Buffer.from('prompt:p1.bad.bad').toString('base64')}`), false);
});
