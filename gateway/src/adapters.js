import { JsonProcess, childEnvironment } from './process.js';
import { Fault } from './security.js';
import { abortable } from './model-catalog.js';
import { InputStream } from './input-stream.js';
import { randomUUID } from 'node:crypto';
import { approvalRestriction, denialDecision } from './approval-presentation.js';

export class CodexAdapter {
  constructor(executable, makeProcess = (executable, args, cwd, options) => new JsonProcess(executable, args, cwd, undefined, options)) {
    this.executable = executable;
    this.makeProcess = makeProcess;
  }
  async discoverModels(directory, { signal }) {
    if (signal.aborted) throw new Error('catalog_cancelled');
    const rpc = this.makeProcess(this.executable, ['app-server', '--listen', 'stdio://', '-c', 'analytics.enabled=false'], directory);
    // Discovery does not start a thread and cannot approve server requests.
    rpc.on('message', (message) => {
      if (message.id !== undefined && message.method) rpc.write({ id: message.id, error: { code: -32601, message: 'Unsupported discovery request' } });
    });
    try {
      return await abortable(async () => {
        await rpc.request('initialize', { clientInfo: { name: 'prompt_model_catalog', version: '0.1.0' } });
        rpc.write({ method: 'initialized', params: {} });
        const models = [];
        const cursors = new Set();
        let cursor;
        for (let page = 0; page < 8; page++) {
          if (signal.aborted) throw new Error('catalog_cancelled');
          const result = await rpc.request('model/list', { limit: 64, includeHidden: false, ...(cursor ? { cursor } : {}) });
          if (!Array.isArray(result?.data)) throw new Error('invalid_catalog');
          for (const model of result.data) {
            if (model && !model.hidden) models.push({ id: model.model, name: model.displayName,
              ...(Array.isArray(model.supportedReasoningEfforts) && model.supportedReasoningEfforts.some((option) => option.reasoningEffort === model.defaultReasoningEffort) ? {
                executionOptions: { version: 1, defaultReasoningEffortId: model.defaultReasoningEffort,
                  reasoningEfforts: model.supportedReasoningEfforts.map((option) => ({ id: option.reasoningEffort, description: option.description })) },
              } : {}),
            });
          }
          if (models.length > 256) throw new Error('catalog_limit');
          if (result.nextCursor == null) return models;
          if (typeof result.nextCursor !== 'string' || !result.nextCursor || result.nextCursor.length > 4096 || cursors.has(result.nextCursor)) throw new Error('invalid_cursor');
          cursor = result.nextCursor;
          cursors.add(cursor);
        }
        throw new Error('catalog_limit');
      }, signal);
    } finally { rpc.close(); }
  }
  async open(session, sink) {
    const rpc = this.makeProcess(this.executable, ['app-server', '--listen', 'stdio://', '-c', 'analytics.enabled=false'], session.directory, { maxFrameBytes: 16 * 1024 * 1024 });
    let turnId;
    let startPending;
    let active = false;
    let completed;
    let rejectCompletion;
    const fileScopes = new Map();
    let fileScopeBytes = 0;
    const scopeKey = (p, itemId = p.itemId) => [p.threadId, p.turnId, itemId].every((id) => typeof id === 'string' && id.length <= 128) ? JSON.stringify([p.threadId, p.turnId, itemId]) : null;
    rpc.on('message', (message) => {
      const p = message.params ?? {};
      if (message.id !== undefined) {
        if (['item/commandExecution/requestApproval', 'item/fileChange/requestApproval'].includes(message.method)) {
          const scope = message.method === 'item/fileChange/requestApproval' ? fileScopes.get(scopeKey(p)) : null;
          const details = scope ? { ...p, changes: scope.changes } : p;
          sink.permission(message.method, details).then((allow) => {
            const decision = allow && !approvalRestriction(message.method, details) ? 'accept' : denialDecision(details);
            if (!rpc.closed) rpc.write(decision ? { id: message.id, result: { decision } } : { id: message.id, error: { code: -32602, message: 'No supported one-time approval decision' } });
          }).catch(() => rpc.close());
        } else {
          // Unknown requests never become implicit permissions or guessed answers.
          rpc.write({ id: message.id, error: { code: -32601, message: 'Unsupported client request' } });
        }
      } else if (message.method === 'item/started' && p.item?.type === 'fileChange') {
        const key = scopeKey(p, p.item.id);
        const changes = p.item.changes;
        if (key && fileScopes.has(key)) { fileScopeBytes -= fileScopes.get(key).size; fileScopes.delete(key); }
        if (key && Array.isArray(changes) && changes.length <= 128 && changes.every((change) => typeof change?.path === 'string' && typeof change.diff === 'string' && ['add', 'delete', 'update'].includes(change.kind?.type))) {
          const size = Buffer.byteLength(JSON.stringify(changes));
          if (size <= 48 * 1024) {
            while (fileScopes.size && (fileScopes.size >= 32 || fileScopeBytes + size > 64 * 1024)) {
              const oldest = fileScopes.keys().next().value;
              fileScopeBytes -= fileScopes.get(oldest).size; fileScopes.delete(oldest);
            }
            fileScopes.set(key, { changes, size }); fileScopeBytes += size;
          }
        }
      } else if (message.method === 'item/agentMessage/delta') sink.delta(p.delta ?? '');
      else if (message.method === 'turn/started') turnId = p.turn?.id;
      else if (message.method === 'turn/completed') {
        fileScopes.clear(); fileScopeBytes = 0;
        if (p.turn?.status === 'failed') rejectCompletion?.(new Fault(502, 'agent_turn_failed'));
        else completed?.();
      }
    });
    rpc.on('closed', () => rejectCompletion?.(new Fault(502, 'agent_disconnected')));
    try {
      await rpc.request('initialize', { clientInfo: { name: 'prompt_private_gateway', version: '0.1.0' } });
      rpc.write({ method: 'initialized', params: {} });
      const result = await rpc.request('thread/start', {
        cwd: session.directory, approvalPolicy: 'untrusted', sandbox: 'workspace-write', ephemeral: true,
      });
      const threadId = result.thread?.id;
      if (typeof threadId !== 'string') throw new Fault(502, 'agent_protocol_error');
      return {
        async run(text, model, images = [], execution = {}) {
          if (active) throw new Fault(409, 'session_busy');
          if (execution.resetEffort && !execution.defaultEffort && typeof result.reasoningEffort !== 'string') throw new Fault(502, 'effort_default_unavailable');
          active = true;
          fileScopes.clear(); fileScopeBytes = 0;
          turnId = undefined;
          const completion = new Promise((resolve, reject) => { completed = resolve; rejectCompletion = reject; });
          // Attach immediately: the process can close while turn/start is pending.
          completion.catch(() => {});
          startPending = rpc.request('turn/start', {
            threadId, input: [
              ...(text ? [{ type: 'text', text, text_elements: [] }] : []),
              ...images.map((image) => ({ type: 'image', url: image.url })),
            ],
            ...(model && model !== 'default' ? { model } : model === 'default' && typeof result.model === 'string' ? { model: result.model } : {}),
            ...(execution.reasoningEffort !== undefined ? { effort: execution.reasoningEffort }
              : execution.resetEffort ? { effort: execution.defaultEffort ?? result.reasoningEffort } : {}),
          }).then((result) => {
            turnId = result.turn?.id ?? turnId;
            if (typeof turnId !== 'string') throw new Fault(502, 'agent_protocol_error');
            return turnId;
          });
          try {
            await startPending;
            await completion;
          } finally {
            active = false;
            startPending = undefined;
            turnId = undefined;
          }
        },
        async abort() {
          if (!active || !startPending) throw new Fault(409, 'no_active_turn');
          const currentTurnId = await startPending;
          // A turn can finish while its start response is being delivered.
          // Do not acknowledge a cancellation that was never sent.
          if (!active || turnId !== currentTurnId) throw new Fault(409, 'turn_already_completed');
          await rpc.request('turn/interrupt', { threadId, turnId: currentTurnId });
        },
        close() { fileScopes.clear(); fileScopeBytes = 0; rpc.close(); },
      };
    } catch (error) { rpc.close(); throw error; }
  }
}

export class ClaudeAdapter {
  constructor(query) { this.query = query; }
  async discoverModels(directory, { signal }) {
    if (signal.aborted) throw new Error('catalog_cancelled');
    const controller = new AbortController();
    let endInput;
    const finished = new Promise((resolve) => { endInput = resolve; });
    async function* emptyInput() { await finished; }
    let running;
    try {
      running = this.query({ prompt: emptyInput(), options: {
        cwd: directory, settingSources: [], env: childEnvironment(),
        abortController: controller, persistSession: false, tools: [],
        permissionMode: 'default', canUseTool: async () => ({ behavior: 'deny', message: 'Discovery cannot use tools' }),
        stderr: () => {},
      } });
      const models = await abortable(() => running.supportedModels(), signal);
      if (!Array.isArray(models) || models.length > 256) throw new Error('invalid_catalog');
      return models.map((model) => ({ id: model?.value, name: model?.displayName,
        ...(model?.supportsEffort === true && Array.isArray(model.supportedEffortLevels) ? {
          executionOptions: { version: 1, reasoningEfforts: model.supportedEffortLevels.map((id) => ({ id })) },
        } : {}),
      }));
    } finally {
      endInput();
      controller.abort();
      running?.close();
    }
  }
  async open(session, sink) {
    const query = this.query;
    const input = new InputStream();
    const controller = new AbortController();
    let running;
    let pending;
    let active = false;
    let closed = false;
    let selectedModel;
    let streamed = false;
    const close = () => {
      if (closed) return;
      closed = true;
      input.close();
      controller.abort();
      try { running?.close(); } catch { /* Cleanup must still reject the active turn. */ }
      pending?.reject(new Fault(502, 'agent_disconnected'));
      pending = undefined;
    };
    const consume = async () => {
      try {
        for await (const event of running) {
          if (!pending || event.parent_tool_use_id) continue;
          if (event.type === 'stream_event' && event.event?.delta?.type === 'text_delta') {
            streamed = true;
            sink.delta(event.event.delta.text);
          }
          if (!streamed && event.type === 'assistant') {
            for (const part of event.message?.content ?? []) if (part.type === 'text') sink.delta(part.text);
          }
          if (event.type === 'result') {
            const turn = pending;
            pending = undefined;
            if (event.is_error || event.subtype !== 'success') turn.reject(new Fault(502, 'agent_turn_failed'));
            else turn.resolve();
          }
        }
        pending?.reject(new Fault(502, 'agent_incomplete'));
      } catch {
        pending?.reject(new Fault(502, 'agent_disconnected'));
      } finally { close(); }
    };
    return {
      async run(text, model, images = [], execution = {}) {
        if (closed) throw new Fault(502, 'agent_disconnected');
        if (active) throw new Fault(409, 'session_busy');
        active = true;
        streamed = false;
        const completion = new Promise((resolve, reject) => { pending = { resolve, reject }; });
        completion.catch(() => {});
        const desiredModel = model && model !== 'default' ? model : undefined;
        try {
          if (!running) {
            selectedModel = desiredModel;
            running = query({ prompt: input, options: {
              cwd: session.directory, settingSources: [], permissionMode: 'default',
              env: childEnvironment(), abortController: controller,
              persistSession: false, includePartialMessages: true,
              ...(desiredModel ? { model: desiredModel } : {}),
              ...(execution.reasoningEffort !== undefined ? { effort: execution.reasoningEffort } : {}),
              tools: ['Read', 'Glob', 'Grep', 'Bash', 'Edit', 'Write'],
              hooks: { PreToolUse: [{ hooks: [async (input) => ({ hookSpecificOutput: {
                hookEventName: 'PreToolUse',
                permissionDecision: await sink.permission(input.tool_name, input.tool_input) ? 'allow' : 'deny',
                permissionDecisionReason: 'Explicit Prompt user decision',
              } })] }] },
              canUseTool: async () => ({ behavior: 'deny', message: 'Tool was not approved by Prompt' }),
              stderr: () => {},
            } });
            void consume();
          } else if (selectedModel !== desiredModel) {
            await running.setModel(desiredModel);
            selectedModel = desiredModel;
          }
          if (execution.reasoningEffort !== undefined || execution.resetEffort) {
            if (typeof running.applyFlagSettings !== 'function') throw new Fault(502, 'effort_control_unavailable');
            await running.applyFlagSettings({ effortLevel: execution.reasoningEffort ?? null });
          }
          if (closed) throw new Fault(502, 'agent_disconnected');
          input.push({ type: 'user', uuid: randomUUID(), parent_tool_use_id: null,
            message: { role: 'user', content: [
              ...(text ? [{ type: 'text', text }] : []),
              ...images.map((image) => ({ type: 'image', source: { type: 'base64', media_type: image.mime, data: image.data } })),
            ] },
          });
          await completion;
        } catch (error) {
          close();
          throw error;
        } finally {
          pending = undefined;
          active = false;
        }
      },
      async abort() {
        if (!active || !running) throw new Fault(409, 'no_active_turn');
        await running.interrupt();
      },
      close,
    };
  }
}
