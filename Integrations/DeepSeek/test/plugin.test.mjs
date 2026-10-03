import test from 'node:test';
import assert from 'node:assert/strict';
import net from 'node:net';
import { mkdtempSync, readFileSync, rmSync, existsSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import vm from 'node:vm';
import { once } from 'node:events';
import { BridgeSender, LifecycleProjection, NavigationBroker, resolveOptions, attachHost } from '../core.mjs';

const options = (extra = {}) => resolveOptions({ bridgeSocketPath: '/tmp/aisland-deepseek-test-absent.sock', ...extra }, {});
const session = (id = 'session-1') => ({ id, header: { cwd: '/test/project', secret: 'private' }, firstLiveSeq: 10 });
const event = (type, turn, seq, reason, time = 1000) => ({ type, seq, time, data: { turn, reason, prompt: 'PRIVATE PROMPT', tool_input: 'PRIVATE TOOL' } });
const hook = message => message.command.runtimeLifecycleHook;
function projected() { const output = []; return { output, p: new LifecycleProjection(options(), x => output.push(x), 1000) }; }

for (const [reason, result, reasonText] of [
  [{ kind: 'completed' }, 'turnCompleted', 'completed'],
  [{ kind: 'error', error: { message: 'PRIVATE ERROR' } }, 'turnFailed', 'error'],
  [{ kind: 'blocked' }, 'turnFailed', 'blocked'],
  [{ kind: 'max-tokens' }, 'turnFailed', 'max-tokens'],
  [{ kind: 'aborted', reason: { kind: 'user' } }, 'turnInterrupted', 'aborted:user'],
  [{ kind: 'aborted', reason: { kind: 'hook', reason: 'PRIVATE HOOK' } }, 'turnInterrupted', 'aborted:hook'],
  [{ kind: 'interrupted' }, 'turnInterrupted', 'interrupted'],
  [{ kind: 'vendor-private-kind' }, 'turnFailed', 'unknown'],
]) {
  test(`explicit reason ${reasonText}`, () => {
    const { p, output } = projected(); p.observe(session(), event('turn/start', 2, 10)); p.observe(session(), event('turn/end', 2, 11, reason));
    assert.equal(hook(output[1]).event, result); assert.equal(hook(output[1]).result_reason, reasonText);
    assert.doesNotMatch(JSON.stringify(output), /PRIVATE|secret|prompt|tool_input|vendor-private/);
  });
}

test('identity, per-session ordering, duplicate and older turn rejection', () => {
  const { p, output } = projected();
  p.observe(session(), event('turn/start', 2, 10)); p.observe(session('other'), event('turn/start', 2, 10));
  p.observe(session(), event('turn/start', 2, 10)); p.observe(session(), event('turn/end', 1, 11, { kind: 'completed' }));
  p.observe(session(), event('turn/end', 2, 12, { kind: 'completed' })); p.observe(session(), event('turn/end', 2, 12, { kind: 'completed' }));
  assert.deepEqual(output.map(x => [hook(x).session_id, hook(x).event]), [['session-1', 'turnStarted'], ['other', 'turnStarted'], ['session-1', 'turnCompleted']]);
  assert.equal(hook(output[0]).turn_id, '2'); assert.equal(hook(output[0]).profile_id, 'desktop');
  assert.equal(hook(output[0]).app_conversation_id, 'session-1'); assert.equal(hook(output[0]).cwd, '/test/project');
  assert.equal(hook(output[0]).navigation_socket_path, '/tmp/deepseek-navigation.sock');
});

test('old seed/start, end without observed start and idle never complete', () => {
  const { p, output } = projected();
  p.observe(session(), event('turn/start', 1, 9)); p.observe(session(), event('turn/start', 1, 10, null, 999));
  p.observe(session(), event('turn/end', 1, 11, { kind: 'completed' })); p.observe(session(), event('agent/status', 2, 12, { kind: 'idle' }));
  assert.equal(output.length, 0);
  const restarted = new LifecycleProjection(options(), x => output.push(x), 1000);
  restarted.observe(session(), event('turn/end', 2, 13, { kind: 'completed' })); assert.equal(output.length, 0);
  restarted.observe(session(), event('turn/start', 3, 14)); restarted.observe(session(), event('turn/end', 3, 15, { kind: 'completed' })); assert.equal(output.length, 2);
});

test('disposal ends only observed session, never successful completion', () => {
  const { p, output } = projected(); p.disposed(session()); p.observe(session(), event('turn/start', 2, 10)); p.disposed(session()); p.disposed(session());
  assert.deepEqual(output.map(x => hook(x).event), ['turnStarted', 'sessionEnded']); assert.equal(p.sessions.size, 0);
});

test('projection contains sender throw; transport disconnected stays asynchronous and disposes', async () => {
  const p = new LifecycleProjection(options(), () => { throw new Error('offline'); }, 1000);
  assert.doesNotThrow(() => p.observe(session(), event('turn/start', 1, 10)));
  const sender = new BridgeSender(options()); sender.enqueue({ test: 'metadata' }); assert.equal(sender.queue.length, 0);
  await new Promise(resolve => setTimeout(resolve, 20)); assert.equal(sender.socket, null); sender.dispose(); sender.enqueue({}); assert.equal(sender.queue.length, 0);
});

test('bridge sends newline envelope over isolated socket in event order', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'ai-ds-')); const path = join(dir, 'bridge.sock'); const lines = [];
  const server = net.createServer(socket => { let text = ''; socket.on('data', chunk => { text += chunk; }); socket.on('end', () => { lines.push(JSON.parse(text)); socket.end(); }); });
  server.listen(path); await once(server, 'listening'); const sender = new BridgeSender(options({ bridgeSocketPath: path }));
  sender.enqueue({ turn: 1 }); sender.enqueue({ turn: 2 });
  for (let i = 0; i < 100 && lines.length < 2; i++) await new Promise(resolve => setTimeout(resolve, 5));
  assert.deepEqual(lines, [{ turn: 1 }, { turn: 2 }]); sender.dispose(); await new Promise(resolve => server.close(resolve)); rmSync(dir, { recursive: true });
});

const request = (id = 'request-1') => ({ version: 1, action: 'openSession', request_id: id, session_id: 'exact-session', profile_id: 'desktop' });
test('broker exact acknowledgement matching, profile isolation, timeout and disposal', async () => {
  const broker = new NavigationBroker(options({ navigationTimeoutMs: 10 }));
  assert.equal((await broker.request({ ...request(), profile_id: 'cli' })).reason, 'profileMismatch');
  const result = broker.request(request()); const polled = broker.rpc('poll', {}).value.request; assert.deepEqual(polled, request());
  assert.equal(broker.rpc('ack', { ...request(), session_id: 'wrong', status: 'dispatched' }).value.accepted, false);
  assert.equal(broker.rpc('ack', { ...request(), status: 'dispatched' }).value.accepted, true);
  assert.equal((await result).status, 'dispatched');
  assert.equal((await broker.request(request('timeout'))).reason, 'clientUnavailable');
  const disposed = broker.request(request('disposed')); broker.dispose(); assert.equal((await disposed).status, 'failed');
});

test('navigation source socket validates and cleans its own endpoint only', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'ai-ds-')); const path = join(dir, 'nav.sock');
  const broker = new NavigationBroker(options({ navigationSocketPath: path, navigationTimeoutMs: 50 })); broker.listen(); await once(broker.server, 'listening');
  assert.equal(statSync(path).mode & 0o777, 0o600);
  const socket = net.createConnection(path); let wire = ''; socket.on('data', chunk => { wire += chunk; });
  socket.end(JSON.stringify({ bad: true }) + '\n'); await once(socket, 'close'); assert.equal(JSON.parse(wire).reason, 'invalidRequest');
  broker.dispose(); await new Promise(resolve => setTimeout(resolve, 5)); assert.equal(existsSync(path), false); rmSync(dir, { recursive: true });
});

function clientPlugin() {
  let plugin; vm.runInNewContext(readFileSync(new URL('../client.js', import.meta.url), 'utf8'), { window: { __ModuleLoader__: { load: entry => { assert.equal(entry.id, '@aisland/deepseek-harness-plugin'); plugin = entry.factory(); } } }, AbortController, setTimeout, clearTimeout }); return plugin;
}
for (const fails of [false, true]) {
  test(`fake client ${fails ? 'failure' : 'exact ID dispatch'} receipt and resource cleanup`, async () => {
    const calls = []; let cleanup; let resolveAck; const acked = new Promise(resolve => { resolveAck = resolve; });
    clientPlugin().apply({ effect(fn) { cleanup = fn(); }, uiWorkspace: { openSession(id) { calls.push(id); if (fails) throw new Error('PRIVATE FAILURE'); } }, connection: { rpc: { async call(channel, endpoint, payload, signal) {
      assert.equal(channel, '/aisland-deepseek'); assert.equal(signal.aborted, false);
      if (endpoint === 'poll') return { ok: true, value: { request: request(), poll_interval_ms: 5000 } };
      resolveAck(payload); return { ok: true, value: { accepted: true } };
    } } } });
    const ack = await acked; cleanup(); assert.deepEqual(calls, ['exact-session']); assert.equal(ack.status, fails ? 'failed' : 'dispatched');
    assert.equal(ack.request_id, 'request-1'); assert.equal(ack.profile_id, 'desktop'); assert.doesNotMatch(JSON.stringify(ack), /PRIVATE/);
  });
}

test('fake Cordis unload removes listeners, RPC route, socket and pending clients', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'ai-ds-')); const listeners = new Map(); const cleanups = []; let unregistered = false;
  const ctx = { on(name, listener) { listeners.set(name, listener); cleanups.push(() => listeners.delete(name)); }, effect(fn) { cleanups.push(fn()); }, connection: { rpc: { handle(channel) { assert.equal(channel, '/aisland-deepseek'); return async () => { unregistered = true; }; } } } };
  const runtime = attachHost(ctx, { bridgeSocketPath: join(dir, 'missing.sock'), navigationSocketPath: join(dir, 'nav.sock') }); await once(runtime.broker.server, 'listening');
  listeners.get('session/event')(session(), event('turn/start', 2, 10, null, Date.now()));
  for (const cleanup of cleanups.reverse()) await cleanup();
  assert.equal(listeners.size, 0); assert.equal(unregistered, true); assert.equal(runtime.sender.closed, true); assert.equal(runtime.broker.pending.size, 0);
  rmSync(dir, { recursive: true });
});

test('configuration precedence keeps test sockets separate from production', () => {
  const resolved = resolveOptions({ bridgeSocketPath: '/test/config.sock' }, { OPEN_ISLAND_SOCKET_PATH: '/test/env.sock' });
  assert.equal(resolved.bridgeSocketPath, '/test/config.sock'); assert.equal(resolved.navigationSocketPath, '/test/deepseek-navigation.sock');
  assert.equal(resolveOptions({}, { OPEN_ISLAND_SOCKET_PATH: '/test/env.sock' }).bridgeSocketPath, '/test/env.sock');
});
