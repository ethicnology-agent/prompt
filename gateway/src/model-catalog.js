const identifier = (value) => typeof value === 'string' && value.length > 0 && value.length <= 128 && !/[\x00-\x1f\x7f]/.test(value);

const codexPermissionChoices = Object.freeze([
  Object.freeze({ id: 'ask', label: 'Auto', description: 'Ask when unsure; writes stay inside the workspace.' }),
  Object.freeze({ id: 'auto', label: 'Workspace', description: 'Sandboxed workspace access that can request escalation.' }),
  Object.freeze({ id: 'read', label: 'Read', description: 'No filesystem writes or approval escalation.' }),
]);

const claudePermissionChoices = Object.freeze([
  Object.freeze({ id: 'ask', label: 'Auto', description: 'Ask before uncertain tool use.' }),
  Object.freeze({ id: 'plan', label: 'Plan', description: 'Plan without executing tools or changing files.' }),
]);

/// Returns only policies the private gateway can enforce end to end.
export function permissionOptions(engine) {
  const permissionModes = engine === 'codex'
    ? codexPermissionChoices
    : engine === 'claude'
      ? claudePermissionChoices
      : undefined;
  if (!permissionModes) return undefined;
  return {
    version: 1,
    permissionModes,
    defaultPermissionModeId: 'ask',
  };
}

export function codexExecutionPolicy(mode) {
  if (mode === 'auto') {
    return { approvalPolicy: 'on-request', sandboxPolicy: { type: 'workspaceWrite' } };
  }
  if (mode === 'read') {
    return { approvalPolicy: 'never', sandboxPolicy: { type: 'readOnly' } };
  }
  return { approvalPolicy: 'untrusted', sandboxPolicy: { type: 'workspaceWrite' } };
}

export function executionOptions(value) {
  if (!value || value.version !== 1 || !Array.isArray(value.reasoningEfforts) || value.reasoningEfforts.length > 32) return undefined;
  const choices = new Map();
  for (const choice of value.reasoningEfforts) {
    if (!choice || !identifier(choice.id)) continue;
    const description = typeof choice.description === 'string' && choice.description.length <= 512 && !/[\x00-\x1f\x7f]/.test(choice.description) ? choice.description : undefined;
    choices.set(choice.id, { id: choice.id, label: choice.id, ...(description ? { description } : {}) });
  }
  if (!choices.size) return undefined;
  const defaultId = value.defaultReasoningEffortId;
  return { version: 1, reasoningEfforts: [...choices.values()], ...(choices.has(defaultId) ? { defaultReasoningEffortId: defaultId } : {}) };
}

// Cancellation rejects even when a native SDK promise fails to settle. Native
// adapters close their owned process in finally; no prompts are submitted.
export async function abortable(operation, signal) {
  if (signal.aborted) throw new Error('catalog_cancelled');
  let cancel;
  const interrupted = new Promise((_, reject) => {
    cancel = () => reject(new Error('catalog_cancelled'));
    signal.addEventListener('abort', cancel, { once: true });
  });
  try { return await Promise.race([Promise.resolve().then(operation), interrupted]); }
  finally { signal.removeEventListener('abort', cancel); }
}

export class NativeModelCatalog {
  constructor(adapter, directory, { timeoutMs = 5000, ttlMs = 300000, failureTtlMs = 30000, now = Date.now } = {}) {
    Object.assign(this, { adapter, directory, timeoutMs, ttlMs, failureTtlMs, now });
    this.closed = false;
  }
  async read() {
    if (this.closed) return { status: 'unavailable', models: [] };
    if (this.cached && this.now() < this.expires) return this.cached;
    if (this.pending) return this.pending;
    this.controller = new AbortController();
    const controller = this.controller;
    this.pending = (async () => {
      const timer = setTimeout(() => controller.abort(), this.timeoutMs);
      let result;
      try {
        const discovered = await abortable(() => this.adapter.discoverModels(this.directory, { signal: controller.signal }), controller.signal);
        if (!Array.isArray(discovered) || discovered.length > 256) throw new Error('invalid_catalog');
        const models = new Map();
        for (const entry of discovered) {
          if (!entry || !identifier(entry.id) || typeof entry.name !== 'string' || !entry.name.trim() || entry.name.length > 256 || /[\x00-\x1f\x7f]/.test(entry.name)) continue;
          const options = executionOptions(entry.executionOptions);
          models.set(entry.id, { id: entry.id, name: entry.name, ...(options ? { executionOptions: options } : {}) });
        }
        if (!models.size) throw new Error('empty_catalog');
        result = { status: 'ready', models: [...models.values()] };
      } catch {
        // Never expose native errors: they may include account or machine data.
        result = { status: 'unavailable', models: [] };
      } finally {
        clearTimeout(timer);
      }
      this.cached = result;
      this.expires = this.now() + (result.status === 'ready' ? this.ttlMs : this.failureTtlMs);
      return result;
    })().finally(() => { this.pending = undefined; this.controller = undefined; });
    return this.pending;
  }
  close() { this.closed = true; this.controller?.abort(); }
}

export function providerCatalog(engine, catalog) {
  const models = Object.fromEntries([
    ['default', { id: 'default', name: catalog.status === 'ready' ? 'CLI default' : 'CLI default (catalog unavailable)' }],
    ...catalog.models.map((model) => [model.id, model]),
  ]);
  const options = permissionOptions(engine);
  return { all: [{ id: engine, name: engine, models, ...(options ? { executionOptions: options } : {}) }], connected: [engine], default: { [engine]: 'default' }, catalog: { status: catalog.status } };
}
