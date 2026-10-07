import net from 'node:net';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { chmodSync, lstatSync, unlinkSync, mkdtempSync, linkSync, openSync, closeSync, fstatSync, readSync, writeFileSync, rmdirSync, constants } from 'node:fs';

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

const NAVIGATION_SOURCE = '@aisland/deepseek-harness-plugin';
const fingerprint = value => createHash('sha256').update(value).digest('hex');
const sameIdentity = (a, b) => a && b && a.dev === b.dev && a.ino === b.ino && a.uid === b.uid && a.mode === b.mode;
const snapshot = path => { try { return lstatSync(path); } catch { return null; } };
const receiptPath = path => `${path}.aisland-owner.json`;
const locatorPath = path => `${path}.aisland-current.json`;

// A receipt is evidence only for the exact endpoint, owner, profile and inode.
// Open without following links and recheck the receipt's own identity as well.
function readOwnedJSON(filename) {
  const identity = snapshot(filename); let fd;
  try {
    if (!identity?.isFile() || identity.uid !== process.getuid() || (identity.mode & 0o777) !== 0o600 || identity.nlink !== 1 || identity.size > 2048) return null;
    fd = openSync(filename, constants.O_RDONLY | constants.O_NOFOLLOW);
    if (!sameIdentity(identity, fstatSync(fd))) return null;
    const bytes = Buffer.alloc(2049); const count = readSync(fd, bytes, 0, bytes.length, 0);
    if (count > 2048 || !sameIdentity(identity, snapshot(filename))) return null;
    return { value: JSON.parse(bytes.subarray(0, count).toString('utf8')), identity };
  } catch { return null; } finally { if (fd !== undefined) closeSync(fd); }
}
function readReceipt(path, profileID, filename = receiptPath(path), requestedPath = path) {
  const proof = readOwnedJSON(filename);
  if (!proof) return null;
  const { value } = proof;
  if (value.version !== 1 || value.source !== NAVIGATION_SOURCE || value.path !== resolve(path) || dirname(value.path) !== dirname(resolve(requestedPath)) || value.requested_path !== resolve(requestedPath) || value.profile_sha256 !== fingerprint(profileID) || value.uid !== process.getuid() || !Number.isSafeInteger(value.dev) || !Number.isSafeInteger(value.ino)) return null;
  const directory = snapshot(value.bind_directory);
  if (typeof value.bind_directory !== 'string' || dirname(value.bind_directory) !== dirname(resolve(path)) || !/^\.ds-[a-zA-Z0-9]+$/.test(value.bind_directory.slice(value.bind_directory.lastIndexOf('/') + 1)) || !directory?.isDirectory() || directory.uid !== value.uid || (directory.mode & 0o777) !== 0o700 || directory.dev !== value.directory_dev || directory.ino !== value.directory_ino) return null;
  if (!Number.isSafeInteger(value.source_pid) || value.source_pid <= 0 || typeof value.executable_path !== 'string' || !value.executable_path.startsWith('/')) return null;
  return proof;
}
const matchesReceipt = (identity, receipt) => identity?.isSocket() && identity.uid === process.getuid() && (identity.mode & 0o777) === 0o600 && receipt && identity.dev === receipt.value.dev && identity.ino === receipt.value.ino && identity.uid === receipt.value.uid;

export class NavigationBroker {
  constructor(options) { this.options = options; this.pending = new Map(); this.closed = false; this.connections = new Set(); this.requestedPath = resolve(options.navigationSocketPath); }
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
  // Empty, bounded connection probe: never enqueue a navigation request.
  probe(path) {
    return new Promise(resolveProbe => {
      const socket = net.createConnection(path); let settled = false;
      const finish = result => { if (settled) return; settled = true; clearTimeout(timer); socket.destroy(); resolveProbe(result); };
      const timer = setTimeout(() => finish('timeout'), Math.min(200, this.options.navigationTimeoutMs));
      socket.once('connect', () => finish('connected'));
      socket.once('error', error => finish(error.code));
      socket.once('close', () => finish('closed'));
    });
  }
  async prepare(path, allowLegacyFallback) {
    const identity = snapshot(path); const proof = readReceipt(path, this.options.profileID, receiptPath(path), this.requestedPath);
    if (!identity) return snapshot(receiptPath(path)) ? 'blocked' : 'ready';
    if (!identity.isSocket() || identity.uid !== process.getuid() || (identity.mode & 0o777) !== 0o600) return 'blocked';
    if (await this.probe(path) !== 'ECONNREFUSED' || this.closed || !sameIdentity(identity, snapshot(path))) return 'blocked';
    if (!matchesReceipt(identity, proof)) return allowLegacyFallback ? 'legacy' : 'blocked';
    const currentProof = readReceipt(path, this.options.profileID, receiptPath(path), this.requestedPath);
    if (!sameIdentity(proof.identity, currentProof?.identity) || !matchesReceipt(snapshot(path), currentProof)) return 'blocked';
    // No asynchronous work between the final identity checks and removal.
    unlinkSync(path); unlinkSync(receiptPath(path));
    const oldBind = join(currentProof.value.bind_directory, 's');
    if (sameIdentity(identity, snapshot(oldBind))) unlinkSync(oldBind);
    const directory = snapshot(currentProof.value.bind_directory);
    if (directory?.isDirectory() && directory.uid === currentProof.value.uid && directory.dev === currentProof.value.directory_dev && directory.ino === currentProof.value.directory_ino && (directory.mode & 0o777) === 0o700) { try { rmdirSync(currentProof.value.bind_directory); } catch {} }
    return 'ready';
  }
  listen() {
    if (this.starting) return this.starting;
    if (this.closed) return Promise.resolve(false);
    this.server = net.createServer({ allowHalfOpen: true }, socket => {
      if (this.closed) { socket.destroy(); return; }
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
    this.starting = this.start().catch(() => false).then(async ready => {
      if (!ready) { if (this.server.listening) await new Promise(resolveClose => this.server.close(resolveClose)); this.cleanup(); }
      return ready;
    });
    return this.starting;
  }
  async start() {
    const parent = snapshot(dirname(this.requestedPath));
    if (!parent?.isDirectory() || parent.uid !== process.getuid() || (parent.mode & 0o022) !== 0) return false;
    let path = this.requestedPath; let state;
    const locator = snapshot(locatorPath(this.requestedPath));
    if (locator) {
      const entry = readOwnedJSON(locatorPath(this.requestedPath)); if (!entry) return false; const { value } = entry;
      const proof = typeof value.path === 'string' ? readReceipt(value.path, this.options.profileID, locatorPath(this.requestedPath), this.requestedPath) : null;
      if (!proof || !sameIdentity(locator, proof.identity) || !matchesReceipt(snapshot(value.path), proof)) return false;
      path = value.path; state = await this.prepare(path, false);
      if (state !== 'ready' || this.closed || !sameIdentity(locator, snapshot(locatorPath(this.requestedPath)))) return false;
      unlinkSync(locatorPath(this.requestedPath));
    } else { state = await this.prepare(path, true); }
    if (state === 'legacy') {
      // Preserve unknown legacy sockets, including crash leftovers without proof.
      path = join(dirname(path), `ds-nav-${fingerprint(`${path}\0${this.options.profileID}`).slice(0, 12)}.sock`);
      state = await this.prepare(path, false);
    }
    if (state !== 'ready' || this.closed) return false;
    // libuv unlinks the original bind path on close, even if it was replaced.
    // Keep that path private; publish a hard link with exclusive-create semantics.
    this.bindDirectory = mkdtempSync(join(dirname(path), '.ds-'));
    chmodSync(this.bindDirectory, 0o700); this.directoryIdentity = snapshot(this.bindDirectory);
    this.bindPath = join(this.bindDirectory, 's');
    const listening = await new Promise(resolveListen => {
      const ready = () => { this.server.off('error', failed); resolveListen(true); };
      const failed = () => { this.server.off('listening', ready); resolveListen(false); };
      this.server.once('listening', ready); this.server.once('error', failed);
      try { this.server.listen(this.bindPath); } catch { failed(); }
    });
    if (!listening || this.closed) return false;
    chmodSync(this.bindPath, 0o600); this.socketIdentity = snapshot(this.bindPath);
    if (!sameIdentity(parent, snapshot(dirname(path)))) return false;
    linkSync(this.bindPath, path); this.publishedPath = path;
    if (!sameIdentity(this.socketIdentity, snapshot(path))) return false;
    const value = { version: 1, source: NAVIGATION_SOURCE, path: resolve(path), requested_path: this.requestedPath, profile_sha256: fingerprint(this.options.profileID), uid: this.socketIdentity.uid, dev: this.socketIdentity.dev, ino: this.socketIdentity.ino, bind_directory: this.bindDirectory, directory_dev: this.directoryIdentity.dev, directory_ino: this.directoryIdentity.ino, source_pid: process.pid, executable_path: process.execPath };
    let fd;
    try {
      fd = openSync(receiptPath(path), constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
      this.receiptIdentity = fstatSync(fd); writeFileSync(fd, JSON.stringify(value) + '\n');
    } finally { if (fd !== undefined) closeSync(fd); fd = undefined; }
    try {
      fd = openSync(locatorPath(this.requestedPath), constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
      this.locatorIdentity = fstatSync(fd); writeFileSync(fd, JSON.stringify(value) + '\n');
    } finally { if (fd !== undefined) closeSync(fd); fd = undefined; }
    this.options.navigationSocketPath = path;
    return true;
  }
  dispose() {
    if (this.disposing) return this.disposing;
    this.closed = true;
    for (const item of this.pending.values()) { clearTimeout(item.timer); item.resolve(this.reply(item.request, 'failed', 'clientUnavailable')); }
    this.pending.clear(); for (const socket of this.connections) socket.destroy();
    this.disposing = (async () => {
      await this.starting;
      if (this.server?.listening) await new Promise(resolveClose => this.server.close(resolveClose));
      this.cleanup();
    })();
    return this.disposing;
  }
  cleanup() {
    try { if (sameIdentity(this.socketIdentity, snapshot(this.publishedPath))) unlinkSync(this.publishedPath); } catch {}
    try { if (sameIdentity(this.receiptIdentity, snapshot(receiptPath(this.publishedPath)))) unlinkSync(receiptPath(this.publishedPath)); } catch {}
    try { if (sameIdentity(this.locatorIdentity, snapshot(locatorPath(this.requestedPath)))) unlinkSync(locatorPath(this.requestedPath)); } catch {}
    try { if (sameIdentity(this.directoryIdentity, snapshot(this.bindDirectory))) rmdirSync(this.bindDirectory); } catch {}
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
    void broker.listen(); // Optional navigation never blocks lifecycle/source activation.
    return async () => { sender.dispose(); await broker.dispose(); await unregister(); };
  });
  return { options, sender, broker, projection };
}
