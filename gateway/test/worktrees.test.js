import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, rm, writeFile, access, chmod } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { Worktrees, worktreeEnvironment } from '../src/worktrees.js';
import { resolveRoots } from '../src/security.js';
import { createGateway } from '../src/server.js';

const execute = promisify(execFile);
const executable = '/usr/bin/git';
const token = 'synthetic-worktrees-test-secret-long-enough';
const auth = `Basic ${Buffer.from(`prompt:${token}`).toString('base64')}`;

async function fixture(t) {
  const scratch = await mkdtemp(join(tmpdir(), 'prompt-worktrees-'));
  const repository = join(scratch, 'repository');
  const destination = join(scratch, 'worktrees');
  await mkdir(repository); await mkdir(destination);
  const git = (...args) => execute(executable, args, { cwd: repository, env: worktreeEnvironment, timeout: 10000 });
  await git('init', '--initial-branch=main');
  // A synthetic immutable empty tree/commit, never a commit in a user's repo.
  const treeFile = join(scratch, 'tree');
  await writeFile(treeFile, '');
  const tree = (await git('hash-object', '-t', 'tree', '-w', treeFile)).stdout.trim();
  const commitFile = join(scratch, 'commit');
  await writeFile(commitFile, `tree ${tree}\nauthor Fixture <fixture@example.invalid> 1 +0000\ncommitter Fixture <fixture@example.invalid> 1 +0000\n\nFixture\n`);
  const commit = (await git('hash-object', '-t', 'commit', '-w', commitFile)).stdout.trim();
  await git('update-ref', 'refs/heads/main', commit);
  const roots = await resolveRoots([repository, destination]);
  const service = await Worktrees.configured({ gitExecutable: executable, worktreeRoot: destination, roots });
  t.after(async () => { service.close(); await rm(scratch, { recursive: true, force: true }); });
  return { service, roots, repository: roots[0], destination: roots[1], git, scratch };
}

test('real isolated git creates a new worktree and leaves source branch unchanged', async (t) => {
  const f = await fixture(t);
  const marker = join(f.scratch, 'unexpected-hook');
  const hook = join(f.repository, '.git', 'hooks', 'post-checkout');
  await writeFile(hook, `#!/bin/sh\ntouch '${marker}'\n`);
  await chmod(hook, 0o700);
  const before = await f.service.list(f.repository);
  assert.equal(before.worktrees.length, 1);
  const created = await f.service.create({ directory: f.repository, name: 'task' });
  assert.ok(created.directory.startsWith(`${f.destination}/task-`));
  assert.match(created.branch, /^refs\/heads\/prompt\/[a-f0-9-]+$/);
  assert.equal((await f.git('branch', '--show-current')).stdout.trim(), 'main');
  assert.equal((await f.service.list(f.repository)).worktrees.length, 2);
  await access(join(created.directory, '.git'));
  await assert.rejects(access(marker), { code: 'ENOENT' });
});

test('fail closed for nongit, arbitrary destinations and configured filters', async (t) => {
  const f = await fixture(t);
  await assert.rejects(f.service.list(f.destination), { code: 'not_git_repository' });
  await assert.rejects(f.service.list(f.scratch), { code: 'directory_not_allowed' });
  await assert.rejects(f.service.create({ directory: f.repository, name: '../escape' }), { code: 'invalid_worktree_name' });
  await f.git('config', 'filter.fixture.smudge', 'do-not-execute');
  await assert.rejects(f.service.create({ directory: f.repository, name: 'safe' }), { code: 'unsafe_repository_configuration' });
  assert.equal((await f.service.list(f.repository)).worktrees.length, 1);
});

test('machine routes are authenticated and require explicit opt-in', async (t) => {
  const f = await fixture(t);
  const gateway = createGateway({ token, roots: f.roots, engines: {}, worktrees: f.service });
  const address = await gateway.listen(0);
  t.after(() => gateway.close());
  const base = `http://127.0.0.1:${address.port}`;
  assert.equal((await fetch(`${base}/prompt/worktrees`)).status, 401);
  const headers = { authorization: auth, 'content-type': 'application/json' };
  const capabilities = await (await fetch(`${base}/prompt/capabilities`, { headers })).json();
  assert.equal(capabilities.machine.worktrees, true);
  const list = await fetch(`${base}/prompt/worktrees?directory=${encodeURIComponent(f.repository)}`, { headers });
  assert.equal(list.status, 200);
  const denied = await fetch(`${base}/prompt/worktrees`, { method: 'POST', headers, body: JSON.stringify({ directory: f.repository, name: 'task', destination: '/untrusted' }) });
  assert.equal(denied.status, 400);
  const create = await fetch(`${base}/prompt/worktrees`, { method: 'POST', headers, body: JSON.stringify({ directory: f.repository, name: 'task' }) });
  assert.equal(create.status, 201);
});

test('worktree destination must be explicitly allowlisted; no inherited environment', async (t) => {
  const f = await fixture(t);
  await assert.rejects(Worktrees.configured({ gitExecutable: executable, worktreeRoot: f.destination, roots: [f.repository] }), { code: 'worktree_root_not_allowlisted' });
  assert.equal(worktreeEnvironment.HOME, undefined);
  assert.equal(worktreeEnvironment.GIT_CONFIG_GLOBAL, '/dev/null');
  assert.equal(worktreeEnvironment.GIT_NO_LAZY_FETCH, '1');
  assert.equal(worktreeEnvironment.NODE_OPTIONS, undefined);
});
