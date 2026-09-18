import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { CodexAdapter, ClaudeAdapter } from '../src/adapters.js';
import { NativeModelCatalog, providerCatalog } from '../src/model-catalog.js';
import { createGateway } from '../src/server.js';

function codexFixture(list) {
  const calls = [];
  let closes = 0;
  const rpc = new EventEmitter();
  rpc.write = (value) => calls.push(value);
  rpc.close = () => { closes++; };
  rpc.request = async (method, params) => {
    calls.push({ method, params });
    if (method === 'initialize') return {};
    assert.equal(method, 'model/list', 'discovery cannot start threads or turns');
    return list(params);
  };
  return { adapter: new CodexAdapter('fixture-only', () => rpc), calls, closes: () => closes };
}

test('Codex paginates actual wire models, excludes hidden, closes without generation', async () => {
  const fixture = codexFixture(({ cursor }) => cursor
    ? { data: [{ model: 'wire-b', displayName: 'Fixture B' }], nextCursor: null }
    : { data: [{ id: 'picker-id', model: 'wire-a', displayName: 'Fixture A' }, { model: 'hidden', displayName: 'Hidden', hidden: true }], nextCursor: 'next' });
  const result = await new NativeModelCatalog(fixture.adapter, '/fixture').read();
  assert.deepEqual(result, { status: 'ready', models: [{ id: 'wire-a', name: 'Fixture A' }, { id: 'wire-b', name: 'Fixture B' }] });
  assert.deepEqual(fixture.calls.filter((call) => call.method === 'model/list').map((call) => call.params), [
    { limit: 64, includeHidden: false }, { limit: 64, includeHidden: false, cursor: 'next' },
  ]);
  assert.equal(fixture.closes(), 1);
});

test('Codex malformed, looping, excessive and failing catalogs clean up safely', async () => {
  for (const page of [() => null, () => { throw new Error('sensitive fixture details'); },
    () => ({ data: [], nextCursor: 'repeated' }),
    () => ({ data: Array.from({ length: 257 }, (_, i) => ({ model: `m${i}`, displayName: 'Fixture' })) }),
    (() => { let i = 0; return () => ({ data: [], nextCursor: `page-${i++}` }); })(),
  ]) {
    const fixture = codexFixture(page);
    assert.deepEqual(await new NativeModelCatalog(fixture.adapter, '/fixture').read(), { status: 'unavailable', models: [] });
    assert.equal(fixture.closes(), 1);
  }
});

test('timeout closes a Codex discovery that never answers', async () => {
  const fixture = codexFixture(() => new Promise(() => {}));
  const result = await new NativeModelCatalog(fixture.adapter, '/fixture', { timeoutMs: 10 }).read();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(result.status, 'unavailable');
  assert.equal(fixture.closes(), 1);
});

test('Claude uses a non-generating empty input stream and closes discovery', async () => {
  let options;
  let input;
  let closed = 0;
  const adapter = new ClaudeAdapter((parameters) => {
    options = parameters.options;
    input = parameters.prompt[Symbol.asyncIterator]().next();
    return { supportedModels: async () => [{ value: 'actual-alias', displayName: 'Fixture Claude' }], close() { closed++; } };
  });
  assert.deepEqual(await new NativeModelCatalog(adapter, '/fixture').read(), { status: 'ready', models: [{ id: 'actual-alias', name: 'Fixture Claude' }] });
  assert.deepEqual(await input, { done: true, value: undefined });
  assert.equal(options.persistSession, false);
  assert.deepEqual(options.settingSources, []);
  assert.deepEqual(options.tools, []);
  assert.equal((await options.canUseTool()).behavior, 'deny');
  assert.equal(options.abortController.signal.aborted, true);
  assert.equal(closed, 1);
});

test('Claude timeout, absent method and failure always abort and close', async () => {
  for (const supportedModels of [undefined, async () => { throw new Error('private native error'); }, () => new Promise(() => {})]) {
    let options;
    let closes = 0;
    const adapter = new ClaudeAdapter((p) => { options = p.options; return { supportedModels, close() { closes++; } }; });
    assert.equal((await new NativeModelCatalog(adapter, '/fixture', { timeoutMs: 10 }).read()).status, 'unavailable');
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(options.abortController.signal.aborted, true);
    assert.equal(closes, 1);
  }
});

test('catalog deduplicates requests, caches bounded records and refreshes after expiry', async () => {
  let now = 0;
  let reads = 0;
  let release;
  const catalog = new NativeModelCatalog({ discoverModels: () => { reads++; return new Promise((resolve) => { release = resolve; }); } }, '/fixture', { now: () => now, ttlMs: 100 });
  const first = catalog.read();
  const second = catalog.read();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(reads, 1);
  release([{ id: 'a', name: 'A' }, { id: 'a', name: 'A' }, { id: 'bad\n', name: 'Invalid' }]);
  assert.deepEqual(await first, await second);
  assert.equal((await catalog.read()).models.length, 1);
  assert.equal(reads, 1);
  now = 101;
  const refreshed = catalog.read();
  await new Promise((resolve) => setImmediate(resolve));
  release([{ id: 'b', name: 'B' }]);
  assert.equal((await refreshed).models[0].id, 'b');
  assert.equal(reads, 2);
});

test('failure cache and shutdown prevent repeated discovery and leak no native errors', async () => {
  let reads = 0;
  const catalog = new NativeModelCatalog({ discoverModels: async () => { reads++; throw new Error('secret fixture text'); } }, '/fixture');
  const result = await catalog.read();
  await catalog.read();
  assert.equal(reads, 1);
  const provider = providerCatalog('codex', result);
  assert.equal(provider.catalog.status, 'unavailable');
  assert.equal(provider.all[0].models.default.name, 'CLI default (catalog unavailable)');
  assert.equal(JSON.stringify(provider).includes('secret'), false);
  catalog.close();
  await catalog.read();
  assert.equal(reads, 1);
});

test('failure cache expires and a subsequent successful catalog replaces the fallback', async () => {
  let now = 0;
  let attempts = 0;
  const catalog = new NativeModelCatalog({ discoverModels: async () => {
    if (++attempts === 1) throw new Error('unavailable');
    return [{ id: 'recovered', name: 'Recovered model' }];
  } }, '/fixture', { now: () => now, failureTtlMs: 20 });
  assert.equal((await catalog.read()).status, 'unavailable');
  now = 19;
  assert.equal((await catalog.read()).status, 'unavailable');
  now = 21;
  assert.equal((await catalog.read()).status, 'ready');
  assert.equal(attempts, 2);
});

test('closing the catalog aborts an in-flight owned discovery process', async () => {
  const fixture = codexFixture(() => new Promise(() => {}));
  const catalog = new NativeModelCatalog(fixture.adapter, '/fixture');
  const pending = catalog.read();
  await new Promise((resolve) => setImmediate(resolve));
  catalog.close();
  assert.equal((await pending).status, 'unavailable');
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(fixture.closes(), 1);
  assert.equal((await catalog.read()).status, 'unavailable');
});

test('provider route authenticates before discovery and returns only real IDs plus default', async (t) => {
  let reads = 0;
  const gateway = createGateway({ token: 'fixture-only-token-with-32-characters', roots: ['/fixture'], engines: {
    codex: { adapter: { discoverModels: async () => { reads++; return [{ id: 'real-id', name: 'Real display' }]; } }, close() {} },
  } });
  const address = await gateway.listen(0);
  t.after(() => gateway.close());
  const url = `http://127.0.0.1:${address.port}/prompt/codex/provider`;
  assert.equal((await fetch(url)).status, 401);
  assert.equal(reads, 0);
  const headers = { authorization: `Basic ${Buffer.from('prompt:fixture-only-token-with-32-characters').toString('base64')}` };
  const [a, b] = await Promise.all([fetch(url, { headers }).then((r) => r.json()), fetch(url, { headers }).then((r) => r.json())]);
  assert.deepEqual(a, b);
  assert.deepEqual(Object.keys(a.all[0].models), ['default', 'real-id']);
  assert.equal(a.catalog.status, 'ready');
  assert.equal(reads, 1);
});
