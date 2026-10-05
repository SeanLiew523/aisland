import { test, expect } from "bun:test";
import plugin, * as moduleExports from "../Sources/OpenIslandApp/Resources/open-island-opencode.js";

const environment = { HOME: "/synthetic", TERM_PROGRAM: "ghostty" };
const row = (pid: number, parent: number, tty = "??") => `${pid} ${parent} ${tty}\n`;

async function fixture(options: any = {}) {
  const sent: any[] = [], queries: any[] = [];
  let clock = 0;
  const env = options.environment || { ...environment };
  const hooks = await plugin({ client: options.client, serverUrl: options.serverUrl }, {
    environment: env, pid: options.pid ?? 100, now: () => clock,
    debugLog: () => {}, sendCommand: async (command: any) => { sent.push(command.openCodeHook); },
    sendAndWaitResponse: options.sendAndWaitResponse || (async () => null),
    runProcess: (path: string, args: string[], settings: any) => {
      queries.push({ path, pid: Number(args[1]), timeout: settings.timeout });
      // No real process, source app, UI, argv, session data, or environment read.
      expect(path).toBe("/bin/ps");
      expect(args.slice(2)).toEqual(["-o", "pid=,ppid=,tty="]);
      expect(settings.timeout).toBeLessThanOrEqual(200);
      expect(settings.maxBuffer).toBe(1024);
      expect(settings.killSignal).toBe("SIGKILL");
      clock += options.elapsed || 0;
      if (options.failure) throw new Error("synthetic process failure");
      return options.rows?.[Number(args[1])] ?? row(Number(args[1]), 1, "ttys001");
    },
  });
  const emit = (type: string, properties = {}) => hooks.event({ event: { type, properties } });
  const start = (id = "native-A", cwd = "/synthetic/project") => emit("session.created", { info: { id, directory: cwd } });
  return { hooks, env, sent, queries, emit, start };
}

test("default-only exports preserve OpenCode legacy plugin loading", () => {
  expect(Object.keys(moduleExports)).toEqual(["default"]);
});

test("true ancestor TTY is reused for interleaved background events", async () => {
  const f = await fixture({ rows: { 100: row(100, 90), 90: row(90, 80), 80: row(80, 1, "ttys007") } });
  await f.start(); await f.start("native-B");
  f.env.TERM_SESSION_ID = "stale-foreign-surface";
  await f.emit("message.updated", { info: { id: "message-A", sessionID: "native-A", role: "user" } });
  await f.emit("message.part.updated", { part: { type: "text", messageID: "message-A", text: "synthetic input" } });
  await f.emit("message.part.updated", { part: { type: "tool", sessionID: "native-B", tool: "read", state: { status: "running" } } });
  await f.emit("session.status", { sessionID: "native-A", status: { type: "idle" } });
  expect(f.queries.map(x => x.pid)).toEqual([100, 90, 80]);
  expect(f.sent.map(x => x.hook_event_name)).toEqual(["SessionStart", "SessionStart", "UserPromptSubmit", "PreToolUse", "Stop"]);
  expect(f.sent.every(x => x.terminal_tty === "/dev/ttys007")).toBe(true);
  expect(f.sent.every(x => x.terminal_app === "Ghostty" && x.terminal_session_id === undefined)).toBe(true);
});

for (const malformed of [
  "100 90", "100 90 ttys001 extra", "101 90 ttys001", "100 90abc ttys001",
  "100 -1 ttys001", "100 2147483648 ttys001", "100 90 /tmp/ttys001",
  "100 90 tty../other", "100\n90 ttys001", "100 90 ttys001\n101 1 ttys002",
  "100 90 ttys001" + " ".repeat(1025),
]) {
  test(`malformed or mismatched process row is rejected: ${JSON.stringify(malformed.slice(0, 45))}`, async () => {
    const f = await fixture({ rows: { 100: malformed } }); await f.start();
    expect(f.sent[0].terminal_tty).toBeUndefined(); expect(f.queries).toHaveLength(1);
  });
}

test("visited set stops a process cycle without querying it twice", async () => {
  const f = await fixture({ rows: { 100: row(100, 90), 90: row(90, 100) } }); await f.start();
  expect(f.queries.map(x => x.pid)).toEqual([100, 90]); expect(f.sent[0].terminal_tty).toBeUndefined();
});

for (const parent of [0, 1]) {
  test(`ancestry stops before init parent ${parent}`, async () => {
    const f = await fixture({ rows: { 100: row(100, parent) } }); await f.start();
    expect(f.queries).toHaveLength(1); expect(f.sent[0].terminal_tty).toBeUndefined();
  });
}

test("self plus seven parents can find a TTY but never reads a ninth process", async () => {
  const rows = Object.fromEntries(Array.from({ length: 9 }, (_, i) => [100 - i, row(100 - i, 99 - i, i === 7 ? "ttys008" : "??")]));
  const success = await fixture({ rows }); await success.start();
  expect(success.sent[0].terminal_tty).toBe("/dev/ttys008"); expect(success.queries).toHaveLength(8);
  rows[93] = row(93, 92); rows[92] = row(92, 1, "ttys009");
  const tooDeep = await fixture({ rows }); await tooDeep.start();
  expect(tooDeep.sent[0].terminal_tty).toBeUndefined(); expect(tooDeep.queries).toHaveLength(8);
});

test("1.5 second total deadline shrinks the final process timeout and rejects late output", async () => {
  const rows = Object.fromEntries(Array.from({ length: 8 }, (_, i) => [100 - i, row(100 - i, 99 - i)]));
  const f = await fixture({ rows, elapsed: 200 }); await f.start();
  expect(f.queries).toHaveLength(8); expect(f.queries.at(-1).timeout).toBe(100);
  expect(f.sent[0].terminal_tty).toBeUndefined();
  const late = await fixture({ elapsed: 1501 }); await late.start();
  expect(late.sent[0].terminal_tty).toBeUndefined(); expect(late.queries).toHaveLength(1);
});

test("process timeout fails open without inherited TTY fallback", async () => {
  const f = await fixture({ failure: true, environment: { ...environment, TTY: "/dev/ttys999", TERM_SESSION_ID: "inherited" } });
  await f.start(); expect(f.sent[0].terminal_tty).toBeUndefined(); expect(f.sent[0].terminal_session_id).toBeUndefined();
});

test("API and TUI-command events never consume a foreground snapshot or foreign env ID", async () => {
  for (const id of [undefined, "stale-ID", "currently-focused-other-page"]) {
    const f = await fixture({ environment: { ...environment, TERM_SESSION_ID: id, GHOSTTY_SURFACE_ID: id } });
    // Same cwd, different native sessions: no evidence distinguishes their panes.
    await f.start("API-A", "/synthetic/shared"); await f.start("API-B", "/synthetic/shared");
    await f.emit("tui.command.execute", { command: "prompt.submit" });
    await f.emit("tui.session.select", { sessionID: "API-B" });
    await f.emit("message.updated", { info: { id: "API-message", sessionID: "API-B", role: "user" } });
    await f.emit("message.part.updated", { part: { type: "text", messageID: "API-message", text: "synthetic API input" } });
    await f.emit("session.status", { sessionID: "API-A", status: { type: "idle" } });
    expect(f.sent.every(x => x.terminal_session_id === undefined && x.terminal_title === undefined)).toBe(true);
    expect(f.queries).toHaveLength(1); // Only ps; no native surface reader exists on this untrusted entry point.
  }
});

test("inherited Ghostty marker does not override Terminal and iTerm metadata", async () => {
  const terminal = await fixture({ environment: { HOME: "/synthetic", TERM_PROGRAM: "Apple_Terminal", GHOSTTY_RESOURCES_DIR: "/inherited", TERM_SESSION_ID: "terminal-ID" } });
  await terminal.start(); expect(terminal.sent[0].terminal_app).toBe("Terminal");
  expect(terminal.sent[0].terminal_session_id).toBeUndefined(); // Preserve the existing Terminal payload contract.
  const iterm = await fixture({ environment: { HOME: "/synthetic", TERM_PROGRAM: "iTerm.app", GHOSTTY_RESOURCES_DIR: "/inherited", ITERM_SESSION_ID: "iterm-ID" } });
  await iterm.start(); expect(iterm.sent[0].terminal_app).toBe("iTerm"); expect(iterm.sent[0].terminal_session_id).toBe("iterm-ID");
  const output = { env: {} as Record<string, string> }; await iterm.hooks["shell.env"]({}, output);
  expect(output.env._OI_ITERM_SESSION_ID).toBe("iterm-ID"); expect(output.env.OPEN_ISLAND_ACTIVE).toBe("1");
});


test("permission and question callbacks preserve bridge response routing", async () => {
  const requests: any[] = [], held: any[] = [];
  const client = { _client: { getConfig: () => ({ fetch: async (request: Request) => {
    requests.push({ url: request.url, body: await request.json() });
  } }) } };
  const f = await fixture({ client, serverUrl: new URL("http://localhost:4196"),
    sendAndWaitResponse: async (command: any) => {
      held.push(command.openCodeHook);
      return { response: { directive: command.openCodeHook.hook_event_name === "PermissionRequest"
        ? { type: "allow" } : { type: "answer", text: "synthetic answer" } } };
    } });
  await f.start();
  await f.emit("permission.asked", { id: "permission-fixture", sessionID: "native-A", permission: "read", patterns: ["synthetic"] });
  await f.emit("question.asked", { id: "question-fixture", sessionID: "native-A", questions: [{ question: "Synthetic?", options: ["yes"] }] });
  await Promise.resolve(); await Promise.resolve();
  expect(held.map(x => x.hook_event_name)).toEqual(["PermissionRequest", "QuestionAsked"]);
  expect(held.every(x => x.terminal_tty === "/dev/ttys001" && x.terminal_session_id === undefined)).toBe(true);
  expect(requests).toEqual([
    { url: "http://localhost:4196/permission/permission-fixture/reply", body: { reply: "once" } },
    { url: "http://localhost:4196/question/question-fixture/reply", body: { answers: [["synthetic answer"]] } },
  ]);
});
