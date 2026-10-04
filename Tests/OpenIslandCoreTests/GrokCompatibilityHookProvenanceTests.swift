import Foundation
import Testing
@testable import OpenIslandCore

struct GrokCompatibilityHookProvenanceTests {
    private let environment = [
        "GROK_HOOK_EVENT": "session_start",
        "GROK_SESSION_ID": "grok-fixture-session",
        "GROK_WORKSPACE_ROOT": "/fixture/project"
    ]
    private func envelope(event: GrokHookEventName = .sessionStart) -> [String: Any] {
        // Literal official wire names keep fixtures independent of the
        // production PascalCase→snake_case conversion.
        let wireNames: [GrokHookEventName: String] = [
            .sessionStart: "session_start", .sessionEnd: "session_end",
            .userPromptSubmit: "user_prompt_submit", .preToolUse: "pre_tool_use",
            .postToolUse: "post_tool_use", .postToolUseFailure: "post_tool_use_failure",
            .stop: "stop", .stopFailure: "stop_failure", .stopCancelled: "stop_cancelled",
            .notification: "notification", .subagentStart: "subagent_start",
            .subagentStop: "subagent_stop", .preCompact: "pre_compact",
            .postCompact: "post_compact", .permissionDenied: "permission_denied"
        ]
        let native = wireNames[event] ?? "unsupported"
        return ["hookEventName": native, "hook_event_name": event.rawValue,
                "sessionId": "grok-fixture-session", "session_id": "grok-fixture-session",
                "cwd": "/fixture/project/nested", "workspaceRoot": "/fixture/project",
                "timestamp": "2026-10-04T12:00:00Z"]
    }
    private func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    @Test(arguments: ["claude", "cursor", "qoder", "qwen", "factory", "droid", "codebuddy", "kimi", "zcode", "workbuddy"])
    func provenGrokEnvelopeSuppressesCompatibilitySources(source: String) throws {
        #expect(GrokCompatibilityHookProvenance.shouldSuppress(input: try data(envelope()), declaredSource: source, environment: environment))
    }

    @Test(arguments: GrokHookEventName.allCases)
    func allNativeLifecycleActivityAndNotificationEventsAreSuppressed(event: GrokHookEventName) throws {
        let object = envelope(event: event)
        var markers = environment
        markers["GROK_HOOK_EVENT"] = object["hookEventName"] as? String
        #expect(GrokCompatibilityHookProvenance.shouldSuppress(input: try data(object), declaredSource: "claude", environment: markers))
        #expect(GrokCompatibilityHookProvenance.shouldSuppress(input: try data(object), declaredSource: "cursor", environment: markers))
    }

    @Test(arguments: ["grok", "codex", "gemini", "hermes", "unknown", ""])
    func nativeAndUnrelatedDestinationsAlwaysRemainAdmitted(source: String) throws {
        #expect(!GrokCompatibilityHookProvenance.shouldSuppress(input: try data(envelope()), declaredSource: source, environment: environment))
    }

    @Test
    func genuineClaudeAndCursorChildrenRemainAdmittedWithInheritedGrokMarkers() throws {
        let claude: [String: Any] = ["hook_event_name": "SessionStart", "session_id": "claude-child-session", "cwd": "/fixture/project", "source": "startup"]
        let cursor: [String: Any] = ["hook_event_name": "beforeSubmitPrompt", "conversation_id": "cursor-child-session", "generation_id": "cursor-turn", "workspace_roots": ["/fixture/project"]]
        for object in [claude, cursor] {
            for source in ["claude", "cursor"] {
                #expect(!GrokCompatibilityHookProvenance.shouldSuppress(input: try data(object), declaredSource: source, environment: environment))
            }
        }
        // Even a shared UUID plus inherited markers cannot suppress native
        // Claude schema: the complete Grok envelope is required.
        var reusedIdentity = claude
        reusedIdentity["session_id"] = environment["GROK_SESSION_ID"]
        #expect(!GrokCompatibilityHookProvenance.shouldSuppress(input: try data(reusedIdentity), declaredSource: "claude", environment: environment))
        #expect(try JSONDecoder().decode(ClaudeHookPayload.self, from: data(claude)).sessionID == "claude-child-session")
        #expect(try JSONDecoder().decode(CursorHookPayload.self, from: data(cursor)).conversationId == "cursor-child-session")
    }

    @Test
    func partialMalformedOrConflictingEnvelopeDoesNotGuessSource() throws {
        for key in ["hookEventName", "hook_event_name", "sessionId", "session_id", "cwd", "workspaceRoot", "timestamp"] {
            var object = envelope()
            object.removeValue(forKey: key)
            #expect(!GrokCompatibilityHookProvenance.shouldSuppress(input: try data(object), declaredSource: "claude", environment: environment))
            object[key] = 123
            #expect(!GrokCompatibilityHookProvenance.shouldSuppress(input: try data(object), declaredSource: "claude", environment: environment))
        }
        for (key, value) in [("hookEventName", "notification"), ("hook_event_name", "Unknown"), ("session_id", "other"), ("sessionId", ""), ("cwd", "relative"), ("workspaceRoot", "relative"), ("timestamp", "")] {
            var object = envelope()
            object[key] = value
            #expect(!GrokCompatibilityHookProvenance.shouldSuppress(input: try data(object), declaredSource: "claude", environment: environment))
        }
        for input in [Data(), Data("[]".utf8), Data("{broken".utf8), Data("null".utf8)] {
            #expect(!GrokCompatibilityHookProvenance.shouldSuppress(input: input, declaredSource: "claude", environment: environment))
        }
    }

    @Test
    func absentOrInheritedMismatchedRuntimeMarkersCannotProveGrok() throws {
        for key in environment.keys {
            var markers = environment
            markers.removeValue(forKey: key)
            #expect(!GrokCompatibilityHookProvenance.shouldSuppress(input: try data(envelope()), declaredSource: "claude", environment: markers))
            markers[key] = "other"
            #expect(!GrokCompatibilityHookProvenance.shouldSuppress(input: try data(envelope()), declaredSource: "claude", environment: markers))
        }
        #expect(!GrokCompatibilityHookProvenance.shouldSuppress(input: try data(envelope()), declaredSource: "claude", environment: [:]))
    }

    @Test
    func ingressLeavesOnlyNativeGrokLifecycleAndSkipsCompatibilitySideEffects() throws {
        // Reproduce the same-session Grok→Claude race with a fake bridge and
        // locator. Source admission is the production CLI's first branch.
        var bridgeSources: [String] = []
        var locatorCalls = 0
        var emittedNotifications = 0
        var finalIdentity: String?
        for event in [GrokHookEventName.sessionStart, .userPromptSubmit, .postToolUse, .stop, .notification] {
            let object = envelope(event: event)
            let input = try data(object)
            var markers = environment
            markers["GROK_HOOK_EVENT"] = object["hookEventName"] as? String
            for source in ["grok", "claude", "cursor"] {
                guard !GrokCompatibilityHookProvenance.shouldSuppress(input: input, declaredSource: source, environment: markers) else { continue }
                bridgeSources.append(source)
                locatorCalls += 1
                finalIdentity = source
                if event == .stop { emittedNotifications += 1 }
                #expect(try JSONDecoder().decode(GrokHookPayload.self, from: input).sessionID == "grok-fixture-session")
            }
        }
        #expect(bridgeSources == Array(repeating: "grok", count: 5))
        #expect(locatorCalls == 5)
        #expect(emittedNotifications == 1)
        #expect(finalIdentity == "grok")
    }

    @Test
    func eventSpecificFieldsAndSensitiveContentCannotChangeAdmission() throws {
        var object = envelope()
        object["prompt"] = ["unexpected": ["shape"]]
        object["toolInput"] = ["privateFixture": true]
        object["toolResult"] = [123, 456]
        object["transcriptPath"] = NSNull()
        #expect(GrokCompatibilityHookProvenance.shouldSuppress(input: try data(object), declaredSource: "claude", environment: environment))
    }
}
