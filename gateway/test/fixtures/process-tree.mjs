import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
const child = spawn(process.execPath, ['-e', "process.on('SIGTERM', () => {}); process.send('ready'); setInterval(() => {}, 1000);"], { stdio: ['ignore', 'ignore', 'ignore', 'ipc'] });
const ready = new Promise((resolve) => child.once('message', resolve));
createInterface({ input: process.stdin }).on('line', async (line) => {
  const request = JSON.parse(line);
  await ready;
  process.stdout.write(`${JSON.stringify({ id: request.id, result: { pid: child.pid } })}\n`);
});
process.on('SIGTERM', () => process.exit(0));
