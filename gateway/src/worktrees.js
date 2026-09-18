import { spawn } from 'node:child_process';
import { access, realpath, lstat } from 'node:fs/promises';
import { constants } from 'node:fs';
import { isAbsolute, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { Fault, allowedDirectory } from './security.js';

const gitOptions = ['-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false',
  '-c', 'submodule.recurse=false', '-c', 'protocol.allow=never',
  '-c', 'maintenance.auto=false', '-c', 'gc.auto=0'];
export const worktreeEnvironment = Object.freeze({
  PATH: '/usr/bin:/bin', LANG: 'C', LC_ALL: 'C',
  GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_SYSTEM: '/dev/null',
  GIT_CONFIG_GLOBAL: '/dev/null', GIT_TERMINAL_PROMPT: '0',
  GIT_NO_LAZY_FETCH: '1', GIT_OPTIONAL_LOCKS: '0',
});

export class Worktrees {
  static async configured({ gitExecutable, worktreeRoot, roots }) {
    if (process.platform === 'win32' || !isAbsolute(gitExecutable ?? '') || !isAbsolute(worktreeRoot ?? '')) throw new Fault(400, 'invalid_worktree_configuration');
    await access(gitExecutable, constants.X_OK);
    const destination = await realpath(worktreeRoot);
    // Operator must explicitly include the dedicated destination, not merely
    // its parent, in the agent/session allowlist.
    if (!roots.includes(destination) || (await lstat(worktreeRoot)).isSymbolicLink()) throw new Fault(400, 'worktree_root_not_allowlisted');
    await allowedDirectory(destination, roots);
    return new Worktrees(gitExecutable, destination, roots);
  }
  constructor(executable, destination, roots) {
    this.executable = executable; this.destination = destination; this.roots = roots;
    this.busy = new Set(); this.children = new Set(); this.closed = false;
  }
  run(directory, args, allowExit = false) {
    if (this.closed) throw new Fault(503, 'worktrees_unavailable');
    return new Promise((resolve, reject) => {
      const child = spawn(process.execPath, [fileURLToPath(new URL('./worktree-git-runner.js', import.meta.url)), this.executable, ...gitOptions, ...args], {
        cwd: directory, env: worktreeEnvironment, detached: true,
        shell: false, stdio: ['ignore', 'pipe', 'ignore', 'ipc'],
      });
      this.children.add(child);
      let output = ''; let code = null; let fault;
      const stop = () => { if (child.connected) child.send({}, () => {}); };
      const timer = setTimeout(() => { fault = new Fault(504, 'worktree_operation_uncertain'); stop(); }, 10000);
      child.stdout.setEncoding('utf8');
      child.stdout.on('data', (chunk) => {
        if (fault) return;
        output += chunk;
        if (Buffer.byteLength(output) > 1024 * 1024) { fault = new Fault(413, 'worktree_output_limit'); output = ''; stop(); }
      });
      child.on('message', (value) => { code = value.code; });
      child.once('error', () => { fault = new Fault(503, 'git_unavailable'); });
      child.once('close', () => {
        clearTimeout(timer); this.children.delete(child);
        if (fault) reject(fault);
        else if (code !== 0 && !allowExit) reject(new Fault(409, 'worktree_operation_failed'));
        else resolve({ code, output });
      });
    });
  }
  async repository(directory) {
    const allowed = await allowedDirectory(directory, this.roots);
    const top = await this.run(allowed, ['rev-parse', '--show-toplevel'], true);
    if (top.code !== 0) throw new Fault(422, 'not_git_repository');
    const root = await allowedDirectory(top.output.trim(), this.roots);
    const common = await this.run(root, ['rev-parse', '--path-format=absolute', '--git-common-dir']);
    await allowedDirectory(common.output.trim(), this.roots);
    return root;
  }
  async list(directory) {
    const root = await this.repository(directory);
    const { output } = await this.run(root, ['worktree', 'list', '--porcelain', '-z']);
    const worktrees = [];
    for (const record of output.split('\0\0')) {
      const fields = record.split('\0');
      const path = fields.find((field) => field.startsWith('worktree '))?.slice(9);
      if (!path) continue;
      let resolved;
      try { resolved = await allowedDirectory(path, this.roots); } catch { continue; }
      worktrees.push({ directory: resolved, branch: fields.find((field) => field.startsWith('branch '))?.slice(7) ?? null,
        detached: fields.includes('detached'), locked: fields.some((field) => field === 'locked' || field.startsWith('locked ')) });
    }
    return { directory: root, worktrees, canCreate: true };
  }
  async create({ directory, name }) {
    if (typeof name !== 'string' || !/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$/.test(name)) throw new Fault(400, 'invalid_worktree_name');
    const root = await this.repository(directory);
    const common = await this.run(root, ['rev-parse', '--path-format=absolute', '--git-common-dir']);
    const lock = await allowedDirectory(common.output.trim(), this.roots);
    if (this.busy.has(lock)) throw new Fault(409, 'worktree_busy');
    this.busy.add(lock);
    try {
      const { output } = await this.run(root, ['config', '--null', '--list']);
      const keys = output.split('\0').map((entry) => entry.split('\n')[0].toLowerCase());
      if (keys.some((key) => key.startsWith('filter.') || key === 'extensions.partialclone' || /^remote\..*\.promisor$/.test(key))) throw new Fault(422, 'unsafe_repository_configuration');
      if (await realpath(this.destination) !== this.destination) throw new Fault(403, 'worktree_root_changed');
      const id = randomUUID();
      const path = join(this.destination, `${name}-${id}`);
      const branch = `prompt/${id}`;
      await this.run(root, ['worktree', 'add', '-b', branch, '--', path, 'HEAD']);
      const resolved = await allowedDirectory(path, this.roots);
      return { directory: resolved, branch: `refs/heads/${branch}`, detached: false, locked: false };
    } finally { this.busy.delete(lock); }
  }
  close() {
    this.closed = true;
    for (const child of this.children) if (child.connected) child.send({}, () => {});
  }
}
