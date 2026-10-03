import net from 'node:net';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { chmodSync, lstatSync, unlinkSync } from 'node:fs';

export const CHANNEL = '/aisland-deepseek';
export function resolveOptions(config = {}, env = process.env) {
  const bridgeSocketPath = config.bridgeSocketPath || env.OPEN_ISLAND_SOCKET_PATH || env.VIBE_ISLAND_SOCKET_PATH || join(homedir(), 'Library/Application Support/OpenIsland/bridge.sock');
  return {
    profileID: config.profileID || 'desktop', bridgeSocketPath,
    navigationSocketPath: config.navigationSocketPath || env.OPEN_ISLAND_DEEPSEEK_NAVIGATION_SOCKET_PATH || join(dirname(bridgeSocketPath), 'deepseek-navigation.sock'),
    bridgeTimeoutMs: config.bridgeTimeoutMs ?? 200,
    navigationTimeoutMs: config.navigationTimeoutMs ?? 2000,
    pollIntervalMs: config.pollIntervalMs ?? 500,
  };
}
const textID = value => typeof value === 'string' && value.length > 0 && value.length <= 1024 && !/[\r\n\0]/.test(value);
const nonnegative = value => Number.isSafeInteger(value) && value >= 0;

// Copy only known coarse reason enums. Error details and hook reason strings are private.
export function classifyReason(reason) {
  switch (reason?.kind) {
    case 'completed': return ['turnCompleted', 'completed'];
    case 'error': case 'blocked': case 'max-tokens': return ['turnFailed', reason.kind];
    case 'aborted': {
      const cause = ['user', 'parent', 'hook', 'disposed', 'legacy'].includes(reason.reason?.kind) ? reason.reason.kind : 'unknown';
      return ['turnInterrupted', `aborted:${cause}`];
    }
    case 'interrupted': case 'forked': return ['turnInterrupted', reason.kind];
    default: return ['turnFailed', 'unknown'];
  }
}
export class LifecycleProjection {
  constructor(options, send, startedAt = Date.now()) {
    this.options = options; this.send = send; this.startedAt = startedAt; this.sessions = new Map();
  }
  observe(session, event) {
    const id = session?.id;
    if (!textID(id) || !nonnegative(event?.seq) || !nonnegative(event?.time)) return;
    // Session seeds do not publish in the supported runtime; these guards also reject replay.
    if (event.time < this.startedAt || event.seq < (session.firstLiveSeq ?? 0)) return;
    if (!['turn/start', 'turn/end'].includes(event.type) || !nonnegative(event.data?.turn)) return;
    const state = this.sessions.get(id) ?? { sequence: -1, turn: -1, active: false, ended: false };
    if (event.seq <= state.sequence || event.data.turn < state.turn) return;
    state.sequence = event.seq;
    const turn = event.data.turn;
    let type; let reason; let observedStart = false;
    if (event.type === 'turn/start') {
      if (turn <= state.turn) return;
      state.turn = turn; state.active = true; state.ended = false; type = 'turnStarted'; observedStart = true;
    } else {
      if (state.turn === turn && state.ended) return;
      // Synchronize an end after plugin reload, but never turn it into a fresh notification.
      observedStart = state.turn === turn && state.active;
      state.turn = turn; state.active = false; state.ended = true;
      [type, reason] = classifyReason(event.data.reason);
    }
    this.sessions.set(id, state);
    this.publish(session, type, event.time, { turn_id: String(turn), sequence: event.seq,
      source_observed_start: observedStart, ...(reason ? { result_reason: reason } : {}) });
  }
  disposed(session) {
    if (!this.sessions.has(session?.id)) return;
    this.sessions.delete(session.id);
    this.publish(session, 'sessionEnded', Date.now());
  }
  publish(session, event, timestamp, extra = {}) {
    const hook = { source: 'deepseekHarness', event, profile_id: this.options.profileID, session_id: session.id,
      cwd: typeof session.header?.cwd === 'string' ? session.header.cwd : '', timestamp,
      app_bundle_id: 'com.deepseek.dsh', app_conversation_id: session.id, terminal_app: 'DeepSeek Harness.app',
      navigation_socket_path: this.options.navigationSocketPath, ...extra };
    try { this.send({ type: 'command', command: { type: 'processRuntimeLifecycleHook', runtimeLifecycleHook: hook } }); } catch { /* Source must continue. */ }
  }
}

// Bounded, ordered, no retry/replay: a disconnected bridge never delays Harness events.
export class BridgeSender {
  constructor(options) { this.options = options; this.queue = []; this.socket = null; this.closed = false; }
  enqueue(message) {
    if (this.closed || this.queue.length >= 256) return;
    this.queue.push(JSON.stringify(message) + '\n'); this.pump();
  }
  pump() {
    if (this.closed || this.socket || !this.queue.length) return;
    const line = this.queue.shift(); const socket = net.createConnection(this.options.bridgeSocketPath); this.socket = socket;
    socket.setTimeout(this.options.bridgeTimeoutMs);
    socket.once('connect', () => socket.end(line));
    socket.on('data', () => {});
    socket.once('error', () => socket.destroy());
    socket.once('timeout', () => socket.destroy());
    socket.once('close', () => { this.socket = null; this.pump(); });
  }
  dispose() { this.closed = true; this.queue.length = 0; this.socket?.destroy(); }
}

export class NavigationBroker {
  constructor(options) { this.options = options; this.pending = new Map(); this.closed = false; this.connections = new Set(); }
  request(request) {
    if (!request || request.version !== 1 || request.action !== 'openSession' || !textID(request.request_id) || !textID(request.session_id) || !textID(request.profile_id)) return Promise.resolve(this.reply(request, 'failed', 'invalidRequest'));
    if (request.profile_id !== this.options.profileID) return Promise.resolve(this.reply(request, 'failed', 'profileMismatch'));
    if (this.closed || this.pending.size >= 32 || this.pending.has(request.request_id)) return Promise.resolve(this.reply(request, 'failed', 'clientUnavailable'));
    return new Promise(resolve => {
      const timer = setTimeout(() => { this.pending.delete(request.request_id); resolve(this.reply(request, 'failed', 'clientUnavailable')); }, this.options.navigationTimeoutMs);
      this.pending.set(request.request_id, { request, timer, resolve, claimed: false });
    });
  }
  reply(request, status, reason) {
    return { version: 1, request_id: textID(request?.request_id) ? request.request_id : '', session_id: textID(request?.session_id) ? request.session_id : '', profile_id: this.options.profileID, status, ...(reason ? { reason } : {}) };
  }
  rpc(endpoint, payload) {
    if (endpoint === 'poll') {
      const item = [...this.pending.values()].find(item => !item.claimed);
      if (item) item.claimed = true;
      return { ok: true, value: { request: item?.request ?? null, poll_interval_ms: this.options.pollIntervalMs } };
    }
    if (endpoint === 'ack') {
      const item = this.pending.get(payload?.request_id);
      if (!item || !item.claimed || payload.session_id !== item.request.session_id || payload.profile_id !== this.options.profileID || !['dispatched', 'failed'].includes(payload.status)) return { ok: true, value: { accepted: false } };
      clearTimeout(item.timer); this.pending.delete(payload.request_id);
      item.resolve(this.reply(item.request, payload.status, payload.status === 'failed' ? 'clientError' : undefined));
      return { ok: true, value: { accepted: true } };
    }
    return { ok: false, error: { code: 'not-found', message: 'Unknown endpoint', details: {} } };
  }
  listen() {
    // Never delete an existing endpoint owned by another plugin/process.
    this.server = net.createServer({ allowHalfOpen: true }, socket => {
      this.connections.add(socket); socket.setTimeout(this.options.navigationTimeoutMs + 100);
      let buffer = ''; let handled = false;
      socket.on('data', chunk => {
        if (handled) return;
        buffer += chunk.toString('utf8');
        if (Buffer.byteLength(buffer) > 4096) { handled = true; socket.destroy(); return; }
        if (!buffer.includes('\n')) return;
        handled = true; let request;
        try { request = JSON.parse(buffer.slice(0, buffer.indexOf('\n'))); } catch { socket.end(JSON.stringify(this.reply(null, 'failed', 'invalidRequest')) + '\n'); return; }
        void this.request(request).then(reply => { if (!socket.destroyed) socket.end(JSON.stringify(reply) + '\n'); });
      });
      socket.on('error', () => {}); socket.on('timeout', () => socket.destroy()); socket.once('close', () => this.connections.delete(socket));
    });
    this.server.on('error', () => {});
    this.server.once('listening', () => {
      try { chmodSync(this.options.navigationSocketPath, 0o600); this.socketIdentity = lstatSync(this.options.navigationSocketPath).ino; } catch { this.server.close(); }
    });
    this.server.listen(this.options.navigationSocketPath);
  }
  dispose() {
    this.closed = true;
    for (const item of this.pending.values()) { clearTimeout(item.timer); item.resolve(this.reply(item.request, 'failed', 'clientUnavailable')); }
    this.pending.clear(); for (const socket of this.connections) socket.destroy();
    this.server?.close();
    try { if (this.socketIdentity !== undefined && lstatSync(this.options.navigationSocketPath).ino === this.socketIdentity) unlinkSync(this.options.navigationSocketPath); } catch {}
  }
}

export function attachHost(ctx, config = {}) {
  const options = resolveOptions(config); const sender = new BridgeSender(options); const broker = new NavigationBroker(options);
  const projection = new LifecycleProjection(options, message => sender.enqueue(message));
  ctx.on('session/event', (session, event) => projection.observe(session, event));
  ctx.on('session/disposed', session => projection.disposed(session));
  ctx.effect(() => {
    const handler = async (endpoint, payload) => broker.rpc(endpoint, payload);
    // 0.2.0-rc.2's rpc getter retains the provider's Cordis shadow. Pass the
    // caller explicitly through the same authenticated route registration.
    const unregister = typeof ctx.connection.register === 'function'
      ? ctx.connection.register(ctx, CHANNEL, handler)
      : ctx.connection.rpc.handle(CHANNEL, handler);
    try { broker.listen(); } catch { /* Optional navigation cannot block lifecycle/source activation. */ }
    return async () => { sender.dispose(); broker.dispose(); await unregister(); };
  });
  return { options, sender, broker, projection };
}
