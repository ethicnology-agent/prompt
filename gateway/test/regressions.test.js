import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { createGateway } from '../src/server.js';
import { CodexAdapter } from '../src/adapters.js';
import { JsonProcess } from '../src/process.js';

test('actual cross-origin responses expose the history cursor', async (t) => {
  const token = 'a-safe-fixture-token-of-32-characters';
  const gateway = createGateway({ token, roots: [], engines: {}, webOrigins: ['https://prompt.test'] });
  const address = await gateway.listen(0);
  t.after(() => gateway.close());
  const response = await fetch(`http://127.0.0.1:${address.port}/prompt/capabilities`, { headers: { origin: 'https://prompt.test', authorization: `Basic ${Buffer.from(`prompt:${token}`).toString('base64')}` } });
  assert.equal(response.headers.get('access-control-expose-headers'), 'x-next-cursor');
});

test('Codex abort waits for the new turn ID and never interrupts the previous turn', async () => {
  const rpc = new EventEmitter();
  const starts = [];
  const interrupts = [];
  rpc.write = () => {};
  rpc.close = () => {};
  rpc.request = async (method, params) => {
    if (method === 'initialize') return {};
    if (method === 'thread/start') return { thread: { id: 'thread' } };
    if (method === 'turn/start') return new Promise((resolve) => starts.push(resolve));
    if (method === 'turn/interrupt') { interrupts.push(params.turnId); }
  };
  const runner = await new CodexAdapter('fixture', () => rpc).open({ directory: '/fixture' }, { delta() {}, permission: async () => false });
  const first = runner.run('first');
  let aborted = false;
  const firstAbort = runner.abort().then(() => { aborted = true; });
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(aborted, false, 'abort must not acknowledge while turn/start is unresolved');
  starts[0]({ turn: { id: 'first' } });
  await firstAbort;
  assert.deepEqual(interrupts, ['first']);
  rpc.emit('message', { method: 'turn/completed', params: { turn: { id: 'first', status: 'interrupted' } } });
  await first;
  const second = runner.run('second');
  const secondAbort = runner.abort();
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(interrupts, ['first']);
  starts[1]({ turn: { id: 'second' } });
  await secondAbort;
  assert.deepEqual(interrupts, ['first', 'second']);
  rpc.emit('message', { method: 'turn/completed', params: { turn: { id: 'second', status: 'interrupted' } } });
  await second;
});

test('termination escalates after the agent leader exits and a descendant ignores SIGTERM', async (t) => {
  const rpc = new JsonProcess(process.execPath, [new URL('./fixtures/process-tree.mjs', import.meta.url).pathname], process.cwd());
  let descendant;
  t.after(() => { rpc.close(); if (descendant) { try { process.kill(descendant, 'SIGKILL'); } catch {} } });
  const result = await rpc.request('ready', {}, 5000);
  descendant = result.pid;
  rpc.close();
  await new Promise((resolve) => setTimeout(resolve, 2400));
  let alive = true;
  try { process.kill(descendant, 0); } catch { alive = false; }
  assert.equal(alive, false, 'the stubborn descendant must not survive agent exit');
});
