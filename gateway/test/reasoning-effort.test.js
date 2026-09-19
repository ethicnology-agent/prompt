import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { CodexAdapter, ClaudeAdapter } from '../src/adapters.js';
import { NativeModelCatalog, providerCatalog } from '../src/model-catalog.js';
import { Sessions } from '../src/sessions.js';
import { InputStream } from '../src/input-stream.js';
import { createGateway } from '../src/server.js';

const options = { version: 1, reasoningEfforts: [{ id: 'fixture-light', label: 'fixture-light' }, { id: 'fixture-deep', label: 'fixture-deep' }], defaultReasoningEffortId: 'fixture-light' };
const session = () => ({ id: 's', directory: '/fixture', messages: [], accepted: new Map(), status: 'idle', active: false, outputBytes: 0, imageBytes: 0, time: {} });
const body = (effort) => ({ parts: [{ type: 'text', text: 'fixture' }], model: { providerID: 'codex', modelID: 'model' }, ...(effort === undefined ? {} : { reasoningEffort: effort }) });

test('HTTP effort selection authenticates and validates before returning accepted', async (t) => {
  let discovers = 0;
  const runs = [];
  const store = new Sessions('codex', {
    discoverModels: async () => { discovers++; return [{ id: 'model', name: 'Fixture', executionOptions: options }]; },
    open: async () => ({ run: async (...args) => runs.push(args), close() {} }),
  }, []);
  const item = session();
  store.sessions.set(item.id, item);
  const token = 'fixture-only-token-with-32-characters';
  const gateway = createGateway({ token, roots: ['/fixture'], engines: { codex: store } });
  const address = await gateway.listen(0);
  t.after(() => gateway.close());
  const url = `http://127.0.0.1:${address.port}/prompt/codex/session/s/prompt_async`;
  const headers = { authorization: `Basic ${Buffer.from(`prompt:${token}`).toString('base64')}`, 'content-type': 'application/json' };
  assert.equal((await fetch(url, { method: 'POST', body: JSON.stringify(body('fixture-deep')) })).status, 401);
  assert.equal(discovers, 0);
  assert.equal((await fetch(url, { method: 'POST', headers, body: JSON.stringify(body('invented')) })).status, 400);
  assert.equal(item.messages.length, 0);
  assert.equal(runs.length, 0);
  assert.equal((await fetch(url, { method: 'POST', headers, body: JSON.stringify({ ...body('fixture-deep'), permissionMode: 'invented' }) })).status, 400);
  assert.equal(item.messages.length, 0);
  assert.equal((await fetch(url, { method: 'POST', headers, body: JSON.stringify({ ...body('fixture-deep'), permissionMode: 'auto' }) })).status, 204);
  await item.task;
  assert.equal(runs[0][3].reasoningEffort, 'fixture-deep');
  assert.equal(runs[0][3].permissionMode, 'auto');
  assert.equal(discovers, 1);
});

test('Claude rejects unadvertised permission modes before accepting a prompt', async () => {
  const runs = [];
  const store = new Sessions('claude', {
    open: async () => ({ run: async (...args) => runs.push(args), close() {} }),
  }, []);
  const item = session();
  const prompt = {
    parts: [{ type: 'text', text: 'fixture' }],
    model: { providerID: 'claude', modelID: 'default' },
  };

  assert.throws(
    () => store.submit(item, { ...prompt, permissionMode: 'bypassPermissions' }),
    /unsupported_permission_mode/,
  );
  assert.equal(item.messages.length, 0);
  assert.equal(item.active, false);
  assert.equal(runs.length, 0);

  store.submit(item, { ...prompt, permissionMode: 'plan' });
  await item.task;
  assert.equal(runs.length, 1);
  assert.equal(runs[0][3].permissionMode, 'plan');
  store.close();
});

test('native discovery maps exact model-specific SDK effort contracts', async () => {
  const rpc = new EventEmitter();
  rpc.write = () => {};
  rpc.close = () => {};
  rpc.request = async (method) => method === 'initialize' ? {} : { data: [{ model: 'model', displayName: 'Fixture', defaultReasoningEffort: 'fixture-light', supportedReasoningEfforts: [{ reasoningEffort: 'fixture-light', description: 'Fixture description' }, { reasoningEffort: 'fixture-deep' }] }] };
  const codex = await new NativeModelCatalog(new CodexAdapter('fixture', () => rpc), '/fixture').read();
  assert.deepEqual(codex.models[0].executionOptions, { ...options, reasoningEfforts: [{ id: 'fixture-light', label: 'fixture-light', description: 'Fixture description' }, options.reasoningEfforts[1]] });
  const claude = await new NativeModelCatalog(new ClaudeAdapter(() => ({
    supportedModels: async () => [{ value: 'model', displayName: 'Fixture', supportsEffort: true, supportedEffortLevels: ['fixture-light', 'fixture-deep'] }, { value: 'no-effort', displayName: 'No effort', supportsEffort: false, supportedEffortLevels: ['must-not-show'] }], close() {},
  })), '/fixture').read();
  assert.deepEqual(claude.models[0].executionOptions, { version: 1, reasoningEfforts: options.reasoningEfforts });
  assert.equal(claude.models[1].executionOptions, undefined);
});

test('catalog publishes bounded versioned advertised efforts, not fixed guessed levels', async () => {
  const catalog = new NativeModelCatalog({ discoverModels: async () => [{ id: 'model', name: 'Fixture', executionOptions: { ...options, reasoningEfforts: [...options.reasoningEfforts, { id: 'bad\nvalue' }, { id: 'fixture-light' }] } }] }, '/fixture');
  const value = await catalog.read();
  assert.deepEqual(value.models[0].executionOptions, options);
  assert.deepEqual(providerCatalog('codex', value).all[0].models.model.executionOptions, options);
  assert.equal(providerCatalog('codex', value).all[0].models.default.executionOptions, undefined);
  assert.deepEqual(providerCatalog('codex', value).all[0].executionOptions, {
    version: 1,
    permissionModes: [
      { id: 'ask', label: 'Auto', description: 'Ask when unsure; writes stay inside the workspace.' },
      { id: 'auto', label: 'Workspace', description: 'Sandboxed workspace access that can request escalation.' },
      { id: 'read', label: 'Read', description: 'No filesystem writes or approval escalation.' },
    ],
    defaultPermissionModeId: 'ask',
  });
  assert.deepEqual(providerCatalog('claude', value).all[0].executionOptions, {
    version: 1,
    permissionModes: [
      { id: 'ask', label: 'Auto', description: 'Ask before uncertain tool use.' },
      { id: 'plan', label: 'Plan', description: 'Plan without executing tools or changing files.' },
    ],
    defaultPermissionModeId: 'ask',
  });
  catalog.close();
});

test('unknown effort rejected before history/acceptance; absent resets using actual model default', async () => {
  const calls = [];
  const store = new Sessions('codex', { open: async () => ({ run: async (...args) => calls.push(args), close() {} }) }, []);
  const value = { status: 'ready', models: [{ id: 'model', name: 'Fixture', executionOptions: options }] };
  const catalog = { cached: value, read: async () => value };
  const item = session();
  await assert.rejects(store.submit(item, body('invented'), catalog), /unsupported_reasoning_effort/);
  assert.equal(item.messages.length, 0);
  assert.equal(item.active, false);
  assert.equal(calls.length, 0);
  await store.submit(item, { ...body('fixture-deep'), messageID: 'once' }, catalog);
  await item.task;
  await store.submit(item, { ...body('fixture-deep'), messageID: 'once' }, { read: async () => { assert.fail('accepted retry must not rediscover'); } });
  store.submit(item, body(), catalog);
  await item.task;
  store.submit(item, body(), catalog);
  await item.task;
  assert.equal(calls.length, 3);
  assert.equal(calls[0][3].reasoningEffort, 'fixture-deep');
  for (const call of calls.slice(1)) assert.deepEqual(call[3], { resetEffort: true, defaultEffort: 'fixture-light', permissionMode: 'ask' });
  store.close();
});

test('unavailable or missing model effort rejects without acceptance', async () => {
  const store = new Sessions('codex', {}, []);
  const item = session();
  assert.throws(() => store.submit(item, body('fixture-deep')), /effort_requires_available_model/);
  assert.throws(() => store.submit(item, body({})), /invalid_reasoning_effort/);
  await assert.rejects(store.submit(item, body('fixture-deep'), { read: async () => ({ status: 'unavailable', models: [] }) }), /unsupported_reasoning_effort/);
  assert.equal(item.accepted.size, 0);
  assert.equal(item.messages.length, 0);
  store.close();
});

test('Codex applies effort and each advertised safe execution policy per turn', async () => {
  const rpc = new EventEmitter();
  const turns = [];
  rpc.write = () => {};
  rpc.close = () => {};
  rpc.request = async (method, params) => {
    if (method === 'initialize') return {};
    if (method === 'thread/start') {
      assert.equal(params.approvalPolicy, 'untrusted');
      assert.equal(params.sandbox, 'workspace-write');
      return { thread: { id: 'thread' }, model: 'cli-default', reasoningEffort: 'baseline' };
    }
    assert.equal(method, 'turn/start');
    turns.push(params);
    setImmediate(() => rpc.emit('message', { method: 'turn/completed', params: { turn: { status: 'completed' } } }));
    return { turn: { id: 'turn' } };
  };
  const runner = await new CodexAdapter('fixture', () => rpc).open(session(), { delta() {}, permission: async () => false });
  await runner.run('first', 'model', [], { reasoningEffort: 'fixture-deep', permissionMode: 'auto' });
  await runner.run('second', 'model', [], { resetEffort: true, defaultEffort: 'fixture-light', permissionMode: 'read' });
  await runner.run('third', 'default', [], { resetEffort: true, permissionMode: 'ask' });
  assert.deepEqual(turns.map((turn) => turn.effort), ['fixture-deep', 'fixture-light', 'baseline']);
  assert.equal(turns[2].model, 'cli-default');
  assert.deepEqual(turns.map((turn) => turn.approvalPolicy), ['on-request', 'never', 'untrusted']);
  assert.deepEqual(turns.map((turn) => turn.sandboxPolicy), [
    { type: 'workspaceWrite' },
    { type: 'readOnly' },
    { type: 'workspaceWrite' },
  ]);
  runner.close();
});

test('Claude reused query updates and resets session-scoped effort without permission changes', async () => {
  const events = new InputStream();
  const settings = [];
  let queries = 0;
  let initial;
  const adapter = new ClaudeAdapter(({ prompt, options }) => {
    queries++;
    initial = options;
    void (async () => { for await (const _ of prompt) events.push({ type: 'result', subtype: 'success' }); })();
    return { [Symbol.asyncIterator]: () => events, applyFlagSettings: async (value) => settings.push(value), close: () => events.close() };
  });
  const runner = await adapter.open(session(), { delta() {}, permission: async () => false });
  await runner.run('first', 'model', [], { reasoningEffort: 'fixture-deep' });
  await runner.run('second', 'model', [], { resetEffort: true });
  assert.equal(queries, 1);
  assert.equal(initial.effort, 'fixture-deep');
  assert.equal(initial.permissionMode, 'default');
  assert.equal(initial.persistSession, false);
  assert.deepEqual(settings, [{ effortLevel: 'fixture-deep' }, { effortLevel: null }]);
  assert.equal((await initial.canUseTool()).behavior, 'deny');
  assert.ok(initial.hooks.PreToolUse.length);
  runner.close();
});

test('Claude applies only advertised ask and no-tool plan policies', async () => {
  const events = new InputStream();
  const permissionModes = [];
  const decisions = [];
  let initial;
  let permissionRequests = 0;
  const adapter = new ClaudeAdapter(({ prompt, options }) => {
    initial = options;
    void (async () => {
      for await (const _ of prompt) {
        decisions.push(await options.hooks.PreToolUse[0].hooks[0]({
          tool_name: 'Write', tool_input: { file_path: '/fixture/file' },
        }));
        events.push({ type: 'result', subtype: 'success' });
      }
    })();
    return {
      [Symbol.asyncIterator]: () => events,
      setPermissionMode: async (value) => permissionModes.push(value),
      close: () => events.close(),
    };
  });
  const runner = await adapter.open(session(), {
    delta() {},
    permission: async () => { permissionRequests++; return true; },
  });
  await runner.run('plan first', 'default', [], { permissionMode: 'plan' });
  await runner.run('ask next', 'default', [], { permissionMode: 'ask' });
  assert.equal(initial.permissionMode, 'plan');
  assert.deepEqual(permissionModes, ['default']);
  assert.deepEqual(decisions.map((value) => value.hookSpecificOutput.permissionDecision), ['deny', 'allow']);
  assert.equal(permissionRequests, 1);
  runner.close();
});
