import { createInterface } from 'node:readline';
const lines = createInterface({ input: process.stdin });
let initialized = false;
const send = (value) => process.stdout.write(`${JSON.stringify(value)}\n`);
lines.on('line', (line) => {
  const request = JSON.parse(line);
  if (request.method === 'initialize') send({ id: request.id, result: {} });
  else if (request.method === 'initialized') initialized = true;
  else if (request.method === 'thread/start') {
    // Codex 0.154.0's generated ThreadStartParams SandboxMode is kebab-case.
    if (!initialized || request.params.approvalPolicy !== 'untrusted' || request.params.sandbox !== 'workspace-write') process.exit(1);
    send({ id: request.id, result: { thread: { id: 'fixture-thread' } } });
  } else if (request.method === 'turn/start') {
    send({ id: request.id, result: { turn: { id: 'fixture-turn' } } });
    send({ method: 'item/agentMessage/delta', params: { delta: 'fixture response' } });
    send({ method: 'turn/completed', params: { turn: { id: 'fixture-turn', status: 'completed' } } });
  }
});
