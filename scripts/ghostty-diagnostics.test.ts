import { test, expect } from "bun:test";
import { mkdtempSync, writeFileSync, readFileSync, chmodSync, existsSync, rmSync, symlinkSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import callback, { ghosttyIDHash, piDiagnostic, readGhosttySnapshot, writeGhosttyDiagnostic } from "../Sources/OpenIslandApp/Resources/open-island-pi.ts";

test("private marker, safe log and cap govern TS diagnostic admission", () => {
  const directory = mkdtempSync(join(tmpdir(), "ghostty-trace-fixture-"));
  const marker = join(directory, ".ghostty-diagnostics-enabled"), log = join(directory, "ghostty-diagnostics.jsonl");
  const record = piDiagnostic("piCapture", "noUI", { event: "private", prompt: "private", hasUI: false }, "abc", "abc");
  try {
    writeGhosttyDiagnostic(record, directory); expect(existsSync(log)).toBe(false);
    writeFileSync(marker, "", { mode: 0o644 });
    writeGhosttyDiagnostic(record, directory); expect(existsSync(log)).toBe(false);
    chmodSync(marker, 0o600); writeFileSync(marker, "nonempty");
    writeGhosttyDiagnostic(record, directory); expect(existsSync(log)).toBe(false);
    writeFileSync(marker, ""); writeGhosttyDiagnostic(record, directory);
    expect(statSync(log).mode & 0o777).toBe(0o600);
    expect(readFileSync(log, "utf8")).not.toContain("private");
    expect(ghosttyIDHash("abc")).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    writeFileSync(log, Buffer.alloc(262_144)); writeGhosttyDiagnostic(record, directory);
    expect(statSync(log).size).toBe(262_144);
    rmSync(log); const sink = join(directory, "fixture"); writeFileSync(sink, "", { mode: 0o600 }); symlinkSync(sink, log);
    writeGhosttyDiagnostic(record, directory); expect(statSync(sink).size).toBe(0);
    rmSync(log); rmSync(marker); symlinkSync(sink, marker);
    writeGhosttyDiagnostic(record, directory); expect(existsSync(log)).toBe(false);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test("fake locator reports bounded failure stages without stderr or running scripts", () => {
  const records: any[] = [], sink = (record: any) => records.push(record);
  const fake = (output: string) => (() => Buffer.from(output)) as any;
  expect(readGhosttySnapshot(sink, fake("diagnostic:focusChanged"))).toBeUndefined();
  expect(records.at(-1).reason).toBe("focusChanged");
  expect(readGhosttySnapshot(sink, fake("private invalid output"))).toBeUndefined();
  expect(records.at(-1).reason).toBe("parseFailed");
  const fail = (() => { throw { status: 1, stderr: "private stderr", message: "private", args: ["private"] }; }) as any;
  expect(readGhosttySnapshot(sink, fail)).toBeUndefined(); expect(records.at(-1).reason).toBe("exitFailed");
  const timeout = (() => { throw { code: "ETIMEDOUT", stderr: "private" }; }) as any;
  readGhosttySnapshot(sink, timeout); expect(records.at(-1).reason).toBe("timeout");
  expect(JSON.stringify(records)).not.toContain("private");
});

test("interactive capture diagnostic distinguishes noUI, source gate, ambiguity and admitted binding", () => {
  const handlers = new Map<string, Function>(), records: any[] = [];
  let reads = 0;
  callback({ on: (name, handler) => handlers.set(name, handler) }, {
    environment: { TERM_PROGRAM: "ghostty" }, getTTY: () => "/dev/ttys001", normalizeDirectory: value => value,
    diagnostic: record => records.push(record), sendCommand: async () => {},
    ghosttySnapshot: () => { reads++; return { frontmost: true, focusedID: "owned", surfaces: [{ id: "owned", cwd: "/tmp/shared", title: "private" }, { id: "other", cwd: "/tmp/shared", title: "private" }] }; },
  });
  const ctx = { cwd: "/tmp/shared", hasUI: false, sessionManager: { getSessionId: () => "private-native" } };
  handlers.get("session_start")!({}, ctx); expect(records.at(-1).reason).toBe("noUI"); expect(reads).toBe(0);
  const ui = { ...ctx, hasUI: true };
  handlers.get("input")!({ source: "rpc", text: "private" }, ui); expect(records.at(-1).reason).toBe("inputSourceRejected"); expect(reads).toBe(0);
  handlers.get("session_start")!({}, ui); expect(records.at(-1).reason).toBe("ambiguousCWD");
  handlers.get("input")!({ source: "interactive", get text() { throw new Error("must not read input"); } }, ui);
  expect(records.at(-1).reason).toBe("bindingAdmitted"); expect(records.at(-1).surfaceIDHash).toBe(ghosttyIDHash("owned"));
  const count = reads; handlers.get("before_agent_start")!({}, ui); expect(reads).toBe(count);
  handlers.get("input")!({ source: "interactive" }, ui); expect(records.at(-1).reason).toBe("bindingReused"); expect(reads).toBe(count);
  handlers.get("session_shutdown")!({ reason: "reload" }, ui);
  expect(JSON.stringify(records)).not.toContain("private"); expect(JSON.stringify(records)).not.toContain("/tmp/shared"); expect(JSON.stringify(records)).not.toContain("/dev/");
});
