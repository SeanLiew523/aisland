import Foundation
import Testing
@testable import OpenIslandCore

struct GrokGhosttyRuntimeContextTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("grok-ghostty-contract-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func snapshot(focused: String, surfaces: [(String, String)]) -> GhosttySourceSnapshot {
        .init(frontmostBefore: true, frontmostAfter: true, focusedBefore: focused, focusedAfter: focused,
              surfaces: surfaces.map { .init(id: $0.0, cwd: $0.1, title: "fixture") })
    }
    private func enrich(
        _ event: GrokHookEventName, session: String = "grok-source", tty: String? = "/dev/ttys031",
        cwd: String = "/tmp/shared", provider: GhosttySourceBindingProvider
    ) -> GrokHookPayload {
        GrokHookPayload(cwd: cwd, hookEventName: event, sessionID: session,
                        terminalSessionID: "foreign-payload-id", terminalTTY: "/dev/ttys099")
            .withRuntimeContext(environment: ["TERM_PROGRAM": "ghostty"], currentTTYProvider: { tty },
                terminalLocatorProvider: { _ in
                    Issue.record("Legacy focused locator must not run")
                    return ("foreign", nil, "foreign")
                }, ghosttyBindingProvider: provider)
    }

    @Test
    func unboundSubmitCannotClaimSiblingPageInSharedDirectory() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var focused = "A"
        var queries = 0
        var policies: [GhosttySourceEvent] = []
        let store = GhosttySourceBindingStore(directory: directory, snapshotProvider: {
            queries += 1
            return snapshot(focused: focused, surfaces: [("A", "/tmp/shared"), ("B", "/tmp/shared")])
        })
        let provider: GhosttySourceBindingProvider = { agent, id, tty, cwd, policy in
            policies.append(policy)
            return store.resolve(agent: agent, sessionID: id, tty: tty, cwd: cwd, event: policy)
        }
        // Automatic wakeups and typed prompts have the same official envelope;
        // neither provides interactive origin evidence in this situation.
        for event in [GrokHookEventName.sessionStart, .userPromptSubmit] {
            #expect(enrich(event, session: "source-A", provider: provider).terminalSessionID == nil)
            focused = "B"
            #expect(enrich(event, session: "source-B", tty: "/dev/ttys032", provider: provider).terminalSessionID == nil)
        }
        #expect(policies.allSatisfy { $0 == .startup })
        #expect(queries == 4)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(!files.contains { $0.pathExtension == "json" })
    }

    @Test
    func uniqueSubmitCanRecoverBindingAndLaterEventsNeverReplaceIt() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var surfaces = [("A", "/tmp/shared")]
        var focused = "A"
        var queries = 0
        let store = GhosttySourceBindingStore(directory: directory, snapshotProvider: {
            queries += 1
            return snapshot(focused: focused, surfaces: surfaces)
        })
        let provider: GhosttySourceBindingProvider = { store.resolve(agent: $0, sessionID: $1, tty: $2, cwd: $3, event: $4) }
        #expect(enrich(.userPromptSubmit, provider: provider).terminalSessionID == "A")
        surfaces.append(("B", "/tmp/shared"))
        focused = "B"
        for event in [GrokHookEventName.userPromptSubmit, .preToolUse, .postToolUse, .stop, .notification, .sessionEnd] {
            let result = enrich(event, provider: provider)
            #expect(result.terminalSessionID == "A")
            #expect(result.terminalTTY == "/dev/ttys031")
        }
        #expect(queries == 1)
    }

    @Test
    func twoAdmittedSourcesStayDistinctWhenDirectoriesConvergeAndPromptsInterleave() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var surfaces = [("A", "/tmp/project-A"), ("B", "/tmp/project-B")]
        var focused = "A"
        var queries = 0
        let store = GhosttySourceBindingStore(directory: directory, snapshotProvider: {
            queries += 1
            return snapshot(focused: focused, surfaces: surfaces)
        })
        let provider: GhosttySourceBindingProvider = { store.resolve(agent: $0, sessionID: $1, tty: $2, cwd: $3, event: $4) }
        #expect(enrich(.sessionStart, session: "source-A", cwd: "/tmp/project-A", provider: provider).terminalSessionID == "A")
        focused = "B"
        #expect(enrich(.sessionStart, session: "source-B", tty: "/dev/ttys032", cwd: "/tmp/project-B", provider: provider).terminalSessionID == "B")
        surfaces = [("A", "/tmp/shared"), ("B", "/tmp/shared")]
        for event in [GrokHookEventName.userPromptSubmit, .postToolUse, .stop, .notification] {
            focused = "B"
            #expect(enrich(event, session: "source-A", provider: provider).terminalSessionID == "A")
            focused = "A"
            #expect(enrich(event, session: "source-B", tty: "/dev/ttys032", provider: provider).terminalSessionID == "B")
        }
        #expect(queries == 2)
    }

    @Test
    func backgroundOrMissingTTYCannotCreateBinding() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var queries = 0
        let store = GhosttySourceBindingStore(directory: directory, snapshotProvider: {
            queries += 1
            return snapshot(focused: "A", surfaces: [("A", "/tmp/shared")])
        })
        let provider: GhosttySourceBindingProvider = { store.resolve(agent: $0, sessionID: $1, tty: $2, cwd: $3, event: $4) }
        for event in [GrokHookEventName.notification, .preToolUse, .stop, .subagentStop] {
            #expect(enrich(event, provider: provider).terminalSessionID == nil)
        }
        #expect(enrich(.userPromptSubmit, tty: nil, provider: provider).terminalSessionID == nil)
        #expect(queries == 0)
    }
}
