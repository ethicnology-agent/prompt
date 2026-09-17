import { spawn } from 'node:child_process';
import { EventEmitter } from 'node:events';
import { fileURLToPath } from 'node:url';
import { Fault } from './security.js';

// Provider credentials remain in the CLI's own credential store. Never forward
// arbitrary gateway environment variables, tokens, or Node preload options.
export function childEnvironment(source = process.env) {
  return Object.fromEntries(['PATH', 'HOME', 'USER', 'TMPDIR', 'LANG', 'LC_ALL',
    'SYSTEMROOT', 'SSL_CERT_FILE', 'SSL_CERT_DIR'].filter((key) => source[key])
    .map((key) => [key, source[key]]));
}

export class JsonProcess extends EventEmitter {
  constructor(executable, args, cwd, launch = spawn) {
    super();
    this.pending = new Map();
    this.counter = 0;
    this.closed = false;
    this.buffer = '';
    this.child = launch(process.execPath, [fileURLToPath(new URL('./process-supervisor.js', import.meta.url)), executable, ...args], { cwd, env: childEnvironment(), shell: false, detached: process.platform !== 'win32', stdio: ['pipe', 'pipe', 'ignore', 'ipc'] });
    this.child.on('message', (message) => { if (message?.type === 'agentExit') this.close(); });
    this.child.stdin.on('error', () => this.close());
    this.child.stdout.setEncoding('utf8');
    this.child.stdout.on('data', (chunk) => {
      this.buffer += chunk;
      if (Buffer.byteLength(this.buffer) > 2 * 1024 * 1024) return this.close();
      let end;
      while ((end = this.buffer.indexOf('\n')) >= 0) {
        const line = this.buffer.slice(0, end);
        this.buffer = this.buffer.slice(end + 1);
        if (!line.trim()) continue;
        let value;
        try { value = JSON.parse(line); } catch { this.close(); return; }
        if (value.id !== undefined && !value.method) {
          const pending = this.pending.get(value.id);
          if (!pending) continue;
          this.pending.delete(value.id);
          clearTimeout(pending.timer);
          if (value.error) pending.reject(new Fault(502, 'agent_request_failed'));
          else pending.resolve(value.result);
        } else {
          try { this.emit('message', value); } catch { this.close(); return; }
        }
      }
    });
    this.child.once('error', () => this.close());
    this.child.once('exit', () => this.close());
  }
  write(value) {
    if (this.closed || this.child.stdin.writableLength > 1024 * 1024) throw new Fault(502, 'agent_disconnected');
    this.child.stdin.write(`${JSON.stringify(value)}\n`);
  }
  request(method, params, timeout = 15000) {
    if (this.closed) return Promise.reject(new Fault(502, 'agent_disconnected'));
    return new Promise((resolve, reject) => {
      const id = ++this.counter;
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Fault(504, 'agent_timeout'));
        this.close();
      }, timeout);
      this.pending.set(id, { resolve, reject, timer });
      try { this.write({ id, method, params }); } catch (error) {
        clearTimeout(timer); this.pending.delete(id); reject(error);
      }
    });
  }
  close() {
    if (this.closed) return;
    this.closed = true;
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(new Fault(502, 'agent_disconnected'));
    }
    this.pending.clear();
    // IPC targets this exact process, not a potentially reused numeric PID.
    // The supervisor terminates its own group after its grace period and does
    // not exit when the wrapped agent leader exits first.
    if (this.child.connected) this.child.send({ type: 'stop' }, () => {});
    this.emit('closed');
    this.removeAllListeners();
  }
}
