import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import { CodexAdapter, ClaudeAdapter } from '../src/adapters.js';
import { InputStream } from '../src/input-stream.js';
import { JsonProcess } from '../src/process.js';
import { Sessions } from '../src/sessions.js';
import { createGateway } from '../src/server.js';
import { imageConstraints, validatePromptParts } from '../src/image-input.js';

const png = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10, 1]);
const file = (bytes = png, mime = 'image/png') => ({ type: 'file', mime, filename: 'Synthetic.png', url: `data:${mime};base64,${bytes.toString('base64')}` });
const sessionFixture = () => ({ id: 'synthetic', directory: '/fixture', messages: [], accepted: new Map(), status: 'idle', active: false, outputBytes: 0, imageBytes: 0, time: {} });

test('PNG/JPEG/GIF/WebP inputs are inline and preserve exact bytes', () => {
  for (const [bytes, mime] of [[png, 'image/png'], [Buffer.from([255, 216, 255, 1]), 'image/jpeg'], [Buffer.from('GIF89a'), 'image/gif'], [Buffer.from('RIFF0000WEBP'), 'image/webp']]) {
    const value = validatePromptParts([file(bytes, mime)]);
    assert.equal(value.text, '');
    assert.deepEqual(Buffer.from(value.images[0].data, 'base64'), bytes);
    assert.equal(value.parts[0].url, file(bytes, mime).url);
  }
});

test('unsupported paths/types/encodings/signatures and invalid sizes fail before acceptance', () => {
  for (const part of [
    { ...file(), url: 'https://fixture.invalid/image.png' },
    { ...file(), url: 'file:///private/image.png' },
    file(Buffer.from('%PDF'), 'application/pdf'),
    { ...file(), url: 'data:image/jpeg;base64,/9j/' },
    { ...file(), url: 'data:image/png;base64,AAAA' },
    { ...file(), url: 'data:image/png;base64,abc' },
    { ...file(), url: 'data:image/png;base64,YQ=Z' },
    { ...file(), filename: 'bad\nname' },
    { type: 'file', mime: 'image/png', url: 1 },
  ]) assert.throws(() => validatePromptParts([part]));
  assert.throws(() => validatePromptParts(Array(6).fill(file())), /attachment_count_limit/);
  const big = Buffer.alloc(imageConstraints.maxBytesPerAttachment + 1);
  png.copy(big);
  assert.throws(() => validatePromptParts([file(big)]), /attachment_size_limit/);
  const exact = big.subarray(0, imageConstraints.maxBytesPerAttachment);
  assert.throws(() => validatePromptParts([file(exact), file(exact), file()]), /attachment_total_limit/);
  const store = new Sessions('codex', { open() { assert.fail('invalid images must not start a runner'); } }, []);
  const session = sessionFixture();
  assert.throws(() => store.submit(session, { parts: [file(Buffer.from('%PDF'), 'application/pdf')], messageID: 'invalid' }));
  assert.equal(session.active, false);
  assert.equal(session.messages.length, 0);
  assert.equal(session.accepted.size, 0);
});

test('image-only sessions retain identical stable REST/SSE parts and deduplicate acceptance', async () => {
  const calls = [];
  const store = new Sessions('codex', { async open() { return { async run(...args) { calls.push(args); }, close() {} }; } }, []);
  const session = sessionFixture();
  const events = [];
  store.on('event', (event) => events.push(event.payload));
  const body = { messageID: 'image-prompt', parts: [file()] };
  store.submit(session, body);
  await session.task;
  store.submit(session, body);
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], '');
  assert.equal(calls[0][2][0].url, file().url);
  const part = session.messages[0].parts[0];
  assert.equal(part.type, 'file');
  assert.equal(part.messageID, 'image-prompt');
  assert.equal(part.url, file().url);
  assert.deepEqual(events.find((event) => event.type === 'message.part.updated').properties.part, part);
  assert.equal(session.status, 'idle');
  assert.throws(() => store.submit(session, { ...body, parts: [{ type: 'text', text: 'changed' }, file()] }), /message_id_conflict/);
});

test('Codex sends image URLs, not localImage files, and bounds its session frame', async () => {
  const rpc = new EventEmitter();
  let turn;
  let frame;
  rpc.write = () => {};
  rpc.close = () => {};
  rpc.request = async (method, params) => {
    if (method === 'initialize') return {};
    if (method === 'thread/start') { assert.equal(params.ephemeral, true); return { thread: { id: 'thread' } }; }
    if (method === 'turn/start') { turn = params; return { turn: { id: 'turn' } }; }
  };
  const adapter = new CodexAdapter('fixture', (_exe, _args, _cwd, options) => { frame = options; return rpc; });
  const runner = await adapter.open({ directory: '/fixture' }, { delta() {}, permission: async () => false });
  const run = runner.run('Describe', undefined, validatePromptParts([file()]).images);
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(turn.input, [{ type: 'text', text: 'Describe', text_elements: [] }, { type: 'image', url: file().url }]);
  assert.equal(frame.maxFrameBytes, 16 * 1024 * 1024);
  rpc.emit('message', { method: 'turn/completed', params: { turn: { id: 'turn', status: 'completed' } } });
  await run;
  runner.close();
});

function claudeFixture({ held = false, failure = false } = {}) {
  const events = new InputStream();
  const inputs = [];
  const models = [];
  let options;
  let queries = 0;
  let closes = 0;
  let interrupts = 0;
  const adapter = new ClaudeAdapter(({ prompt, options: value }) => {
    queries++;
    options = value;
    void (async () => {
      for await (const message of prompt) {
        inputs.push(message);
        if (held) continue;
        if (inputs.length === 1) events.push({ type: 'stream_event', event: { delta: { type: 'text_delta', text: 'first' } } });
        else events.push({ type: 'assistant', message: { content: [{ type: 'text', text: 'second fallback' }] } });
        events.push({ type: 'result', subtype: failure ? 'error_during_execution' : 'success', is_error: failure });
      }
    })();
    return { [Symbol.asyncIterator]: () => events,
      setModel: async (model) => models.push(model),
      interrupt: async () => { interrupts++; events.push({ type: 'result', subtype: 'success', is_error: false }); },
      close: () => { closes++; events.close(); },
    };
  });
  return { adapter, events, inputs, models, options: () => options, queries: () => queries, closes: () => closes, interrupts: () => interrupts };
}

test('Claude uses one nonpersistent query across image and text turns with final-text fallback', async () => {
  const fixture = claudeFixture();
  const output = [];
  const runner = await fixture.adapter.open({ directory: '/fixture' }, { delta: (text) => output.push(text), permission: async () => false });
  await runner.run('', 'fixture-model', validatePromptParts([file()]).images);
  await runner.run('Continue', 'other-model');
  assert.equal(fixture.queries(), 1);
  assert.equal(fixture.options().persistSession, false);
  assert.equal(fixture.options().resume, undefined);
  assert.deepEqual(fixture.inputs[0].message.content, [{ type: 'image', source: { type: 'base64', media_type: 'image/png', data: png.toString('base64') } }]);
  assert.deepEqual(fixture.inputs[1].message.content, [{ type: 'text', text: 'Continue' }]);
  assert.deepEqual(fixture.models, ['other-model']);
  assert.deepEqual(output, ['first', 'second fallback']);
  runner.close();
  assert.equal(fixture.options().abortController.signal.aborted, true);
  assert.equal(fixture.closes(), 1);
});

test('Claude gates concurrent turns, interrupt retains context, close rejects an unfinished turn', async () => {
  const fixture = claudeFixture({ held: true });
  const runner = await fixture.adapter.open({ directory: '/fixture' }, { delta() {}, permission: async () => false });
  const first = runner.run('first');
  await assert.rejects(runner.run('overlap'), /session_busy/);
  await runner.abort();
  await first;
  assert.equal(fixture.interrupts(), 1);
  assert.equal(fixture.closes(), 0);
  const second = runner.run('second');
  runner.close();
  await assert.rejects(second, /agent_disconnected/);
  assert.equal(fixture.queries(), 1);
  assert.equal(fixture.closes(), 1);
  await assert.rejects(runner.run('later'), /agent_disconnected/);
});

test('Claude failed result closes nonpersistent context rather than restarting silently', async () => {
  const fixture = claudeFixture({ failure: true });
  const runner = await fixture.adapter.open({ directory: '/fixture' }, { delta() {}, permission: async () => false });
  await assert.rejects(runner.run('failure'), /agent_turn_failed/);
  assert.equal(fixture.closes(), 1);
  await assert.rejects(runner.run('again'), /agent_disconnected/);
});

test('JSON frame override is bounded and the default remains 2 MiB', () => {
  function transport(maxFrameBytes) {
    const child = new EventEmitter();
    child.stdin = new PassThrough(); child.stdout = new PassThrough(); child.connected = false;
    const process = new JsonProcess('fixture', [], '/fixture', () => child, maxFrameBytes ? { maxFrameBytes } : undefined);
    return { process, child };
  }
  const normal = transport();
  normal.child.stdout.write('x'.repeat(2 * 1024 * 1024 + 1));
  assert.equal(normal.process.closed, true);
  const images = transport(16 * 1024 * 1024);
  images.child.stdout.write('x'.repeat(3 * 1024 * 1024));
  assert.equal(images.process.closed, false);
  images.child.stdout.write('x'.repeat(14 * 1024 * 1024));
  assert.equal(images.process.closed, true);
  assert.throws(() => transport(17 * 1024 * 1024), /invalid_frame_limit/);
});

test('native capability advertises images-only limits and HTTP accepts bounded image bodies', async (t) => {
  let runs = 0;
  const store = new Sessions('codex', { async open() { return { async run() { runs++; }, close() {} }; } }, []);
  const session = sessionFixture(); store.sessions.set(session.id, session);
  const token = 'fixture-token-at-least-32-characters';
  const gateway = createGateway({ token, roots: [], engines: { codex: store } });
  const address = await gateway.listen(0); t.after(() => gateway.close());
  const headers = { authorization: `Basic ${Buffer.from(`prompt:${token}`).toString('base64')}`, 'content-type': 'application/json' };
  const base = `http://127.0.0.1:${address.port}`;
  const caps = await (await fetch(`${base}/prompt/capabilities`, { headers })).json();
  assert.ok(caps.engines.codex.features.includes('imageAttachments'));
  assert.deepEqual(caps.engines.codex.attachmentConstraints, imageConstraints);
  const bytes = Buffer.alloc(300 * 1024); png.copy(bytes);
  const result = await fetch(`${base}/prompt/codex/session/synthetic/prompt_async`, { method: 'POST', headers, body: JSON.stringify({ parts: [file(bytes)] }) });
  assert.equal(result.status, 204);
  await session.task;
  const history = await (await fetch(`${base}/prompt/codex/session/synthetic/message`, { headers })).json();
  assert.equal(history[0].parts[0].url, file(bytes).url);
  const invalid = await fetch(`${base}/prompt/codex/session/synthetic/prompt_async`, { method: 'POST', headers, body: JSON.stringify({ parts: [file(Buffer.from('%PDF'), 'application/pdf')] }) });
  assert.equal(invalid.status, 400);
  assert.equal(runs, 1);
  const tooLarge = await fetch(`${base}/prompt/codex/session/synthetic/prompt_async`, {
    method: 'POST', headers, body: JSON.stringify({ parts: [file()], padding: 'x'.repeat(15 * 1024 * 1024) }),
  });
  assert.equal(tooLarge.status, 413);
  assert.equal(runs, 1);
  const otherRoute = await fetch(`${base}/prompt/codex/session`, {
    method: 'POST', headers, body: JSON.stringify({ title: 'x'.repeat(300 * 1024) }),
  });
  assert.equal(otherRoute.status, 413, 'non-prompt routes keep the original small request limit');
});

test('Claude input pump ending without result rejects and releases the query', async () => {
  let closed = 0;
  const adapter = new ClaudeAdapter(() => {
    const stream = (async function* () { yield { type: 'system', subtype: 'init' }; })();
    stream.close = () => { closed++; };
    return stream;
  });
  const runner = await adapter.open({ directory: '/fixture' }, { delta() {}, permission: async () => false });
  await assert.rejects(runner.run('never accepted'), /agent_incomplete|agent_disconnected/);
  assert.equal(closed, 1);
});

test('Claude close failure cannot strand an in-flight completion', async () => {
  const events = new InputStream();
  const adapter = new ClaudeAdapter(() => ({ [Symbol.asyncIterator]: () => events, close() { events.close(); throw new Error('synthetic cleanup failure'); } }));
  const runner = await adapter.open({ directory: '/fixture' }, { delta() {}, permission: async () => false });
  const run = runner.run('pending');
  runner.close();
  await assert.rejects(run, /agent_disconnected/);
});
