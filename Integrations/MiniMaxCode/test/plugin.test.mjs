import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, mkdtemp, rm, cp, writeFile } from 'node:fs/promises';
import { existsSync, readFileSync } from 'node:fs';
import net from 'node:net';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { Readable } from 'node:stream';
import { projectHook, validConfig, readBoundedInput, sendOnce } from '../scripts/core.mjs';
import { buildPlan } from '../plan.mjs';
const root = dirname(dirname(fileURLToPath(import.meta.url)));
const config = { schemaVersion: 1, source: 'minimaxCodeDesktop', sourceRuntimeVersion: '3.1.0', profileID: 'desktop-test',
  bridgeSocketPath: '/tmp/unused-test.sock', metadataDatabasePath: '/tmp/source-test/v2/sqlite/runtime-state.sqlite', bridgeTimeoutMs: 50 };
const input = { hook_event_name: 'UserPromptSubmit', session_id: 'session-test', turn_id: 'turn-test', cwd: '/tmp/workspace' };

test('Hook observation does not claim final success, even Stop or session release', () => {
  for (const name of ['SessionStart', 'UserPromptSubmit', 'Stop']) {
    const hook = projectHook({ ...input, hook_event_name: name, stop_hook_active: false }, config, 100).command.runtimeLifecycleHook;
    assert.equal(hook.event, 'sessionObserved'); assert.equal(hook.turn_id, 'turn-test');
  }
  const hook = projectHook({ ...input, hook_event_name: 'SessionEnd', reason: 'other' }, config, 100).command.runtimeLifecycleHook;
  assert.equal(hook.event, 'sessionEnded'); assert.equal(hook.source_observed_start, undefined);
  assert.equal(projectHook({ ...input, hook_event_name: 'SubagentStop' }, config, 100), null);
});
test('No invented native identity, timestamps, or private content', () => {
  const hook = projectHook({ ...input, turn_id: undefined, prompt: 'PRIVATE_PROMPT', transcript_path: '/PRIVATE_TRANSCRIPT',
    last_assistant_message: 'PRIVATE_RESPONSE', tool_input: { command: 'PRIVATE_ARG' }, error: 'PRIVATE_ERROR' }, config, 100).command.runtimeLifecycleHook;
  assert.equal(hook.turn_id, undefined); assert.equal(hook.event, 'sessionObserved');
  assert.ok(!JSON.stringify(hook).includes('PRIVATE'));
  assert.deepEqual(Object.keys(hook).sort(), ['app_bundle_id', 'app_conversation_id', 'cwd', 'event', 'metadata_database_path', 'profile_id', 'session_id', 'source', 'source_runtime_version', 'terminal_app', 'timestamp'].sort());
});
test('Reject malformed identities, source-version drift, config paths and non-object input', () => {
  for (const value of [null, [], 'text', 3, { ...input, session_id: '\ninvalid' }, { ...input, session_id: 'x'.repeat(513) }, { ...input, cwd: {} }]) assert.equal(projectHook(value, config), null);
  assert.equal(validConfig({ ...config, sourceRuntimeVersion: '3.2.0' }), false);
  assert.equal(validConfig({ ...config, bridgeSocketPath: 'relative.sock' }), false);
  assert.equal(validConfig({ ...config, bridgeTimeoutMs: 5000 }), false);
  const cli = { ...config, source: 'minimaxCodeCLI', sourceRuntimeVersion: '0.5.3' };
  assert.ok(validConfig(cli)); assert.equal(projectHook(input, cli, 100).command.runtimeLifecycleHook.app_bundle_id, undefined);
});
test('Input and disconnected bridge are bounded and fail open', async () => {
  assert.equal(await readBoundedInput(Readable.from([Buffer.from('{bad')])), null);
  assert.equal(await readBoundedInput(Readable.from([Buffer.alloc(16)]), 8), null);
  const started = Date.now(); assert.equal(await sendOnce(projectHook(input, config), config), false);
  assert.ok(Date.now() - started < 1000);
});
test('Dry-run plan renders a source-native plugin without changing the destination', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'aisland-minimax-plan-'));
  try {
    const args = { dataDir: join(dir, 'source'), bridgeSocketPath: join(dir, 'bridge.sock'), nodePath: process.execPath };
    const plan = await buildPlan(args);
    assert.equal(plan.mode, 'dry-run-only'); assert.equal(existsSync(plan.destination), false);
    assert.ok(plan.hooks.hooks.Stop[0].hooks[0].command.includes(process.execPath));
    await assert.rejects(buildPlan({ ...args, source: 'minimaxCodeCLI' }), /Desktop runtime verification/);
    assert.equal((await buildPlan({ ...args, source: 'minimaxCodeCLI', profileID: 'cli', desktopVerified: true })).config.sourceRuntimeVersion, '0.5.3');
  } finally { await rm(dir, { recursive: true, force: true }); }
});
test('Real command process sends metadata only and writes no source decision to stdout/stderr', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'aisland-minimax-hook-'));
  const socketPath = join(dir, 'bridge.sock'); const received = [];
  const server = net.createServer(socket => { let text = ''; socket.on('data', data => text += data); socket.on('end', () => { received.push(JSON.parse(text)); socket.end(); }); });
  await new Promise(resolve => server.listen(socketPath, resolve));
  try {
    await cp(join(root, 'scripts'), join(dir, 'scripts'), { recursive: true });
    await writeFile(join(dir, 'config.json'), JSON.stringify({ ...config, bridgeSocketPath: socketPath }));
    const child = spawn(process.execPath, [join(dir, 'scripts/hook.mjs')], { env: { PATH: process.env.PATH }, stdio: 'pipe' });
    let output = ''; child.stdout.on('data', data => output += data); child.stderr.on('data', data => output += data);
    child.stdin.end(JSON.stringify({ ...input, prompt: 'PRIVATE_PROMPT' }));
    const exit = await new Promise(resolve => child.once('close', resolve));
    assert.equal(exit, 0); assert.equal(output, ''); assert.equal(received.length, 1);
    assert.equal(received[0].command.runtimeLifecycleHook.event, 'sessionObserved'); assert.ok(!JSON.stringify(received).includes('PRIVATE_PROMPT'));
  } finally { await new Promise(resolve => server.close(resolve)); await rm(dir, { recursive: true, force: true }); }
});

// Read installed application code, never source databases, profiles, or user content.
function readAsarEntry(path) {
  const bytes = readFileSync('/Applications/MiniMax Code.app/Contents/Resources/app.asar');
  const header = JSON.parse(bytes.subarray(16, 16 + bytes.readUInt32LE(12)).toString('utf8'));
  let entry = header;
  for (const part of path.split('/')) entry = entry.files[part];
  const offset = 8 + bytes.readUInt32LE(4) + Number(entry.offset);
  return bytes.subarray(offset, offset + entry.size).toString('utf8');
}
test('Installed desktop package confirms native hooks and committed turn metadata contract', { skip: !existsSync('/Applications/MiniMax Code.app/Contents/Resources/app.asar') }, async () => {
  const base = 'node_modules/@mavis/local-runtime-v2/';
  const reference = readAsarEntry(base + 'assets/skills/plugin-creator/references/local-plugin-hooks.md');
  const hooks = JSON.parse(await readFile(join(root, 'hooks/hooks.json'), 'utf8'));
  for (const event of Object.keys(hooks.hooks)) assert.ok(reference.includes('`' + event + '`'));
  assert.match(reference, /when available, `turn_id`/);
  assert.match(reference, /continue once/);
  assert.match(readAsarEntry(base + 'dist/infra/db/client.js'), /join\('v2', 'sqlite', DB_FILE\)/);
  const schema = readAsarEntry(base + 'dist/infra/db/schema/turn.js');
  assert.match(schema, /status.*IN \('accepted', 'completed', 'failed', 'aborted'\)/);
  const repository = readAsarEntry(base + 'dist/service/turn-system/persistence/turn.repository.js');
  assert.match(repository, /set\(\{ status: input.outcome, completedAtMs \}\)/);
  assert.match(repository, /eq\(turnIngress.turnId, input.turnId\), eq\(turnIngress.sessionId, input.sessionId\)/);
});
