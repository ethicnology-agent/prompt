// Human-readable native approval summaries. The complete original request
// remains in permission.metadata; nothing here grants or changes permission.
export function approvalRestriction(tool, input) {
  if (!['item/commandExecution/requestApproval', 'item/fileChange/requestApproval'].includes(tool)) return null;
  if (input?.grantRoot != null) return 'Denied: this request may grant write access for the remainder of the session. Prompt only supports one-time approval; session-scoped grants are unavailable.';
  if (input && Object.hasOwn(input, 'availableDecisions') && (!Array.isArray(input.availableDecisions) || !input.availableDecisions.includes('accept'))) return 'Denied: the agent did not offer a one-time accept decision. Broader approval is unavailable in Prompt.';
  return null;
}

export function denialDecision(input) {
  if (!input || !Object.hasOwn(input, 'availableDecisions')) return 'decline';
  if (!Array.isArray(input.availableDecisions)) return null;
  if (input.availableDecisions.includes('decline')) return 'decline';
  if (input.availableDecisions.includes('cancel')) return 'cancel';
  return null;
}

export function approvalPresentation(tool, input) {
  const codexCommandRequest = tool === 'item/commandExecution/requestApproval';
  const commandRequest = codexCommandRequest || tool === 'Bash';
  const fileRequest = tool === 'item/fileChange/requestApproval';
  if ((!commandRequest && !fileRequest) || !input || typeof input !== 'object' || Array.isArray(input)) {
    return { type: tool, title: `${tool}\n${JSON.stringify(input ?? {})}` };
  }

  const hasCommand = typeof input.command === 'string' && input.command.length > 0;
  const networkOnly = commandRequest && !hasCommand && input.networkApprovalContext && typeof input.networkApprovalContext === 'object';
  const sections = [networkOnly ? 'Allow network access' : commandRequest ? (hasCommand ? 'Run command' : 'Approve command execution') : 'Allow file changes'];
  const displayed = new Set();
  const add = (key, label) => {
    if (typeof input[key] === 'string' && input[key].length > 0) {
      sections.push(label ? `${label}: ${input[key]}` : input[key]);
      displayed.add(key);
    }
  };
  if (commandRequest) {
    add('command');
    if (!hasCommand && !networkOnly) sections.push('The agent did not provide a command. Review the request details before approving.');
    add('cwd', 'Working directory');
  } else {
    add('cwd', 'Working directory');
    add('grantRoot', 'Requested root');
  }
  add('reason', 'Reason');
  if (tool === 'Bash') add('description', 'Description');

  // IDs route the reply; they are not the action the person is approving.
  const routing = new Set(codexCommandRequest || fileRequest ? ['threadId', 'turnId', 'itemId', 'approvalId', 'environmentId', 'availableDecisions'] : []);
  for (const [key, value] of Object.entries(input)) {
    if (value == null || displayed.has(key) || routing.has(key)) continue;
    // Parsed command classifications duplicate the exact command, but are the
    // only available action evidence if a protocol version omits that command.
    if (key === 'commandActions' && hasCommand && codexCommandRequest) continue;
    // Preserve additional/network permissions, policy amendments and unfamiliar
    // future fields. A prettier card must not conceal an expanded grant.
    sections.push(`${key}:\n${JSON.stringify(value, null, 2)}`);
  }
  return { type: networkOnly ? 'network' : commandRequest ? 'bash' : 'edit', title: sections.join('\n\n') };
}
