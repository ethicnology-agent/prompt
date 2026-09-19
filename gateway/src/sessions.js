import { randomUUID, createHash } from 'node:crypto';
import { EventEmitter } from 'node:events';
import { Fault, allowedDirectory } from './security.js';
import { approvalPresentation, approvalRestriction } from './approval-presentation.js';
import { validatePromptParts } from './image-input.js';
import { permissionOptions } from './model-catalog.js';

export class Sessions extends EventEmitter {
  constructor(engine, adapter, roots, { maxSessions = 32, maxMessages = 1000, maxOutput = 2 * 1024 * 1024, turnTimeout = 30 * 60 * 1000, approvalTimeout = 5 * 60 * 1000 } = {}) {
    super();
    Object.assign(this, { engine, adapter, roots, maxSessions, maxMessages, maxOutput, turnTimeout, approvalTimeout });
    this.sessions = new Map();
    this.permissions = new Map();
  }
  emitEvent(session, type, properties) {
    this.emit('event', { directory: session.directory, payload: { type, properties } });
  }
  status(session, type) {
    session.status = type;
    this.emitEvent(session, 'session.status', { sessionID: session.id, status: { type } });
    if (type === 'idle') this.emitEvent(session, 'session.idle', { sessionID: session.id });
  }
  get(id) {
    const session = this.sessions.get(id);
    if (!session) throw new Fault(404, 'session_not_found');
    return session;
  }
  record(session) {
    return { id: session.id, projectID: session.projectID, directory: session.directory, title: session.title, time: session.time };
  }
  projectId(directory) {
    const rootIndex = this.roots.indexOf(directory);
    return rootIndex >= 0 ? `root_${rootIndex}` : `workspace_${createHash('sha256').update(directory).digest('hex').slice(0, 24)}`;
  }
  projects() {
    const directories = new Set([...this.roots, ...[...this.sessions.values()].map((session) => session.directory)]);
    return [...directories].map((worktree) => ({ id: this.projectId(worktree), worktree }));
  }
  async create(directory, title) {
    if (this.sessions.size >= this.maxSessions) throw new Fault(429, 'session_limit');
    directory = await allowedDirectory(directory, this.roots);
    if (title !== undefined && (typeof title !== 'string' || title.length > 256)) throw new Fault(400, 'invalid_title');
    const now = Date.now();
    const session = { id: `${this.engine}_${randomUUID()}`, projectID: this.projectId(directory), directory, title: title || 'New session', time: { created: now, updated: now }, messages: [], accepted: new Map(), status: 'idle', runner: null, active: false, outputBytes: 0, imageBytes: 0 };
    this.sessions.set(session.id, session);
    return this.record(session);
  }
  message(session, role, text, id = randomUUID(), parts = [{ type: 'text', text }]) {
    const record = { info: { id, role, sessionID: session.id, time: { created: Date.now() } }, parts: parts.map((part) => ({ ...part, id: randomUUID(), sessionID: session.id, messageID: id })) };
    session.messages.push(record);
    this.emitEvent(session, 'message.updated', { info: record.info });
    for (const part of record.parts) this.emitEvent(session, 'message.part.updated', { part });
    return record;
  }
  submit(session, body, catalog) {
    if (typeof body.messageID === 'string' && session.accepted.has(body.messageID)) {
      const fingerprint = createHash('sha256').update(JSON.stringify(body)).digest('hex');
      if (session.accepted.get(body.messageID) !== fingerprint) throw new Fault(409, 'message_id_conflict');
      return;
    }
    const advertisedPermissions = permissionOptions(this.engine);
    const permissionMode = body.permissionMode ?? advertisedPermissions?.defaultPermissionModeId;
    if (body.permissionMode !== undefined &&
        (typeof body.permissionMode !== 'string' ||
          !advertisedPermissions?.permissionModes.some((choice) => choice.id === body.permissionMode))) {
      throw new Fault(400, 'unsupported_permission_mode');
    }
    if (body.reasoningEffort !== undefined) {
      if (typeof body.reasoningEffort !== 'string' || !body.reasoningEffort.length || body.reasoningEffort.length > 128 || /[\x00-\x1f\x7f]/.test(body.reasoningEffort)) throw new Fault(400, 'invalid_reasoning_effort');
      if (!catalog || !body.model || body.model.providerID !== this.engine || body.model.modelID === 'default') throw new Fault(400, 'effort_requires_available_model');
      return catalog.read().then((value) => {
        const model = value.models.find((entry) => entry.id === body.model.modelID);
        if (value.status !== 'ready' || !model?.executionOptions?.reasoningEfforts.some((choice) => choice.id === body.reasoningEffort) || (this.engine === 'codex' && !model.executionOptions.defaultReasoningEffortId)) throw new Fault(400, 'unsupported_reasoning_effort');
        this._submit(session, body, { reasoningEffort: body.reasoningEffort, permissionMode });
      });
    }
    const selectedModel = body.model?.modelID ?? session.selectedModel;
    const defaultEffort = catalog?.cached?.models.find((entry) => entry.id === selectedModel)?.executionOptions?.defaultReasoningEffortId;
    if (session.effortWasSet && this.engine === 'codex' && selectedModel && selectedModel !== 'default' && !defaultEffort) throw new Fault(400, 'effort_default_unavailable');
    return this._submit(session, body, { resetEffort: session.effortWasSet === true, defaultEffort, permissionMode });
  }
  _submit(session, body, execution) {
    const fingerprint = createHash('sha256').update(JSON.stringify(body)).digest('hex');
    if (typeof body.messageID === 'string' && session.accepted.has(body.messageID)) {
      if (session.accepted.get(body.messageID) !== fingerprint) throw new Fault(409, 'message_id_conflict');
      return;
    }
    if (session.broken) throw new Fault(409, 'session_failed_create_new');
    if (session.active) throw new Fault(409, 'session_busy');
    if (session.messages.length + 2 > this.maxMessages) throw new Fault(429, 'history_limit');
    const input = validatePromptParts(body.parts);
    if (Object.keys(body).some((key) => !['parts', 'model', 'agent', 'messageID', 'reasoningEffort', 'permissionMode'].includes(key))) throw new Fault(400, 'unsupported_prompt_option');
    if (body.agent && body.agent !== this.engine) throw new Fault(400, 'unsupported_agent');
    if (body.model && (body.model.providerID !== this.engine || typeof body.model.modelID !== 'string' || body.model.modelID.length > 128)) throw new Fault(400, 'invalid_model');
    if (body.messageID !== undefined && (typeof body.messageID !== 'string' || body.messageID.length > 128)) throw new Fault(400, 'invalid_message_id');
    const { text, images } = input;
    if (session.outputBytes + Buffer.byteLength(text) > this.maxOutput || session.imageBytes + input.imageBytes > 25 * 1024 * 1024) throw new Fault(413, 'history_limit');
    session.outputBytes += Buffer.byteLength(text);
    session.imageBytes += input.imageBytes;
    session.active = true;
    session.effortWasSet ||= execution.reasoningEffort !== undefined;
    session.selectedModel = body.model?.modelID ?? session.selectedModel;
    if (body.messageID) session.accepted.set(body.messageID, fingerprint);
    session.time.updated = Date.now();
    this.message(session, 'user', text, body.messageID, input.parts);
    session.assistant = this.message(session, 'assistant', '');
    this.status(session, 'busy');
    session.task = this.run(session, text, body.model?.modelID, images, execution);
  }
  async run(session, text, model, images = [], execution = {}) {
    let deadline;
    try {
      const timeout = new Promise((_, reject) => { deadline = setTimeout(() => { session.runner?.close(); reject(new Fault(504, 'turn_timeout')); }, this.turnTimeout); });
      await Promise.race([(async () => {
        session.runner ??= await this.adapter.open(session, {
          delta: (text) => this.delta(session, text),
          permission: (tool, input) => this.permission(session, tool, input),
        });
        if (!session.active) { session.runner.close(); return; }
        await session.runner.run(text, model, images, execution);
      })(), timeout]);
      session.assistant.info.time.completed = Date.now();
    } catch {
      session.broken = true;
      session.assistant.info.error = { name: 'AgentError', data: { message: 'The agent did not complete this turn. Check its local setup before trying again.' } };
      if (!session.assistant.parts[0].text) {
        session.assistant.parts[0].text = 'The agent could not complete this turn. Check its local setup and create a new session; queued prompts were not sent.';
        this.emitEvent(session, 'message.part.updated', { part: session.assistant.parts[0] });
      }
      session.runner?.close();
      session.runner = null;
    } finally {
      clearTimeout(deadline);
      for (const [id, permission] of this.permissions) if (permission.record.sessionID === session.id) this.reply(id, 'reject');
      this.emitEvent(session, 'message.updated', { info: session.assistant.info });
      session.active = false;
      // The existing client treats unknown execution states as unsynchronized.
      // Never emit idle for a lost context: that could dispatch queued work.
      this.status(session, session.broken ? 'error' : 'idle');
    }
  }
  delta(session, text) {
    if (!session.active || typeof text !== 'string') return;
    session.outputBytes += Buffer.byteLength(text);
    if (session.outputBytes > this.maxOutput) { session.runner?.close(); throw new Fault(413, 'output_limit'); }
    const part = session.assistant.parts[0];
    part.text += text;
    this.emitEvent(session, 'message.part.updated', { part });
  }
  permission(session, tool, input) {
    if (!session.active || this.permissions.size >= 32) return Promise.resolve(false);
    const metadata = JSON.stringify(input ?? {});
    if (Buffer.byteLength(metadata) > 64 * 1024) return Promise.resolve(false);
    const presentation = approvalPresentation(tool, input);
    const restriction = approvalRestriction(tool, input);
    if (restriction) {
      this.delta(session, `\n\n${restriction}\n\n${presentation.title}\n`);
      return Promise.resolve(false);
    }
    const record = { id: randomUUID(), sessionID: session.id, type: presentation.type, permission: tool, title: presentation.title, pattern: [], metadata: input ?? {}, time: { created: Date.now() } };
    return new Promise((resolve) => {
      const timer = setTimeout(() => this.reply(record.id, 'reject'), this.approvalTimeout);
      this.permissions.set(record.id, { record, session, resolve, timer });
      this.emitEvent(session, 'permission.updated', record);
    });
  }
  reply(id, response, sessionId) {
    const pending = this.permissions.get(id);
    if (!pending || (sessionId && pending.record.sessionID !== sessionId)) throw new Fault(404, 'permission_not_found');
    // Persistent/session-wide approval is intentionally not available.
    if (!['once', 'reject'].includes(response)) throw new Fault(400, 'one_time_approval_required');
    clearTimeout(pending.timer);
    this.permissions.delete(id);
    this.emitEvent(pending.session, 'permission.replied', { sessionID: pending.record.sessionID, requestID: id, response });
    pending.resolve(response === 'once');
    return true;
  }
  async abort(session) {
    if (!session.active) return true;
    for (const [id, pending] of this.permissions) if (pending.record.sessionID === session.id) this.reply(id, 'reject');
    if (!session.runner) throw new Fault(409, 'agent_starting');
    await session.runner.abort();
    // Only run completion emits idle; requesting cancellation is not completion.
    return true;
  }
  close() {
    for (const id of this.permissions.keys()) this.reply(id, 'reject');
    for (const session of this.sessions.values()) session.runner?.close();
    this.removeAllListeners();
  }
}
