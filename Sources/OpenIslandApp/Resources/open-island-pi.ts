// Open Island extension for Pi and Oh My Pi.
// Installed into ~/.pi/agent/extensions or ~/.omp/agent/extensions.
import { connect } from "node:net";
import { homedir } from "node:os";
import { execFileSync } from "node:child_process";
import { realpathSync, lstatSync, fstatSync, openSync, closeSync, writeSync, unlinkSync, constants } from "node:fs";
import { createHash } from "node:crypto";
import { resolve, dirname, join } from "node:path";

const AGENT_SOURCE = "__OPEN_ISLAND_PI_SOURCE__";
const SESSION_PREFIX = AGENT_SOURCE === "oh-my-pi" ? "omp" : "pi";
const SOCKET_PATH =
  process.env.OPEN_ISLAND_SOCKET_PATH ||
  `${process.env.HOME || homedir()}/Library/Application Support/OpenIsland/bridge.sock`;
const DEFAULT_HEARTBEAT_INTERVAL_MS = 15_000;
const MAX_TIMER_INTERVAL_MS = 2_147_483_647;

function heartbeatIntervalFromEnvironment(value: string | undefined): number {
  if (value === undefined) return DEFAULT_HEARTBEAT_INTERVAL_MS;

  const parsed = Number(value);
  if (
    !Number.isSafeInteger(parsed)
    || parsed <= 0
    || parsed > MAX_TIMER_INTERVAL_MS
  ) {
    return DEFAULT_HEARTBEAT_INTERVAL_MS;
  }

  return parsed;
}

const HEARTBEAT_INTERVAL_MS = heartbeatIntervalFromEnvironment(
  process.env.OPEN_ISLAND_HEARTBEAT_INTERVAL_MS,
);

interface SessionManagerLike {
  getSessionId?: () => string;
  getSessionFile?: () => string | undefined;
}

interface ModelLike {
  provider?: string;
  id?: string;
}

interface ExtensionContextLike {
  cwd: string;
  hasUI?: boolean;
  sessionManager?: SessionManagerLike;
  model?: ModelLike;
}

interface ExtensionEvent {
  source?: "interactive" | "rpc" | "extension";
  prompt?: string;
  toolName?: string;
  args?: unknown;
  reason?: string;
  willContinue?: boolean;
  messages?: { role?: string; stopReason?: string }[];
  message?: {
    role?: string;
    content?: unknown;
  };
}

type ExtensionHandler = (event: ExtensionEvent, ctx: ExtensionContextLike) => void | Promise<void>;

interface ExtensionAPICompat {
  on(event: string, handler: ExtensionHandler): void;
}


function sendToSocket(command: unknown): Promise<void> {
  const { promise, resolve } = Promise.withResolvers<void>();

  try {
    const socket = connect({ path: SOCKET_PATH }, () => {
      socket.end(JSON.stringify({ type: "command", command }) + "\n");
    });
    socket.once("close", resolve);
    socket.once("error", resolve);
    socket.setTimeout(3000, () => {
      socket.destroy();
      resolve();
    });
  } catch {
    resolve();
  }

  return promise;
}

export type GhosttyDiagnosticRecord = Record<string, string | boolean | number>;
export function ghosttyIDHash(id: string): string { return createHash("sha256").update(id, "utf8").digest("hex"); }
const diagnosticReasons = new Set(["noUI", "notGhostty", "inputSourceRejected", "bindingReused", "bindingAdmitted", "bindingRejected", "snapshotUnavailable", "notFrontmost", "focusChanged", "invalidInventory", "focusedCWDNotFound", "ambiguousCWD", "launchFailed", "timeout", "exitFailed", "invalidOutput", "emptySnapshot", "parseFailed", "snapshotReady", "notRunning", "tooManySurfaces"]);
export function piDiagnostic(stage: string, reason: string, fields: GhosttyDiagnosticRecord = {}, nativeID?: string, surfaceID?: string): GhosttyDiagnosticRecord {
  const record: GhosttyDiagnosticRecord = { stage: stage === "piLocator" ? stage : "piCapture", reason: diagnosticReasons.has(reason) ? reason : "other", agent: ["pi", "oh-my-pi"].includes(AGENT_SOURCE) ? AGENT_SOURCE : "other" };
  const events = new Set(["sessionStart", "interactive", "rpc", "extension", "unknown"]);
  if (typeof fields.event === "string") record.event = events.has(fields.event) ? fields.event : "unknown";
  for (const key of ["hasRealTTY", "hasUI", "hasBinding", "isGhostty", "frontmostBefore", "frontmostAfter", "focusStable"]) {
    if (typeof fields[key] === "boolean") record[key] = fields[key];
  }
  for (const key of ["surfaceCount", "cwdMatchCount", "exitStatus"]) {
    if (typeof fields[key] === "number" && Number.isFinite(fields[key])) record[key] = Math.max(-1, Math.min(256, Math.trunc(fields[key])));
  }
  if (nativeID && Buffer.byteLength(nativeID) <= 512) record.nativeIDHash = ghosttyIDHash(nativeID);
  if (surfaceID && Buffer.byteLength(surfaceID) <= 512) record.surfaceIDHash = ghosttyIDHash(surfaceID);
  return record;
}

// Same private marker/lock/log contract as Core. No free text, terminal content,
// error message, path, TTY or environment value can enter the trace.
export function writeGhosttyDiagnostic(record: GhosttyDiagnosticRecord, directory: string): void {
  let marker: number | undefined, lock: number | undefined, log: number | undefined;
  const lockPath = join(directory, ".ghostty-diagnostics.lock");
  const safe = (fd: number, empty: boolean) => {
    const info = fstatSync(fd);
    return info.isFile() && info.uid === process.getuid?.() && (info.mode & 0o7777) === 0o600 && info.nlink === 1 && (empty ? info.size === 0 : info.size <= 262_144);
  };
  try {
    const dir = lstatSync(directory);
    if (!dir.isDirectory() || dir.uid !== process.getuid?.() || (dir.mode & 0o022) !== 0) return;
    marker = openSync(join(directory, ".ghostty-diagnostics-enabled"), constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
    if (!safe(marker, true)) return;
    lock = openSync(lockPath, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
    log = openSync(join(directory, "ghostty-diagnostics.jsonl"), constants.O_WRONLY | constants.O_CREAT | constants.O_APPEND | constants.O_NOFOLLOW | constants.O_NONBLOCK, 0o600);
    if (!safe(log, false)) return;
    const current = lstatSync(directory);
    if (current.dev !== dir.dev || current.ino !== dir.ino || !current.isDirectory()) return;
    // Re-admit even records supplied through the injectable diagnostic seam.
    const safeRecord = piDiagnostic(String(record.stage), String(record.reason), record);
    for (const key of ["nativeIDHash", "surfaceIDHash"]) {
      if (typeof record[key] === "string" && /^[a-f0-9]{64}$/.test(record[key] as string)) safeRecord[key] = record[key];
    }
    const line = Buffer.from(JSON.stringify({ ...safeRecord, timestamp: new Date().toISOString() }) + "\n");
    if (line.length > 2_048 || fstatSync(log).size + line.length > 262_144) return;
    writeSync(log, line);
  } catch {} finally {
    if (log !== undefined) { try { closeSync(log); } catch {} }
    if (lock !== undefined) { try { closeSync(lock); } catch {} try { unlinkSync(lockPath); } catch {} }
    if (marker !== undefined) { try { closeSync(marker); } catch {} }
  }
}

function detectTTY(): string | undefined {
  try {
    let pid = process.pid;
    for (let depth = 0; depth < 8; depth += 1) {
      const output = execFileSync("/bin/ps", ["-o", "tty=,ppid=", "-p", String(pid)], {
        timeout: 1000,
      }).toString().trim();
      const [tty, parent] = output.split(/\s+/);
      if (tty && tty !== "??" && tty !== "?") return `/dev/${tty}`;
      const parentPID = Number.parseInt(parent || "", 10);
      if (!parentPID || parentPID <= 1) break;
      pid = parentPID;
    }
  } catch {}
  return undefined;
}

export interface GhosttySurface { id: string; cwd: string; title: string }
export interface GhosttySnapshot { frontmost: boolean; focusedID: string; surfaces: GhosttySurface[] }
interface GhosttyBinding extends GhosttySurface {}

function normalizedDirectory(cwd: string): string {
  try { return realpathSync(cwd); } catch { return resolve(cwd); }
}

// 1.3.1 exposes ID/name/cwd, but no TTY/PID or documented inheritable surface ID.
// Do not admit TERM_SESSION_ID or an assumed GHOSTTY_SURFACE_ID as a Ghostty ID.
export function admitGhosttyBinding(snapshot: GhosttySnapshot | undefined, cwd: string,
  normalize: (value: string) => string = normalizedDirectory, interactiveInput = false, realPTYSource = false): GhosttyBinding | undefined {
  if (!snapshot?.frontmost || !snapshot.focusedID || snapshot.surfaces.length > 256) return;
  if (snapshot.surfaces.some(surface => !surface.id) || new Set(snapshot.surfaces.map(surface => surface.id)).size !== snapshot.surfaces.length) return;
  const matches = snapshot.surfaces.filter(surface => normalize(surface.cwd) === normalize(cwd));
  const focused = snapshot.surfaces.filter(surface => surface.id === snapshot.focusedID);
  if (focused.length !== 1) return;
  // OSC cwd describes the shell, while OMP can start in /tmp or change cwd.
  // Only this source's interactive UI input with a real PTY may bind the
  // stable focused native surface without a shell-cwd match. Startup and
  // RPC/extension/background events keep the unique matching-cwd gate.
  if (!(interactiveInput && realPTYSource) && normalize(focused[0].cwd) !== normalize(cwd)) return;
  if (!interactiveInput && matches.length !== 1) return;
  return { ...focused[0], cwd: normalize(cwd) };
}

export function parseGhosttySnapshot(output: string): GhosttySnapshot | undefined {
  if (Buffer.byteLength(output) > 1_048_576) return;
  const lines = output.trimEnd().split("\n");
  const header = lines.shift()?.split("\x1f");
  if (header?.length !== 2 || header[0] !== "focused" || !header[1] || lines.length > 256) return;
  const surfaces: GhosttySurface[] = [];
  for (const line of lines) {
    const fields = line.split("\x1f");
    if (fields.length !== 3 || !fields[0] || !fields[1]) return;
    surfaces.push({ id: fields[0], cwd: fields[1], title: fields[2] });
  }
  return { frontmost: true, focusedID: header[1], surfaces };
}

export function readGhosttySnapshot(diagnostic: (record: GhosttyDiagnosticRecord) => void, run: typeof execFileSync = execFileSync): GhosttySnapshot | undefined {
  // Read metadata only. Never activate Ghostty or capture terminal content.
  const script = `tell application "Ghostty"
    if not (it is running) then return "diagnostic:notRunning"
    if not frontmost then return "diagnostic:notFrontmost"
    if (count of terminals) > 256 then return "diagnostic:tooManySurfaces"
    set focusedID to id of focused terminal of selected tab of front window as text
    set output to "focused" & (ASCII character 31) & focusedID & linefeed
    repeat with aTerminal in terminals
      set output to output & (id of aTerminal as text) & (ASCII character 31) & (working directory of aTerminal as text) & (ASCII character 31) & (name of aTerminal as text) & linefeed
    end repeat
    if not frontmost then return "diagnostic:notFrontmost"
    if (id of focused terminal of selected tab of front window as text) is not focusedID then return "diagnostic:focusChanged"
    return output
  end tell`;
  try {
    const output = run("/usr/bin/osascript", ["-e", script], {
      timeout: 1500, maxBuffer: 1_048_576, stdio: ["ignore", "pipe", "ignore"],
    }).toString();
    if (["diagnostic:notRunning", "diagnostic:notFrontmost", "diagnostic:tooManySurfaces", "diagnostic:focusChanged"].includes(output.trim())) {
      diagnostic(piDiagnostic("piLocator", output.trim().slice("diagnostic:".length), { exitStatus: 0 }));
      return;
    }
    const snapshot = parseGhosttySnapshot(output);
    diagnostic(piDiagnostic("piLocator", snapshot ? "snapshotReady" : output.trim() ? "parseFailed" : "emptySnapshot", { exitStatus: 0 }));
    return snapshot;
  } catch (error) {
    const failure = (error && typeof error === "object" ? error : {}) as { status?: unknown; code?: unknown };
    const reason = failure.code === "ETIMEDOUT" ? "timeout" : typeof failure.status === "number" ? "exitFailed" : "launchFailed";
    diagnostic(piDiagnostic("piLocator", reason, typeof failure.status === "number" ? { exitStatus: failure.status } : {}));
    return undefined;
  }
}

export interface PiExtensionDependencies {
  diagnostic?: (record: GhosttyDiagnosticRecord) => void;
  environment?: Record<string, string | undefined>;
  getTTY?: () => string | undefined;
  ghosttySnapshot?: () => GhosttySnapshot | undefined;
  normalizeDirectory?: (value: string) => string;
  sendCommand?: (command: unknown) => Promise<void>;
  heartbeatIntervalMs?: number;
}

function terminalFields(env: Record<string, string | undefined>, detectedTTY: string | undefined,
  binding?: GhosttyBinding): Record<string, string> {
  const result: Record<string, string> = {};
  if (env.ITERM_SESSION_ID) {
    result.terminal_app = "iTerm";
    result.terminal_session_id = env.ITERM_SESSION_ID;
  } else if (env.CMUX_WORKSPACE_ID || env.CMUX_SOCKET_PATH) {
    result.terminal_app = "cmux";
    if (env.CMUX_SURFACE_ID) result.terminal_session_id = env.CMUX_SURFACE_ID;
  } else if (env.ZELLIJ != null) {
    result.terminal_app = "Zellij";
    const paneID = env.ZELLIJ_PANE_ID || "";
    const sessionName = env.ZELLIJ_SESSION_NAME || "";
    if (paneID) result.terminal_session_id = `${paneID}:${sessionName}`;
  } else if ((env.TERM_PROGRAM || "").toLowerCase().includes("ghostty") || (!env.TERM_PROGRAM && env.GHOSTTY_RESOURCES_DIR)) {
    result.terminal_app = "Ghostty";
    if (binding) {
      result.terminal_session_id = binding.id;
      result.terminal_title = binding.title;
    }
  } else if (env.TERM_PROGRAM === "Apple_Terminal") {
    result.terminal_app = "Terminal";
  } else if (env.TERM_PROGRAM) {
    result.terminal_app = env.TERM_PROGRAM;
  }
  if (result.terminal_app !== "Ghostty" && env.TERM_SESSION_ID && !result.terminal_session_id) {
    result.terminal_session_id = env.TERM_SESSION_ID;
  }
  if (detectedTTY) result.terminal_tty = detectedTTY;
  return result;
}

function textContent(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  const texts: string[] = [];
  for (const part of content) {
    if (
      part !== null
      && typeof part === "object"
      && "type" in part
      && part.type === "text"
      && "text" in part
      && typeof part.text === "string"
    ) {
      texts.push(part.text);
    }
  }
  return texts.join("\n").trim();
}

function safeJSON(value: unknown): string | undefined {
  try {
    const encoded = JSON.stringify(value);
    return encoded.length > 500 ? `${encoded.slice(0, 499)}…` : encoded;
  } catch {
    return undefined;
  }
}

export default function openIslandPiExtension(pi: ExtensionAPICompat, dependencies: PiExtensionDependencies = {}) {
  const environment = dependencies.environment || process.env;
  const tty = (dependencies.getTTY || detectTTY)();
  const diagnostic = dependencies.diagnostic || ((record: GhosttyDiagnosticRecord) => writeGhosttyDiagnostic(record, dirname(SOCKET_PATH)));
  const locator = dependencies.ghosttySnapshot || (() => readGhosttySnapshot(diagnostic));
  const normalize = dependencies.normalizeDirectory || normalizedDirectory;
  const sendCommand = dependencies.sendCommand || sendToSocket;
  const heartbeatInterval = dependencies.heartbeatIntervalMs === undefined ? HEARTBEAT_INTERVAL_MS
    : heartbeatIntervalFromEnvironment(String(dependencies.heartbeatIntervalMs));
  const ghosttyBindings = new Map<string, GhosttyBinding>();
  function sessionID(ctx: ExtensionContextLike): string {
    return ctx.sessionManager?.getSessionId?.() || ctx.sessionManager?.getSessionFile?.() || `${ctx.cwd}:${process.pid}`;
  }
  function captureGhosttyBinding(ctx: ExtensionContextLike, interactiveInput = false): void {
    const key = sessionID(ctx);
    const existing = ghosttyBindings.get(key);
    const fields: GhosttyDiagnosticRecord = { event: interactiveInput ? "interactive" : "sessionStart", hasUI: ctx.hasUI === true,
      hasRealTTY: !!tty && /^\/dev\/tty\S+$/.test(tty), hasBinding: !!existing };
    const report = (reason: string, surfaceID?: string) => diagnostic(piDiagnostic("piCapture", reason, fields, `${SESSION_PREFIX}-${key}`, surfaceID));
    if (!ctx.hasUI) { report("noUI"); return; }
    fields.isGhostty = terminalFields(environment, tty).terminal_app === "Ghostty";
    if (!fields.isGhostty) { report("notGhostty"); return; }
    if (existing) { report("bindingReused", existing.id); return; }
    const snapshot = locator();
    if (snapshot) { fields.frontmostBefore = snapshot.frontmost; fields.surfaceCount = snapshot.surfaces.length;
      fields.cwdMatchCount = snapshot.surfaces.filter(surface => normalize(surface.cwd) === normalize(ctx.cwd || process.cwd())).length; }
    const binding = admitGhosttyBinding(snapshot, ctx.cwd || process.cwd(), normalize, interactiveInput, fields.hasRealTTY === true);
    if (binding) ghosttyBindings.set(key, binding);
    report(binding ? "bindingAdmitted" : !snapshot ? "snapshotUnavailable" : !snapshot.frontmost ? "notFrontmost"
      : new Set(snapshot.surfaces.map(surface => surface.id)).size !== snapshot.surfaces.length ? "invalidInventory"
      : fields.cwdMatchCount === 0 ? "focusedCWDNotFound" : !interactiveInput && Number(fields.cwdMatchCount) > 1 ? "ambiguousCWD" : "bindingRejected", binding?.id);
  }
  let lastAssistantMessage = "";
  let stopSent = false;
  let heartbeatTimer: NodeJS.Timeout | undefined;
  function contextFields(ctx: ExtensionContextLike): Record<string, unknown> {
    const sessionManager = ctx.sessionManager;
    const rawID = sessionID(ctx);
    const model = ctx.model
      ? [ctx.model.provider, ctx.model.id].filter(Boolean).join("/")
      : undefined;
    return {
      agent: AGENT_SOURCE,
      session_id: `${SESSION_PREFIX}-${rawID}`,
      cwd: ctx.cwd || process.cwd(),
      model,
      transcript_path: sessionManager?.getSessionFile?.(),
      ...terminalFields(environment, tty,
        ghosttyBindings.get(rawID)),
    };
  }

  function send(
    eventName: string,
    ctx: ExtensionContextLike,
    extra: Record<string, unknown> = {},
  ): Promise<void> {
    return sendCommand({
      type: "processPiHook",
      piHook: {
        hook_event_name: eventName,
        ...contextFields(ctx),
        ...extra,
      },
    });
  }
  function stopHeartbeat(): void {
    if (heartbeatTimer === undefined) return;
    clearInterval(heartbeatTimer);
    heartbeatTimer = undefined;
  }

  function startHeartbeat(ctx: ExtensionContextLike): void {
    stopHeartbeat();
    heartbeatTimer = setInterval(() => {
      void send("Heartbeat", ctx);
    }, heartbeatInterval);
    heartbeatTimer.unref();
  }


  function sendStop(ctx: ExtensionContextLike): Promise<void> {
    if (stopSent) return Promise.resolve();
    stopSent = true;
    return send("Stop", ctx, {
      last_assistant_message: lastAssistantMessage || undefined,
    });
  }

  pi.on("session_start", (_event, ctx) => {
    captureGhosttyBinding(ctx);
    lastAssistantMessage = "";
    stopSent = false;
    void send("SessionStart", ctx);
    startHeartbeat(ctx);
  });

  // Pi and OMP identify actual TUI input as interactive. This is the source
  // evidence that distinguishes two processes sharing one working directory.
  // Never inspect event.text; before_agent_start can also originate in RPC or
  // an extension, so it must not infer ownership from the currently focused pane.
  pi.on("input", (event, ctx) => {
    if (event.source === "interactive") captureGhosttyBinding(ctx, true);
    else diagnostic(piDiagnostic("piCapture", "inputSourceRejected", { event: event.source || "unknown", hasUI: ctx.hasUI === true }, `${SESSION_PREFIX}-${sessionID(ctx)}`));
  });

  pi.on("before_agent_start", (event, ctx) => {
    lastAssistantMessage = "";
    stopSent = false;
    void send("UserPromptSubmit", ctx, { prompt: event.prompt });
    process.env.OPEN_ISLAND_ACTIVE = "1";
  });

  pi.on("agent_start", () => {
    stopSent = false;
  });

  pi.on("tool_execution_start", (event, ctx) => {
    void send("PreToolUse", ctx, {
      tool_name: event.toolName,
      tool_input: safeJSON(event.args),
    });
  });


  pi.on("tool_execution_end", (event, ctx) => {
    void send("PostToolUse", ctx, { tool_name: event.toolName });
  });


  pi.on("message_end", (event) => {
    if (event.message?.role !== "assistant") return;
    const text = textContent(event.message.content);
    if (text) lastAssistantMessage = text;
  });

  if (AGENT_SOURCE === "oh-my-pi") {
    pi.on("session_stop", (_event, ctx) => sendStop(ctx));
    // OMP can settle without invoking session_stop (e.g. a terminal tool-call
    // path). Its public agent_end is emitted after maintenance, with an
    // explicit continuation flag. Intermediate settles must stay running.
    pi.on("agent_end", (event, ctx) => {
      if (event.willContinue === true) return;
      const assistant = event.messages?.findLast(message => message.role === "assistant");
      if (assistant?.stopReason === "aborted" || assistant?.stopReason === "error") return;
      return sendStop(ctx); // one completion across both callbacks
    });
  } else {
    pi.on("agent_settled", (_event, ctx) => sendStop(ctx));
  }

  pi.on("session_shutdown", (event, ctx) => {
    stopHeartbeat();
    if (event.reason === "reload") return;
    return send("SessionEnd", ctx);
  });
}
