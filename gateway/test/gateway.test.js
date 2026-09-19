import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, symlink, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:http';
import { createGateway } from '../src/server.js';
import { Sessions } from '../src/sessions.js';
import { allowedDirectory, privateAddress, resolveRoots } from '../src/security.js';
import { childEnvironment } from '../src/process.js';
import { CodexAdapter, ClaudeAdapter } from '../src/adapters.js';

const token = 'test-only-token-with-at-least-32-characters';
const authorization = `Basic ${Buffer.from(`prompt:${token}`).toString('base64')}`;

async function fixture(t, adapter) {
  const directory = await mkdtemp(join(tmpdir(), 'prompt-gateway-test-'));
  const roots = await resolveRoots([directory]);
  let runs = 0;
  let finish;
  const store = new Sessions('codex', adapter ?? { async open(_, sink) {
    return { async run() { runs++; sink.delta('Test response'); await new Promise((resolve) => { finish = resolve; }); }, async abort() { finish?.(); }, close() { finish?.(); } };
  } }, roots, { turnTimeout: 1000, approvalTimeout: 100 });
  const gateway = createGateway({ token, roots, engines: { codex: store } });
  const address = await gateway.listen(0);
  t.after(async () => { await gateway.close(); await rm(directory, { recursive: true }); });
  const request = async (path, method = 'GET', body, auth = authorization) => fetch(`http://127.0.0.1:${address.port}${path}`, { method, headers: { authorization: auth, 'content-type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  return { directory: roots[0], store, request, runs: () => runs, finish: () => finish?.() };
}

test('private literal bind, upstream and secrets fail closed', async () => {
  for (const address of ['0.0.0.0', '::', '8.8.8.8', 'example.com', '::ffff:127.0.0.1']) assert.equal(privateAddress(address), false);
  for (const address of ['127.0.0.1', '10.0.0.1', '192.168.1.1', '100.64.0.1', 'fd00::1']) assert.equal(privateAddress(address), true);
  assert.throws(() => createGateway({ token, host: '0.0.0.0' }));
  assert.throws(() => createGateway({ token: 'short' }));
  assert.throws(() => createGateway({ token, openCode: { url: 'http://example.com' } }));
  assert.deepEqual(childEnvironment({ HOME: '/test', PROMPT_GATEWAY_TOKEN: 'secret', NODE_OPTIONS: 'evil', ANTHROPIC_API_KEY: 'secret' }), { HOME: '/test' });
});

test('capabilities and all native routes require authentication', async (t) => {
  const f = await fixture(t);
  assert.equal((await f.request('/prompt/capabilities', 'GET', null, '')).status, 401);
  const capabilities = await (await f.request('/prompt/capabilities')).json();
  assert.equal(capabilities.protocolVersion, 1);
  assert.equal(capabilities.engines.claude.available, false);
  assert.equal(capabilities.engines.codex.available, true);
  assert.equal(capabilities.engines.codex.features.includes('terminal'), false);
  assert.equal(capabilities.engines.codex.features.includes('sessionArtifacts'), true);
  assert.equal(capabilities.engines.codex.features.includes('review'), false);
  assert.equal(capabilities.engines.claude.features.includes('sessionArtifacts'), false);
  assert.equal((await f.request('/prompt/codex/session', 'GET', null, '')).status, 401);
  assert.equal((await f.request('/prompt/codex/pty')).status, 404);
});

test('short-lived pairing yields a scoped device credential exactly once', async (t) => {
  const f = await fixture(t);
  assert.equal((await f.request('/prompt/pairings', 'POST', { backend: 'codex' }, '')).status, 401);
  const created = await (await f.request('/prompt/pairings', 'POST', { backend: 'codex' })).json();
  assert.match(created.ticket, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(typeof created.expiresAt, 'number');

  const exchange = await f.request('/prompt/pairings/exchange', 'POST', {
    ticket: created.ticket,
    backend: 'codex',
  }, '');
  assert.equal(exchange.status, 200);
  const paired = await exchange.json();
  assert.equal(paired.username, 'prompt');
  assert.equal(paired.backend, 'codex');
  assert.match(paired.token, /^p1\./);
  assert.equal(paired.token.includes(token), false);
  const deviceAuth = `Basic ${Buffer.from(`prompt:${paired.token}`).toString('base64')}`;
  assert.equal((await f.request('/prompt/capabilities', 'GET', null, deviceAuth)).status, 200);
  assert.equal((await f.request('/prompt/pairings/exchange', 'POST', {
    ticket: created.ticket,
    backend: 'codex',
  }, '')).status, 401);
});

test('roots reject traversal, symlink escape and public prefix confusion', async (t) => {
  const f = await fixture(t);
  const inside = join(f.directory, 'inside');
  await mkdir(inside);
  await symlink(tmpdir(), join(f.directory, 'escape'));
  assert.equal(await allowedDirectory(inside, [f.directory]), inside);
  await assert.rejects(allowedDirectory(join(f.directory, '..'), [f.directory]));
  await assert.rejects(allowedDirectory(join(f.directory, 'escape'), [f.directory]));
  const response = await f.request(`/prompt/codex/session?directory=${encodeURIComponent(tmpdir())}`, 'POST', {});
  assert.equal(response.status, 403);
});

test('project catalogs include active nested workspaces with matching stable IDs', async (t) => {
  const f = await fixture(t);
  const directory = join(f.directory, 'nested-worktree');
  await mkdir(directory);
  const create = () => f.request(`/prompt/codex/session?directory=${encodeURIComponent(directory)}`, 'POST', {});
  const first = await (await create()).json();
  const second = await (await create()).json();
  const projects = await (await f.request('/prompt/codex/project')).json();
  const project = projects.find((entry) => entry.worktree === directory);
  assert.ok(project, 'Every active session directory must have an authoritative project catalog');
  assert.equal(project.id, first.projectID);
  assert.equal(project.id, second.projectID);
  assert.equal(projects.filter((entry) => entry.worktree === directory).length, 1);
  assert.equal(projects.find((entry) => entry.worktree === f.directory).id, 'root_0');
  assert.notEqual(project.id, 'root_0');
  const visible = (await Promise.all(projects.map(async (entry) =>
    (await f.request(`/prompt/codex/session?directory=${encodeURIComponent(entry.worktree)}`)).json()))).flat();
  assert.deepEqual(new Set(visible.map((entry) => entry.id)), new Set([first.id, second.id]));
  await f.request(`/prompt/codex/session/${first.id}`, 'DELETE');
  assert.ok((await (await f.request('/prompt/codex/project')).json()).some((entry) => entry.id === project.id));
  await f.request(`/prompt/codex/session/${second.id}`, 'DELETE');
  assert.equal((await (await f.request('/prompt/codex/project')).json()).some((entry) => entry.id === project.id), false);
});

test('native session records expose bounded branch and completed in-workspace diffs', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'prompt-gateway-artifacts-'));
  const roots = await resolveRoots([directory]);
  const store = new Sessions('codex', {}, roots, {
    workspaceMetadata: async () => ({ branch: 'refs/heads/main' }),
  });
  t.after(async () => { store.close(); await rm(directory, { recursive: true }); });
  const created = await store.create(directory);
  const session = store.get(created.id);
  session.active = true;
  store.changes(session, [
    { path: join(session.directory, 'lib/a.dart'), kind: { type: 'update' }, diff: '@@ -1 +1 @@\n-old\n+new' },
    { path: join(session.directory, '..', 'outside.txt'), kind: { type: 'add' }, diff: '+secret' },
  ]);
  const record = store.record(session);
  assert.equal(record.branch, 'refs/heads/main');
  assert.deepEqual(record.summary, { files: 1, additions: 1, deletions: 1 });
  assert.deepEqual([...session.diffs.values()], [{ file: 'lib/a.dart', patch: '@@ -1 +1 @@\n-old\n+new', additions: 1, deletions: 1, status: 'modified' }]);
});

test('session queue does not interrupt and duplicate acceptance never executes twice', async (t) => {
  const f = await fixture(t);
  const record = await (await f.request('/prompt/codex/session', 'POST', {})).json();
  const path = `/prompt/codex/session/${record.id}`;
  const body = { messageID: 'client-operation-1', parts: [{ type: 'text', text: 'A safe fixture' }] };
  assert.equal((await f.request(`${path}/prompt_async`, 'POST', body)).status, 204);
  assert.equal((await f.request(`${path}/prompt_async`, 'POST', body)).status, 204);
  assert.equal((await f.request(`${path}/prompt_async`, 'POST', { ...body, parts: [{ type: 'text', text: 'changed' }] })).status, 409);
  assert.equal((await f.request(`${path}/prompt_async`, 'POST', { parts: [{ type: 'text', text: 'queued' }] })).status, 409);
  assert.equal(f.runs(), 1);
  assert.equal((await f.request(path, 'DELETE')).status, 409);
  assert.equal((await f.request(`${path}/abort`, 'POST')).status, 200);
  await f.store.get(record.id).task;
  assert.equal(f.store.get(record.id).status, 'idle');
  const messages = await (await f.request(`${path}/message`)).json();
  assert.equal(messages[1].parts[0].text, 'Test response');
  assert.equal((await f.request('/prompt/codex/session/codex_previous-epoch/message')).status, 404);
});

test('permissions show exact arguments, reject always, and close denies pending requests', async (t) => {
  const f = await fixture(t);
  const record = await f.store.create(f.directory);
  const session = f.store.get(record.id);
  session.active = true;
  const decision = f.store.permission(session, 'Bash', { command: 'echo fixture' });
  const permission = [...f.store.permissions.values()][0].record;
  assert.match(permission.title, /echo fixture/);
  assert.throws(() => f.store.reply(permission.id, 'always'));
  assert.throws(() => f.store.reply(permission.id, 'once', 'another-session'));
  f.store.close();
  assert.equal(await decision, false);
});

test('Codex approval presents exact action without internal routing identifiers', async (t) => {
  const f = await fixture(t);
  const record = await f.store.create(f.directory);
  const session = f.store.get(record.id);
  session.active = true;
  // Shape of Codex 0.154.0 item/commandExecution/requestApproval. Values are
  // synthetic; no real command is executed or user path included.
  const input = {
    threadId: 'thread-fixture', turnId: 'turn-fixture', itemId: 'item-fixture',
    environmentId: 'environment-fixture',
    command: "printf '%s\\n' 'a b' && git status --short",
    cwd: '/fixture/project with spaces',
    reason: 'Inspect the requested working tree.',
    commandActions: [{ type: 'unknown', command: 'git status --short' }],
    availableDecisions: ['accept', 'decline'],
    additionalPermissions: null, networkApprovalContext: null,
    proposedExecpolicyAmendment: null,
  };
  const decision = f.store.permission(session, 'item/commandExecution/requestApproval', input);
  const permission = [...f.store.permissions.values()][0].record;
  assert.equal(permission.type, 'bash');
  assert.equal(permission.title, `Run command\n\n${input.command}\n\nWorking directory: ${input.cwd}\n\nReason: ${input.reason}`);
  assert.deepEqual(permission.metadata, input);
  assert.equal(permission.title.includes('thread-fixture'), false);
  f.store.reply(permission.id, 'reject', session.id);
  assert.equal(await decision, false);
});

test('readable approvals preserve expanded security scope and unknown fields', async (t) => {
  const f = await fixture(t);
  const record = await f.store.create(f.directory);
  const session = f.store.get(record.id);
  session.active = true;
  const input = {
    threadId: 'thread-fixture', turnId: 'turn-fixture', itemId: 'item-fixture',
    command: 'fixture command', cwd: '/fixture',
    additionalPermissions: { fileSystem: { write: ['/outside-fixture'] } },
    networkApprovalContext: { host: 'service.example.test', protocol: 'https' },
    proposedExecpolicyAmendment: ['fixture', '--mode'],
    futureSecurityScope: { important: true },
  };
  const decision = f.store.permission(session, 'item/commandExecution/requestApproval', input);
  const permission = [...f.store.permissions.values()][0].record;
  for (const key of ['additionalPermissions', 'networkApprovalContext', 'proposedExecpolicyAmendment', 'futureSecurityScope']) {
    assert.equal(permission.title.includes(JSON.stringify(input[key], null, 2)), true, key);
  }
  assert.equal(permission.title.includes('/outside-fixture'), true);
  assert.equal(permission.title.includes('service.example.test'), true);
  f.store.reply(permission.id, 'reject', session.id);
  assert.equal(await decision, false);
});

test('file approval describes its denied grant root without presenting one-time approval', async (t) => {
  const f = await fixture(t);
  const record = await f.store.create(f.directory);
  const session = f.store.get(record.id);
  session.active = true;
  const input = { threadId: 'thread-fixture', turnId: 'turn-fixture', itemId: 'item-fixture', grantRoot: '/fixture/target', reason: 'Apply requested changes.' };
  session.assistant = f.store.message(session, 'assistant', '');
  const decision = f.store.permission(session, 'item/fileChange/requestApproval', input);
  assert.equal(f.store.permissions.size, 0);
  assert.match(session.assistant.parts[0].text, /Denied/);
  assert.match(session.assistant.parts[0].text, /Requested root: \/fixture\/target/);
  assert.match(session.assistant.parts[0].text, /Reason: Apply requested changes/);
  assert.equal(await decision, false);
});

test('network-only approval keeps host and protocol without inventing a command', async (t) => {
  const f = await fixture(t);
  const record = await f.store.create(f.directory);
  const session = f.store.get(record.id);
  session.active = true;
  const input = { threadId: 'thread-fixture', networkApprovalContext: { host: 'service.example.test', protocol: 'https' }, reason: 'Access the requested service.' };
  const decision = f.store.permission(session, 'item/commandExecution/requestApproval', input);
  const permission = [...f.store.permissions.values()][0].record;
  assert.equal(permission.type, 'network');
  assert.match(permission.title, /^Allow network access\n/);
  assert.equal(permission.title.includes(JSON.stringify(input.networkApprovalContext, null, 2)), true);
  assert.equal(permission.title.includes('Run command'), false);
  assert.deepEqual(permission.metadata, input);
  f.store.reply(permission.id, 'reject', session.id);
  assert.equal(await decision, false);
});

test('failed native context cannot silently restart or accept queued work', async (t) => {
  const f = await fixture(t, { async open() { throw Error('private detail'); } });
  const record = await f.store.create(f.directory);
  const session = f.store.get(record.id);
  const events = [];
  f.store.on('event', (event) => events.push(event));
  f.store.submit(session, { parts: [{ type: 'text', text: 'fixture' }] });
  await session.task;
  assert.equal(session.broken, true);
  assert.equal(session.status, 'error');
  assert.equal(events.some((event) => event.payload.type === 'session.idle'), false);
  assert.match(session.messages[1].parts[0].text, /create a new session/);
  assert.throws(() => f.store.submit(session, { parts: [{ type: 'text', text: 'next' }] }), /session_failed/);
  assert.equal(JSON.stringify(session.messages).includes('private detail'), false);
});

test('Codex real subprocess fixture validates handshake, deltas and completion', async (t) => {
  const f = await fixture(t);
  // Node itself is the fake CLI; no provider or credential is contacted.
  const { JsonProcess } = await import('../src/process.js');
  const adapter = new CodexAdapter(process.execPath, (executable, args, cwd) => {
    assert.deepEqual(args.slice(0, 3), ['app-server', '--listen', 'stdio://']);
    return new JsonProcess(executable, [new URL('./fixtures/codex.mjs', import.meta.url).pathname], cwd);
  });
  let output = '';
  const runner = await adapter.open({ directory: f.directory }, { delta: (text) => { output += text; }, permission: async () => false });
  t.after(() => runner.close());
  await runner.run('fixture');
  assert.equal(output, 'fixture response');
});

test('Claude SDK hook gates every tool and retains one nonpersistent native context', async () => {
  const options = [];
  const adapter = new ClaudeAdapter(({ prompt, options: settings }) => {
    options.push(settings);
    const stream = (async function* () {
      for await (const _message of prompt) {
        const result = await settings.hooks.PreToolUse[0].hooks[0]({ tool_name: 'Bash', tool_input: { command: 'fixture' } });
        assert.equal(result.hookSpecificOutput.permissionDecision, 'deny');
        yield { type: 'system', subtype: 'init', session_id: 'native-session' };
        yield { type: 'stream_event', event: { delta: { type: 'text_delta', text: 'fixture' } } };
        yield { type: 'result', subtype: 'success', is_error: false };
      }
    })();
    stream.close = () => { void stream.return(); };
    return stream;
  });
  let text = '';
  const runner = await adapter.open({ directory: '/fixture' }, { delta: (value) => { text += value; }, permission: async () => false });
  await runner.run('first'); await runner.run('second');
  assert.equal(options.length, 1);
  assert.equal(options[0].persistSession, false);
  assert.equal(options[0].resume, undefined);
  assert.deepEqual(options[0].settingSources, []);
  assert.equal(options[0].permissionMode, 'default');
  assert.equal(text, 'fixturefixture');
  runner.close();
});

test('SSE disconnect releases its subscription and snapshots reconcile deltas', async (t) => {
  const f = await fixture(t);
  const stream = await f.request('/prompt/codex/global/event');
  const reader = stream.body.getReader();
  assert.equal(f.store.listenerCount('event'), 1);
  assert.match(new TextDecoder().decode((await reader.read()).value), /connected/);
  const session = await f.store.create(f.directory);
  f.store.submit(f.store.get(session.id), { parts: [{ type: 'text', text: 'fixture' }] });
  const frame = new TextDecoder().decode((await reader.read()).value);
  assert.match(frame, /message.updated/);
  await reader.cancel();
  f.finish();
  await f.store.get(session.id).task;
});

test('OpenCode proxy authenticates separately, rejects redirects and unsafe routes', async (t) => {
  let observedAuthorization;
  const upstream = createServer((request, response) => {
    observedAuthorization = request.headers.authorization;
    if (request.url === '/provider') { response.writeHead(302, { location: 'http://example.com' }); response.end(); }
    else { response.setHeader('content-type', 'application/json'); response.end(JSON.stringify({ healthy: true, version: 'fixture' })); }
  });
  await new Promise((resolve) => upstream.listen(0, '127.0.0.1', resolve));
  const gateway = createGateway({ token, roots: [], engines: {}, openCode: { url: `http://127.0.0.1:${upstream.address().port}/`, password: 'upstream-fixture' } });
  const address = await gateway.listen(0);
  t.after(async () => { await gateway.close(); upstream.closeAllConnections(); await new Promise((resolve) => upstream.close(resolve)); });
  const request = (path) => fetch(`http://127.0.0.1:${address.port}/prompt/opencode${path}`, { headers: { authorization } });
  assert.equal((await request('/global/health')).status, 200);
  assert.equal(observedAuthorization, `Basic ${Buffer.from('opencode:upstream-fixture').toString('base64')}`);
  assert.notEqual(observedAuthorization, authorization);
  assert.equal((await request('/provider')).status, 500);
  assert.equal((await request('/global/dispose')).status, 404);
  assert.equal((await request('/session/fixture/share')).status, 404);
});
