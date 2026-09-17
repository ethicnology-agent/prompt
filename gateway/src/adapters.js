import { JsonProcess, childEnvironment } from './process.js';
import { Fault } from './security.js';
import { approvalRestriction, denialDecision } from './approval-presentation.js';

export class CodexAdapter {
  constructor(executable, makeProcess = (...args) => new JsonProcess(...args)) {
    this.executable = executable;
    this.makeProcess = makeProcess;
  }
  async open(session, sink) {
    const rpc = this.makeProcess(this.executable, ['app-server', '--listen', 'stdio://', '-c', 'analytics.enabled=false'], session.directory);
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
        async run(text, model) {
          if (active) throw new Fault(409, 'session_busy');
          active = true;
          fileScopes.clear(); fileScopeBytes = 0;
          turnId = undefined;
          const completion = new Promise((resolve, reject) => { completed = resolve; rejectCompletion = reject; });
          // Attach immediately: the process can close while turn/start is pending.
          completion.catch(() => {});
          startPending = rpc.request('turn/start', {
            threadId, input: [{ type: 'text', text, text_elements: [] }],
            ...(model && model !== 'default' ? { model } : {}),
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
  async open(session, sink) {
    const query = this.query;
    let nativeSession;
    let running;
    let controller;
    return {
      async run(text, model) {
        controller = new AbortController();
        running = query({ prompt: text, options: {
          cwd: session.directory, settingSources: [], permissionMode: 'default',
          env: childEnvironment(), abortController: controller,
          persistSession: true, includePartialMessages: true,
          ...(nativeSession ? { resume: nativeSession } : {}),
          ...(model && model !== 'default' ? { model } : {}),
          tools: ['Read', 'Glob', 'Grep', 'Bash', 'Edit', 'Write'],
          hooks: { PreToolUse: [{ hooks: [async (input) => ({ hookSpecificOutput: {
            hookEventName: 'PreToolUse',
            permissionDecision: await sink.permission(input.tool_name, input.tool_input) ? 'allow' : 'deny',
            permissionDecisionReason: 'Explicit Prompt user decision',
          } })] }] },
          canUseTool: async () => ({ behavior: 'deny', message: 'Tool was not approved by Prompt' }),
          stderr: () => {},
        } });
        let streamed = false;
        let successful = false;
        for await (const event of running) {
          if (event.type === 'system' && event.subtype === 'init') nativeSession = event.session_id;
          if (event.type === 'stream_event' && event.event?.delta?.type === 'text_delta') {
            streamed = true; sink.delta(event.event.delta.text);
          }
          if (!streamed && event.type === 'assistant') {
            for (const part of event.message?.content ?? []) if (part.type === 'text') sink.delta(part.text);
          }
          if (event.type === 'result') {
            if (event.is_error || event.subtype !== 'success') throw new Fault(502, 'agent_turn_failed');
            successful = true;
          }
        }
        if (!successful) throw new Fault(502, 'agent_incomplete');
      },
      async abort() { controller?.abort(); await running?.interrupt(); },
      close() { controller?.abort(); running?.close(); },
    };
  }
}
