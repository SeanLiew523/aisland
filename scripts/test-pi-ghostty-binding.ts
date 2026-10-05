import { test, expect } from "bun:test";
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import callback, { admitGhosttyBinding, parseGhosttySnapshot } from "../Sources/OpenIslandApp/Resources/open-island-pi.ts";
const surfaces = [{ id: "A", cwd: "/tmp/shared", title: "first" }, { id: "B", cwd: "/tmp/shared", title: "second" }];
const snapshot = (focusedID = "A", frontmost = true) => ({ frontmost, focusedID, surfaces });
const normalize = (value: string) => value;

test("locator rejects unavailable, foreign, duplicate, background, wrong cwd and malformed snapshots", () => {
  expect(admitGhosttyBinding(undefined, "/tmp/shared", normalize, true)).toBeUndefined();
  expect(admitGhosttyBinding(snapshot("foreign"), "/tmp/shared", normalize, true)).toBeUndefined();
  expect(admitGhosttyBinding(snapshot("A", false), "/tmp/shared", normalize, true)).toBeUndefined();
  expect(admitGhosttyBinding(snapshot(), "/another", normalize, true)).toBeUndefined();
  expect(admitGhosttyBinding(snapshot(), "/another", normalize, false, true)).toBeUndefined();
  expect(admitGhosttyBinding({ ...snapshot(), surfaces: [surfaces[0], { ...surfaces[1], id: "" }] }, "/another", normalize, true, true)).toBeUndefined();
  expect(admitGhosttyBinding({ ...snapshot(), surfaces: [surfaces[0], surfaces[0]] }, "/tmp/shared", normalize, true)).toBeUndefined();
  expect(admitGhosttyBinding(snapshot(), "/tmp/shared", normalize)).toBeUndefined();
  expect(admitGhosttyBinding(snapshot(), "/tmp/shared", normalize, true)?.id).toBe("A");
  expect(parseGhosttySnapshot("focused\x1fA\nA\x1f/tmp/shared\x1ffirst\n")?.focusedID).toBe("A");
  expect(parseGhosttySnapshot("focused\x1fA\nmalformed\n")).toBeUndefined();
});

for (const agent of ["pi", "oh-my-pi"]) {
  test(`${agent}: shared cwd interactive inputs bind separate sessions, later focus never rewrites them`, async () => {
    const directory = mkdtempSync(join(tmpdir(), "aisland-pi-ghostty-fixture-"));
    try {
      const source = readFileSync(new URL("../Sources/OpenIslandApp/Resources/open-island-pi.ts", import.meta.url), "utf8").replaceAll("__OPEN_ISLAND_PI_SOURCE__", agent);
      const path = join(directory, "extension.ts"); writeFileSync(path, source);
      const { default: extension } = await import(path);
      let focusedID = "A", reads = 0;
      const build = (id: string) => {
        const handlers = new Map<string, Function>(), sent: any[] = [];
        const ctx = { cwd: "/tmp/shared", hasUI: true, sessionManager: { getSessionId: () => id } };
        extension({ on: (name: string, handler: Function) => handlers.set(name, handler) }, {
          diagnostic: () => {},
          environment: { TERM_PROGRAM: "ghostty", TERM_SESSION_ID: "foreign-terminal-id", GHOSTTY_SURFACE_ID: "unsupported-id" },
          getTTY: () => "/dev/synthetic", normalizeDirectory: normalize, heartbeatIntervalMs: 5,
          ghosttySnapshot: () => { reads++; return snapshot(focusedID); },
          sendCommand: async (command: unknown) => { sent.push(command); },
        });
        return { handlers, sent, ctx, emit: (name: string, event = {}, context = ctx) => handlers.get(name)!(event, context) };
      };
      const a = build("session-A"), b = build("session-B");
      a.emit("session_start"); b.emit("session_start");
      expect(a.sent[0].piHook.terminal_session_id).toBeUndefined();
      expect(b.sent[0].piHook.terminal_session_id).toBeUndefined();
      const before = reads;
      a.emit("input", { source: "rpc" }); a.emit("input", { source: "extension" });
      a.emit("input", { source: "interactive" }, { ...a.ctx, hasUI: false });
      a.emit("before_agent_start"); expect(reads).toBe(before);
      a.emit("input", { source: "interactive", get text() { throw new Error("locator must not read input text"); } });
      focusedID = "B"; b.emit("input", { source: "interactive" });
      const boundReads = reads;
      focusedID = "foreign";
      a.emit("before_agent_start"); b.emit("before_agent_start");
      a.emit("tool_execution_start"); b.emit("tool_execution_end");
      a.emit(agent === "pi" ? "agent_settled" : "session_stop");
      b.emit(agent === "pi" ? "agent_settled" : "session_stop");
      await new Promise(resolve => setTimeout(resolve, 20));
      expect(a.sent.filter(value => value.piHook.hook_event_name === "Heartbeat").every(value => value.piHook.terminal_session_id === "A")).toBe(true);
      expect(b.sent.filter(value => value.piHook.hook_event_name === "Heartbeat").every(value => value.piHook.terminal_session_id === "B")).toBe(true);
      expect(a.sent.some(value => value.piHook.hook_event_name === "Heartbeat")).toBe(true);
      expect(reads).toBe(boundReads);
      expect(a.sent.at(-1).piHook.terminal_session_id).toBe("A");
      expect(a.sent.at(-1).piHook.terminal_title).toBe("first");
      expect(b.sent.at(-1).piHook.terminal_session_id).toBe("B");
      expect(b.sent.at(-1).piHook.terminal_title).toBe("second");
      a.emit("session_shutdown", { reason: "reload" }); b.emit("session_shutdown", { reason: "reload" });
    } finally { rmSync(directory, { recursive: true, force: true }); }
  });
}

test("unique cwd startup binds only UI source; plain before_agent_start cannot capture", () => {
  const handlers = new Map<string, Function>(), sent: any[] = []; let reads = 0;
  callback({ on: (name, handler) => handlers.set(name, handler) }, {
    diagnostic: () => {},
    environment: { TERM_PROGRAM: "ghostty", TERM_SESSION_ID: "foreign" }, getTTY: () => undefined,
    normalizeDirectory: normalize, ghosttySnapshot: () => { reads++; return { ...snapshot(), surfaces: [surfaces[0]] }; },
    sendCommand: async command => { sent.push(command); },
  });
  const ctx = { cwd: "/tmp/shared", hasUI: false, sessionManager: { getSessionId: () => "fixture" } };
  handlers.get("before_agent_start")!({}, ctx); expect(reads).toBe(0);
  handlers.get("session_start")!({}, { ...ctx, hasUI: true });
  expect(sent.at(-1).piHook.terminal_session_id).toBe("A");
  handlers.get("session_shutdown")!({ reason: "reload" }, ctx);
});


test("authoritative non-Ghostty terminal rejects inherited Ghostty markers", () => {
  const handlers = new Map<string, Function>(), sent: any[] = [];
  callback({ on: (name, handler) => handlers.set(name, handler) }, {
    diagnostic: () => {},
    environment: { TERM_PROGRAM: "Apple_Terminal", GHOSTTY_RESOURCES_DIR: "/synthetic/inherited", TERM_SESSION_ID: "terminal-session" },
    getTTY: () => undefined, normalizeDirectory: normalize,
    ghosttySnapshot: () => { throw new Error("must not query unrelated Ghostty"); },
    sendCommand: async command => { sent.push(command); },
  });
  const ctx = { cwd: "/tmp/shared", hasUI: true, sessionManager: { getSessionId: () => "fixture" } };
  handlers.get("session_start")!({}, ctx);
  expect(sent.at(-1).piHook.terminal_app).toBe("Terminal");
  expect(sent.at(-1).piHook.terminal_session_id).toBe("terminal-session");
  handlers.get("session_shutdown")!({ reason: "reload" }, ctx);
});


test("interactive real-PTY source binds when its agent cwd differs from shell OSC cwd and stays pinned after cd", () => {
  const handlers = new Map<string, Function>(), sent: any[] = []; let reads = 0, focusedID = "A";
  callback({ on: (name, handler) => handlers.set(name, handler) }, {
    diagnostic: () => {}, environment: { TERM_PROGRAM: "ghostty" }, getTTY: () => "/dev/ttys001",
    normalizeDirectory: normalize, ghosttySnapshot: () => { reads++; return snapshot(focusedID); },
    sendCommand: async command => { sent.push(command); },
  });
  const ctx = { cwd: "/tmp/agent-cwd", hasUI: true, sessionManager: { getSessionId: () => "ordinary" } };
  handlers.get("session_start")!({}, ctx);
  expect(sent.at(-1).piHook.terminal_session_id).toBeUndefined();
  const startupReads = reads;
  handlers.get("input")!({ source: "rpc" }, ctx);
  expect(reads).toBe(startupReads);
  handlers.get("input")!({ source: "interactive" }, ctx);
  handlers.get("tool_execution_start")!({}, ctx);
  expect(sent.at(-1).piHook.terminal_session_id).toBe("A");
  const pinnedReads = reads; focusedID = "B";
  const moved = { ...ctx, cwd: "/tmp/changed" };
  handlers.get("input")!({ source: "interactive" }, moved);
  handlers.get("tool_execution_start")!({}, moved);
  expect(sent.at(-1).piHook.terminal_session_id).toBe("A");
  expect(sent.at(-1).piHook.cwd).toBe("/tmp/changed");
  expect(reads).toBe(pinnedReads);
  handlers.get("session_shutdown")!({ reason: "reload" }, moved);
});
