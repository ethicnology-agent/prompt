// A process-group leader that outlives the agent during shutdown. Keeping the
// leader alive reserves its PGID until escalation, avoiding PID-reuse races.
import { spawn } from 'node:child_process';

let stopping = false;
let agent;
function stop() {
  if (stopping) return;
  stopping = true;
  if (process.platform === 'win32') {
    agent?.kill('SIGTERM');
    setTimeout(() => { agent?.kill('SIGKILL'); process.exit(0); }, 2000);
    return;
  }
  // This handler deliberately survives its own group SIGTERM. The timer is
  // referenced, even if the agent exits and all stdio streams have closed.
  try { process.kill(-process.pid, 'SIGTERM'); } catch {}
  setTimeout(() => {
    try { process.kill(-process.pid, 'SIGKILL'); } catch { process.exit(1); }
  }, 2000);
}
process.on('SIGTERM', stop);
process.on('SIGINT', stop);
process.on('disconnect', stop);
process.on('message', (message) => { if (message?.type === 'stop') stop(); });
try {
  agent = spawn(process.argv[2], process.argv.slice(3), {
    shell: false, detached: false, stdio: ['inherit', 'inherit', 'ignore'],
    env: process.env,
  });
  agent.once('error', stop);
  agent.once('exit', () => {
    if (process.connected) process.send({ type: 'agentExit' });
    stop();
  });
} catch { stop(); }
