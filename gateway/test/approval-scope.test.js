import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { CodexAdapter } from '../src/adapters.js';
import { Sessions } from '../src/sessions.js';
import { approvalPresentation } from '../src/approval-presentation.js';

test('Claude Bash approval presents the exact command and preserves extra permissions', () => {
  const input = { command: 'pwd', description: 'Print working directory', dangerouslyDisableSandbox: true, threadId: 'tool-input-not-routing' };
  const presentation = approvalPresentation('Bash', input);
  assert.equal(presentation.type, 'bash');
  assert.match(presentation.title, /^Run command\n\npwd\n\nDescription: Print working directory/);
  assert.match(presentation.title, /dangerouslyDisableSandbox:\ntrue/);
  assert.match(presentation.title, /tool-input-not-routing/);
  assert.equal(input.command, 'pwd');
});

async function fixture() {
  const rpc = new EventEmitter();
  const replies = [];
  const requests = [];
  const completedChanges = [];
  rpc.write = (value) => replies.push(value);
  rpc.close = () => {};
  rpc.request = async (method) => method === 'thread/start' ? { thread: { id: 'thread' } } : {};
  const runner = await new CodexAdapter('fixture', () => rpc).open({ directory: '/fixture' }, { delta() {}, changes: (value) => completedChanges.push(value), permission: async (method, params) => { requests.push(params); return true; } });
  return { rpc, replies, requests, completedChanges, runner };
}

test('session-scoped grantRoot never becomes accept even when generic sink says allow', async () => {
  const f = await fixture();
  f.rpc.emit('message', { id: 1, method: 'item/fileChange/requestApproval', params: { threadId: 'thread', turnId: 'turn', itemId: 'file', startedAtMs: 1, grantRoot: '/outside fixture' } });
  await new Promise(setImmediate);
  assert.equal(f.replies.at(-1).result.decision, 'decline');
  f.runner.close();
});

test('provided availableDecisions never permits an unoffered accept', async () => {
  const f = await fixture();
  f.rpc.emit('message', { id: 2, method: 'item/commandExecution/requestApproval', params: { availableDecisions: ['cancel'], command: 'fixture' } });
  await new Promise(setImmediate);
  assert.equal(f.replies.at(-1).result.decision, 'cancel');
  f.rpc.emit('message', { id: 5, method: 'item/commandExecution/requestApproval', params: { availableDecisions: [], command: 'fixture' } });
  await new Promise(setImmediate);
  assert.equal(f.replies.at(-1).result, undefined);
  assert.equal(f.replies.at(-1).error.code, -32602);
  f.rpc.emit('message', { id: 6, method: 'item/commandExecution/requestApproval', params: { availableDecisions: ['accept', 'decline'], command: 'fixture' } });
  await new Promise(setImmediate);
  assert.equal(f.replies.at(-1).result.decision, 'accept');
  f.runner.close();
});

test('blocked scope is visible without exposing a misleading pending Allow once', async () => {
  const store = new Sessions('codex', {}, [], { approvalTimeout: 10 });
  const session = { id: 'session', active: true, outputBytes: 0, assistant: { parts: [{ text: '' }] } };
  const allowed = await store.permission(session, 'item/fileChange/requestApproval', { grantRoot: '/outside fixture', reason: 'Needs wider access' });
  assert.equal(allowed, false);
  assert.equal(store.permissions.size, 0);
  assert.match(session.assistant.parts[0].text, /outside fixture/);
  assert.match(session.assistant.parts[0].text, /Needs wider access/);
  assert.match(session.assistant.parts[0].text, /session/i);
  store.close();
});

test('file scope is correlated from actual item started contract by thread turn and item', async () => {
  const f = await fixture();
  const changes = [{ path: '/fixture/a.txt', kind: { type: 'add' }, diff: '+synthetic' }];
  f.rpc.emit('message', { method: 'item/started', params: { threadId: 'thread', turnId: 'turn', item: { id: 'file', type: 'fileChange', status: 'inProgress', changes } } });
  f.rpc.emit('message', { id: 3, method: 'item/fileChange/requestApproval', params: { threadId: 'thread', turnId: 'turn', itemId: 'file' } });
  await new Promise(setImmediate);
  assert.deepEqual(f.requests.at(-1).changes, changes);
  f.rpc.emit('message', { id: 4, method: 'item/fileChange/requestApproval', params: { threadId: 'other', turnId: 'turn', itemId: 'file' } });
  await new Promise(setImmediate);
  assert.equal(f.requests.at(-1).changes, undefined);
  f.rpc.emit('message', { method: 'turn/completed', params: { turn: { status: 'completed' } } });
  f.rpc.emit('message', { id: 7, method: 'item/fileChange/requestApproval', params: { threadId: 'thread', turnId: 'turn', itemId: 'file' } });
  await new Promise(setImmediate);
  assert.equal(f.requests.at(-1).changes, undefined);
  f.runner.close();
});

test('only successfully completed file changes reach session artifacts', async () => {
  const f = await fixture();
  const changes = [{ path: '/fixture/a.txt', kind: { type: 'update', move_path: null }, diff: '@@ -1 +1 @@\n-old\n+new' }];
  for (const status of ['failed', 'declined', 'inProgress']) {
    f.rpc.emit('message', { method: 'item/completed', params: { threadId: 'thread', turnId: 'turn', item: { id: status, type: 'fileChange', status, changes } } });
  }
  assert.deepEqual(f.completedChanges, []);
  f.rpc.emit('message', { method: 'item/completed', params: { threadId: 'thread', turnId: 'turn', item: { id: 'done', type: 'fileChange', status: 'completed', changes } } });
  assert.deepEqual(f.completedChanges, [changes]);
  f.runner.close();
});

test('reply broadcasts exact resolution to both observers including expiry and close, never idle', async () => {
  const store = new Sessions('codex', {}, [], { approvalTimeout: 10 });
  const session = { id: 'session', directory: '/fixture', active: true };
  const observers = [[], []];
  for (const events of observers) store.on('event', (event) => events.push(event));
  for (const action of ['once', 'reject', 'timeout', 'close']) {
    const pending = store.permission(session, 'Bash', { command: 'fixture' });
    const id = [...store.permissions.keys()][0];
    if (action === 'close') store.close();
    else if (action !== 'timeout') store.reply(id, action, session.id);
    assert.equal(await pending, action === 'once');
    for (const events of observers) {
      const event = events.at(-1);
      assert.equal(event.directory, '/fixture');
      assert.deepEqual(event.payload, { type: 'permission.replied', properties: { sessionID: 'session', requestID: id, response: action === 'once' ? 'once' : 'reject' } });
      assert.equal(events.some((value) => value.payload.type === 'session.idle'), false);
    }
  }
  assert.deepEqual(observers[0], observers[1]);
});
