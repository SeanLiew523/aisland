import Foundation
import Testing
@testable import OpenIslandCore

struct GhosttySourceBindingTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ghostty-bindings-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func snapshot(_ focused: String, shared: Bool = true) -> GhosttySourceSnapshot {
        .init(frontmostBefore: true, frontmostAfter: true, focusedBefore: focused, focusedAfter: focused,
              surfaces: [.init(id: "A", cwd: "/tmp/shared", title: "alpha")]
                + (shared ? [.init(id: "B", cwd: "/tmp/shared", title: "beta")] : []))
    }

    @Test(arguments: ["claude", "codex", "grok", "gemini"])
    func separateProcessesReuseFirstBindingDespiteBackgroundFocusChanges(agent: String) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var calls = 0
        var focused = "A"
        let store = GhosttySourceBindingStore(directory: directory, snapshotProvider: {
            calls += 1
            return snapshot(focused)
        })
        // Startup cannot choose between sibling surfaces sharing a cwd.
        #expect(store.resolve(agent: agent, sessionID: "sA", tty: "/dev/ttys031", cwd: "/tmp/shared", event: .startup) == nil)
        let first = store.resolve(agent: agent, sessionID: "sA", tty: "/dev/ttys031", cwd: "/tmp/shared", event: .userSubmit)
        #expect(first?.sessionID == "A")
        focused = "B"
        #expect(store.resolve(agent: agent, sessionID: "sB", tty: "/dev/ttys032", cwd: "/tmp/shared", event: .userSubmit)?.sessionID == "B")
        let beforeBackgroundCalls = calls
        // New store instances simulate subsequent independent hook processes.
        let later = GhosttySourceBindingStore(directory: directory, snapshotProvider: {
            calls += 1
            return snapshot("B")
        })
        #expect(later.resolve(agent: agent, sessionID: "sA", tty: "/dev/ttys031", cwd: "/tmp/changed", event: .background)?.sessionID == "A")
        #expect(later.resolve(agent: agent, sessionID: "sB", tty: "/dev/ttys032", cwd: "/tmp/shared", event: .background)?.sessionID == "B")
        #expect(later.resolve(agent: agent, sessionID: "sA", tty: "/dev/ttys031", cwd: "/tmp/shared", event: .userSubmit)?.sessionID == "A")
        #expect(later.resolve(agent: agent, sessionID: "sA", tty: "/dev/ttys099", cwd: "/tmp/shared", event: .background) == nil)
        #expect(later.resolve(agent: "foreign", sessionID: "sA", tty: "/dev/ttys031", cwd: "/tmp/shared", event: .background) == nil)
        #expect(calls == beforeBackgroundCalls)
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(entries.filter { $0.pathExtension == "json" }.count == 2)
        for url in entries {
            #expect((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
    }

    @Test
    func unavailableOrUnstableSourcesCannotCreateReceipt() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var current = snapshot("A", shared: false)
        var calls = 0
        let store = GhosttySourceBindingStore(directory: directory, snapshotProvider: { calls += 1; return current })
        #expect(store.resolve(agent: "grok", sessionID: "s", tty: nil, cwd: "/tmp/shared", event: .userSubmit) == nil)
        #expect(store.resolve(agent: "grok", sessionID: "s", tty: "??", cwd: "/tmp/shared", event: .userSubmit) == nil)
        #expect(store.resolve(agent: "grok", sessionID: "", tty: "/dev/ttys031", cwd: "/tmp/shared", event: .userSubmit) == nil)
        #expect(store.resolve(agent: "grok", sessionID: "s", tty: "/dev/ttys031", cwd: "/tmp/shared", event: .background) == nil)
        #expect(calls == 0)
        current.frontmostAfter = false
        #expect(store.resolve(agent: "grok", sessionID: "s", tty: "/dev/ttys031", cwd: "/tmp/shared", event: .userSubmit) == nil)
        current.frontmostAfter = true
        current.focusedAfter = "B"
        #expect(store.resolve(agent: "grok", sessionID: "s", tty: "/dev/ttys031", cwd: "/tmp/shared", event: .userSubmit) == nil)
        current.focusedAfter = "A"
        #expect(store.resolve(agent: "grok", sessionID: "s", tty: "/dev/ttys031", cwd: "/tmp/foreign", event: .userSubmit) == nil)
        current.surfaces.append(current.surfaces[0])
        #expect(store.resolve(agent: "grok", sessionID: "s", tty: "/dev/ttys031", cwd: "/tmp/shared", event: .userSubmit) == nil)
        current = snapshot("A", shared: false)
        #expect(store.resolve(agent: "grok", sessionID: "s", tty: "/dev/ttys031", cwd: "/tmp/shared", event: .startup)?.sessionID == "A")
    }

    @Test(arguments: ["claude", "codex", "grok", "gemini"])
    func hookAdaptersNeverUseOldFocusedLocatorOrPayloadTTY(agent: String) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var focused = "A"
        var queries = 0
        let store = GhosttySourceBindingStore(directory: directory, snapshotProvider: {
            queries += 1
            return snapshot(focused, shared: agent != "gemini")
        })
        let provider: GhosttySourceBindingProvider = { agent, id, tty, cwd, event in
            store.resolve(agent: agent, sessionID: id, tty: tty, cwd: cwd, event: event)
        }
        let env = ["TERM_PROGRAM": "ghostty"]
        let tty = { Optional("/dev/ttys031") }
        let forbidden: (String) -> (sessionID: String?, tty: String?, title: String?) = { _ in
            Issue.record("Old focused locator must not run for Ghostty")
            return ("foreign", nil, "foreign")
        }
        func run(_ stage: Int) -> (String?, String?) {
            switch agent {
            case "claude":
                let result = ClaudeHookPayload(cwd: "/tmp/shared", hookEventName: stage == 0 ? .userPromptSubmit : stage == 1 ? .notification : .stop,
                    sessionID: "s", terminalSessionID: "foreign", terminalTTY: "/dev/ttys099")
                    .withRuntimeContext(environment: env, currentTTYProvider: tty, terminalLocatorProvider: forbidden, ghosttyBindingProvider: provider)
                return (result.terminalSessionID, result.terminalTTY)
            case "codex":
                let result = CodexHookPayload(cwd: "/tmp/shared", hookEventName: stage == 0 ? .userPromptSubmit : stage == 1 ? .postToolUse : .stop,
                    model: "test", permissionMode: .default, sessionID: "s", terminalSessionID: "foreign", terminalTTY: "/dev/ttys099", transcriptPath: nil)
                    .withRuntimeContext(environment: env, currentTTYProvider: tty, terminalLocatorProvider: forbidden, ghosttyBindingProvider: provider)
                return (result.terminalSessionID, result.terminalTTY)
            case "grok":
                let result = GrokHookPayload(cwd: "/tmp/shared", hookEventName: stage == 0 ? .userPromptSubmit : stage == 1 ? .notification : .stop,
                    sessionID: "s", terminalSessionID: "foreign", terminalTTY: "/dev/ttys099")
                    .withRuntimeContext(environment: env, currentTTYProvider: tty, terminalLocatorProvider: forbidden, ghosttyBindingProvider: provider)
                return (result.terminalSessionID, result.terminalTTY)
            default:
                let result = GeminiHookPayload(cwd: "/tmp/shared", hookEventName: stage == 0 ? .sessionStart : stage == 1 ? .notification : .beforeAgent,
                    sessionID: "s", terminalSessionID: "foreign", terminalTTY: "/dev/ttys099")
                    .withRuntimeContext(environment: env, currentTTYProvider: tty, terminalLocatorProvider: forbidden, ghosttyBindingProvider: provider)
                return (result.terminalSessionID, result.terminalTTY)
            }
        }
        #expect(run(0).0 == "A")
        focused = "B"
        #expect(run(1).0 == "A")
        #expect(run(2).0 == "A")
        #expect(run(2).1 == "/dev/ttys031")
        #expect(queries == 1)
    }

    @Test
    func geminiBeforeAgentAndNotificationCannotBindSharedDirectory() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var calls = 0
        let store = GhosttySourceBindingStore(directory: directory, snapshotProvider: { calls += 1; return snapshot("B") })
        for event in [GeminiHookEventName.beforeAgent, .notification, .afterAgent, .sessionEnd] {
            let payload = GeminiHookPayload(cwd: "/tmp/shared", hookEventName: event, sessionID: "s", terminalSessionID: "foreign")
                .withRuntimeContext(environment: ["TERM_PROGRAM": "ghostty"], currentTTYProvider: { "/dev/ttys031" },
                    terminalLocatorProvider: { _ in Issue.record("Unexpected locator"); return (nil, nil, nil) },
                    ghosttyBindingProvider: { store.resolve(agent: $0, sessionID: $1, tty: $2, cwd: $3, event: $4) })
            #expect(payload.terminalSessionID == nil)
        }
        #expect(calls == 0)
    }

    @Test
    func staleCorruptAndSymlinkReceiptsFailWithoutFocusedLookup() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GhosttySourceBindingStore(directory: directory, snapshotProvider: { snapshot("A", shared: false) })
        #expect(store.resolve(agent: "claude", sessionID: "s", tty: "/dev/ttys031", cwd: "/tmp/shared", event: .startup)?.sessionID == "A")
        let receipt = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.pathExtension == "json" })
        let later = GhosttySourceBindingStore(directory: directory, snapshotProvider: {
            Issue.record("Invalid receipt must never trigger focused lookup")
            return snapshot("B")
        })
        let stale = GhosttySourceBinding(sessionID: "A", workingDirectory: "/tmp/shared", title: "alpha", capturedAt: Date().addingTimeInterval(-25 * 60 * 60))
        try JSONEncoder().encode(stale).write(to: receipt)
        #expect(later.resolve(agent: "claude", sessionID: "s", tty: "/dev/ttys031", cwd: "/tmp/shared", event: .background) == nil)
        try Data(repeating: 65, count: 16_385).write(to: receipt)
        #expect(later.resolve(agent: "claude", sessionID: "s", tty: "/dev/ttys031", cwd: "/tmp/shared", event: .userSubmit) == nil)
        try Data("corrupt".utf8).write(to: receipt)
        #expect(later.resolve(agent: "claude", sessionID: "s", tty: "/dev/ttys031", cwd: "/tmp/shared", event: .background) == nil)
        let outside = directory.appendingPathComponent("outside")
        try Data("foreign".utf8).write(to: outside)
        try FileManager.default.removeItem(at: receipt)
        try FileManager.default.createSymbolicLink(at: receipt, withDestinationURL: outside)
        #expect(later.resolve(agent: "claude", sessionID: "s", tty: "/dev/ttys031", cwd: "/tmp/shared", event: .userSubmit) == nil)
        #expect(try String(contentsOf: outside, encoding: .utf8) == "foreign")
    }

    @Test
    func agedReceiptCanRefreshSameSourceButCannotSwitchToForeignSurface() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        var focused = "A"
        var calls = 0
        let store = GhosttySourceBindingStore(directory: directory, snapshotProvider: {
            calls += 1
            return snapshot(focused)
        }, now: { currentDate })
        #expect(store.resolve(agent: "grok", sessionID: "s", tty: "/dev/ttys031", cwd: "/tmp/shared", event: .userSubmit)?.sessionID == "A")
        currentDate = currentDate.addingTimeInterval(25 * 60 * 60)
        focused = "B"
        #expect(store.resolve(agent: "grok", sessionID: "s", tty: "/dev/ttys031", cwd: "/tmp/shared", event: .background) == nil)
        #expect(calls == 1)
        #expect(store.resolve(agent: "grok", sessionID: "s", tty: "/dev/ttys031", cwd: "/tmp/shared", event: .userSubmit) == nil)
        focused = "A"
        #expect(store.resolve(agent: "grok", sessionID: "s", tty: "/dev/ttys031", cwd: "/tmp/shared", event: .userSubmit)?.sessionID == "A")
        focused = "B"
        #expect(store.resolve(agent: "grok", sessionID: "s", tty: "/dev/ttys031", cwd: "/tmp/shared", event: .background)?.sessionID == "A")
        #expect(calls == 3)
    }

    @Test
    func locatorRejectsMalformedMetadataAndCannotMutateTerminal() {
        #expect(GhosttySourceLocator.parse("A\nA\u{1f}/tmp/shared\u{1f}alpha\n")?.surfaces.count == 1)
        #expect(GhosttySourceLocator.parse("A\nmalformed") == nil)
        #expect(GhosttySourceLocator.parse("") == nil)
        #expect(GhosttySourceLocator.script.contains("if not frontmost then return"))
        #expect(GhosttySourceLocator.script.contains("if firstID is not lastID then return"))
        #expect(!GhosttySourceLocator.script.contains("activate"))
        #expect(!GhosttySourceLocator.script.contains("set name"))
    }
}
