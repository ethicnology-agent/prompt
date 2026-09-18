import { readFile, access } from 'node:fs/promises';
import { constants } from 'node:fs';
import { isAbsolute } from 'node:path';
import { pathToFileURL } from 'node:url';
import { resolveRoots, Fault } from './security.js';
import { CodexAdapter, ClaudeAdapter } from './adapters.js';
import { Sessions } from './sessions.js';
import { createGateway } from './server.js';
import { Worktrees } from './worktrees.js';

export async function configuredGateway(config, env = process.env) {
  const roots = await resolveRoots(config.roots);
  const worktrees = config.worktreeRoot || config.gitExecutable
    ? await Worktrees.configured({ gitExecutable: config.gitExecutable, worktreeRoot: config.worktreeRoot, roots })
    : undefined;
  const engines = {};
  if (config.codexExecutable) {
    if (!isAbsolute(config.codexExecutable)) throw new Fault(400, 'absolute_executable_required');
    await access(config.codexExecutable, constants.X_OK);
    engines.codex = new Sessions('codex', new CodexAdapter(config.codexExecutable), roots);
  }
  if (config.claudeSdkModule) {
    if (!isAbsolute(config.claudeSdkModule)) throw new Fault(400, 'absolute_sdk_module_required');
    const module = await import(pathToFileURL(config.claudeSdkModule).href);
    if (typeof module.query !== 'function') throw new Fault(400, 'invalid_sdk_module');
    engines.claude = new Sessions('claude', new ClaudeAdapter(module.query), roots);
  }
  return createGateway({ ...config, roots, engines, worktrees, token: env.PROMPT_GATEWAY_TOKEN,
    openCode: config.openCode ? { ...config.openCode, password: env.PROMPT_OPENCODE_PASSWORD } : undefined });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  let gateway;
  try {
    if (!process.argv[2]) throw new Fault(400, 'configuration_file_required');
    const config = JSON.parse(await readFile(process.argv[2], 'utf8'));
    gateway = await configuredGateway(config);
    await gateway.listen(config.port ?? 4097);
    // Generic lifecycle diagnostics only: never paths, addresses or credentials.
    process.stdout.write('Prompt private gateway is listening.\n');
    for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, async () => { await gateway.close(); process.exit(0); });
  } catch {
    if (gateway) await gateway.close();
    process.stderr.write('Prompt gateway could not start. Check the private configuration and installed engines.\n');
    process.exitCode = 1;
  }
}
