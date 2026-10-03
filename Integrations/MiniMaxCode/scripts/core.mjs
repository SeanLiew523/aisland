import net from 'node:net';
import { isAbsolute } from 'node:path';

const cleanText = (value, limit, required = true) => typeof value === 'string' && (!required || value.trim().length > 0)
  && Buffer.byteLength(value) <= limit && !/[\x00-\x1f\x7f-\x9f]/.test(value);
const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);
export function validConfig(config) {
  return record(config) && config.schemaVersion === 1
    && ['minimaxCodeDesktop', 'minimaxCodeCLI'].includes(config.source)
    && config.sourceRuntimeVersion === (config.source === 'minimaxCodeDesktop' ? '3.1.0' : '0.5.3')
    && cleanText(config.profileID, 1024) && cleanText(config.bridgeSocketPath, 4096) && isAbsolute(config.bridgeSocketPath)
    && cleanText(config.metadataDatabasePath, 4096) && isAbsolute(config.metadataDatabasePath)
    && Number.isInteger(config.bridgeTimeoutMs) && config.bridgeTimeoutMs >= 10 && config.bridgeTimeoutMs <= 300;
}

// Hooks are admission observations only. The native ingress metadata reader
// resolves accepted/final status. Stop remains nonterminal; other hooks can continue it.
// SessionEnd means session release/archive, never successful turn completion.
export function projectHook(input, config, timestamp = Date.now()) {
  if (!validConfig(config) || !record(input) || !cleanText(input.session_id, 512)
      || !cleanText(input.cwd, 4096, false) || !Number.isSafeInteger(timestamp) || timestamp < 0) return null;
  let event;
  if (['SessionStart', 'UserPromptSubmit', 'Stop'].includes(input.hook_event_name)) event = 'sessionObserved';
  else if (input.hook_event_name === 'SessionEnd') event = 'sessionEnded';
  else return null;
  const hook = { source: config.source, event, profile_id: config.profileID, session_id: input.session_id,
    cwd: input.cwd, timestamp, metadata_database_path: config.metadataDatabasePath,
    ...(cleanText(input.turn_id, 512) ? { turn_id: input.turn_id } : {}),
    ...(config.source === 'minimaxCodeDesktop' ? { app_bundle_id: 'com.minimax.agent',
      app_conversation_id: input.session_id, terminal_app: 'MiniMax Code.app' } : {}) };
  return { type: 'command', command: { type: 'processRuntimeLifecycleHook', runtimeLifecycleHook: hook } };
}

// No retries, retained queue, subprocess, source mutation, or stdout decision.
export async function sendOnce(message, config) {
  if (!message || !validConfig(config)) return false;
  return await new Promise(resolve => {
    let settled = false;
    const socket = net.createConnection(config.bridgeSocketPath);
    const finish = accepted => { if (settled) return; settled = true; clearTimeout(timer); socket.destroy(); resolve(accepted); };
    const timer = setTimeout(() => finish(false), config.bridgeTimeoutMs);
    socket.on('connect', () => socket.end(JSON.stringify(message) + '\n', () => finish(true)));
    socket.on('error', () => finish(false));
    socket.on('close', () => finish(false));
    socket.on('data', () => {});
  });
}

export async function readBoundedInput(stream, maximum = 1024 * 1024) {
  const chunks = []; let bytes = 0;
  for await (const chunk of stream) {
    bytes += chunk.length;
    if (bytes > maximum) { stream.destroy(); return null; }
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { return null; }
}
