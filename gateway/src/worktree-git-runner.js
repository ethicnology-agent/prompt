// Own the process group until termination has reached all descendants.
import { spawn } from 'node:child_process';
let child;
let stopping = false;
function stop() {
  if (stopping) return;
  stopping = true;
  try { process.kill(-process.pid, 'SIGTERM'); } catch {}
  setTimeout(() => {
    try { process.kill(-process.pid, 'SIGKILL'); } catch { process.exit(1); }
  }, 100);
}
process.on('SIGTERM', stop);
process.on('disconnect', stop);
process.on('message', () => stop());
try {
  child = spawn(process.argv[2], process.argv.slice(3), {
    shell: false, stdio: ['ignore', 'inherit', 'ignore'], env: process.env,
  });
  child.once('error', () => {
    if (process.connected) process.send({ code: -1 });
    stop();
  });
  child.once('exit', (code) => {
    if (process.connected) process.send({ code });
    stop();
  });
} catch { stop(); }
