import Foundation
import Testing
@testable import OpenIslandCore

struct HermesHooksTests {
    @Test func ghosttyRejectsInheritedGenericSessionIDsWithoutLosingRealTTY() throws {
        let raw = #"{"hook_event_name":"pre_llm_call","session_id":"s","cwd":"/tmp/project","extra":{"turn_id":"t"}}"#
        let value = try #require(try HermesHookAdapter.decode(Data(raw.utf8), profileID: "default",
            environment: ["TERM_PROGRAM": "ghostty", "TERM_SESSION_ID": "foreign-shell", "ITERM_SESSION_ID": "inherited-tab"],
            ttyProvider: { "/dev/ttys002" }, ghosttyBindingProvider: { _, _, _, _, _ in nil }))
        #expect(value.terminalApp == "Ghostty")
        #expect(value.terminalSessionID == nil)
        #expect(value.terminalTTY == "/dev/ttys002")
    }
    @Test func ghosttyIntakeUsesHermesNamespaceAndNeverCapturesAtCompletionOrFromSubagents() throws {
        var events: [GhosttySourceEvent] = []
        let provider: GhosttySourceBindingProvider = { agent, session, tty, cwd, event in
            #expect(agent == "hermes" && session == "source" && tty == "/dev/ttys002" && cwd == "/tmp")
            events.append(event)
            return GhosttySourceBinding(sessionID: "native-surface", workingDirectory: cwd, title: nil, capturedAt: .now)
        }
        for (name, platform, parent) in [("pre_llm_call", "cli", ""), ("on_session_end", "cli", ""),
            ("pre_llm_call", "gateway", ""), ("pre_llm_call", "cli", "parent")] {
            let raw = "{\"hook_event_name\":\"\(name)\",\"session_id\":\"source\",\"cwd\":\"/tmp\",\"extra\":{\"turn_id\":\"turn\",\"platform\":\"\(platform)\",\"parent_session_id\":\"\(parent)\",\"completed\":true}}"
            let payload = try #require(try HermesHookAdapter.decode(Data(raw.utf8), profileID: "fixture",
                environment: ["TERM_PROGRAM": "ghostty", "TERM_SESSION_ID": "foreign"],
                ttyProvider: { "/dev/ttys002" }, ghosttyBindingProvider: provider))
            #expect(payload.terminalSessionID == "native-surface")
        }
        #expect(events == [.userSubmit, .background, .background, .background])
    }
    @Test func adapterDoesNotForwardContentAndNeverInfersSuccessFromPostLLM() throws {
        let raw = #"{"hook_event_name":"pre_llm_call","session_id":"s","cwd":"/tmp/project","profile":"default","tool_input":{"secret":"private"},"extra":{"turn_id":"t","user_message":"secret","conversation_history":["secret"]}}"#
        let value = try #require(try HermesHookAdapter.decode(Data(raw.utf8), profileID: "profile-path",
            environment: ["TERM_PROGRAM": "iTerm.app", "ITERM_SESSION_ID": "real-tab"], ttyProvider: { "/dev/ttys003" }))
        #expect(value.event == .turnStarted)
        #expect(value.profileID == "profile-path")
        #expect(value.terminalTTY == "/dev/ttys003")
        #expect(value.terminalSessionID == "real-tab")
        let output = try BridgeCodec.encodeLine(.command(.processRuntimeLifecycleHook(value)))
        #expect(!String(decoding: output, as: UTF8.self).contains("secret"))
        let post = raw.replacingOccurrences(of: "pre_llm_call", with: "post_llm_call")
        #expect(try HermesHookAdapter.decode(Data(post.utf8), profileID: "p") == nil)
    }
    @Test func explicitFinalResultAndMissingTurn() throws {
        for (fields, expected) in [("\"completed\":true", RuntimeLifecycleHookPayload.Event.turnCompleted),
            ("\"completed\":true,\"failed\":true", .turnFailed),
            ("\"completed\":true,\"interrupted\":true", .turnInterrupted), ("\"completed\":false", .turnFailed)] {
            let raw = "{\"hook_event_name\":\"on_session_end\",\"session_id\":\"s\",\"cwd\":\"/tmp\",\"extra\":{\"turn_id\":\"t\",\(fields)}}"
            #expect(try HermesHookAdapter.decode(Data(raw.utf8), profileID: "p", ttyProvider: { nil })?.event == expected)
        }
        let raw = #"{"hook_event_name":"on_session_end","session_id":"s","extra":{"interrupted":true}}"#
        #expect(try HermesHookAdapter.decode(Data(raw.utf8), profileID: "p") == nil)
    }
    @Test func coarseReasonRemovesDiagnosticBodyAndUnknownReason() {
        #expect(HermesHookAdapter.coarseReason("local_processing_error(private input)" ) == "local_processing_error")
        #expect(HermesHookAdapter.coarseReason("text_response(stop)") == "text_response")
        #expect(HermesHookAdapter.coarseReason("private user input") == nil)
    }
    private var pythonURL: URL { HermesHookInstallationManager.defaultPythonURL }
    @Test func configInstallConsentAndUninstallPreserveOtherItems() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hermes-config-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manager = HermesHookInstallationManager(profileDirectory: root, pythonURL: pythonURL)
        let original = "# keep this comment\nmodel: custom\nmax_turns: 99\nhooks:\n  pre_llm_call:\n    - command: user-script\n      timeout: 12\n  outbound:\n    enabled: false\nother: untouched # retain comment\n"
        try Data(original.utf8).write(to: manager.configURL)
        let binary = root.appendingPathComponent("hook binary's")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let status = try manager.install(hooksBinaryURL: binary)
        #expect(status.isInstalled && status.isCurrent && !status.hasConsent)
        let config = try String(contentsOf: manager.configURL, encoding: .utf8)
        #expect(config.contains("# keep this comment\nmodel: custom\nmax_turns: 99\n"))
        #expect(config.contains("other: untouched # retain comment"))
        #expect(config.contains("user-script"))
        #expect(config.contains("outbound:"))
        #expect(!config.contains("hooks_auto_accept"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("shell-hooks-allowlist.json").path))
        #expect(try manager.install(hooksBinaryURL: binary).isInstalled)
        #expect(try String(contentsOf: manager.configURL, encoding: .utf8) == config)
        let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manager.manifestURL)) as? [String: Any])
        let command = try #require(manifest["command"] as? String)
        let approvals: [[String: String]] = ["pre_llm_call", "on_session_end"].map { ["event": $0, "command": command] }
        let allowlist = root.appendingPathComponent("shell-hooks-allowlist.json")
        let consent = try JSONSerialization.data(withJSONObject: ["approvals": approvals])
        try consent.write(to: allowlist)
        #expect(try manager.status().hasConsent)
        #expect(try manager.uninstall().isInstalled == false)
        let removed = try String(contentsOf: manager.configURL, encoding: .utf8)
        #expect(removed.contains("user-script") && removed.contains("other: untouched # retain comment"))
        #expect(!removed.contains("--source hermes"))
        #expect(try Data(contentsOf: allowlist) == consent)
    }
    @Test func invalidConfigAndMissingPythonLeaveConfigUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hermes-invalid-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manager = HermesHookInstallationManager(profileDirectory: root, pythonURL: pythonURL)
        let original = Data("model: a\nmodel: b\n".utf8)
        try original.write(to: manager.configURL)
        #expect(throws: (any Error).self) { try manager.status() }
        #expect(try Data(contentsOf: manager.configURL) == original)
        let missing = HermesHookInstallationManager(profileDirectory: root, pythonURL: root.appendingPathComponent("missing"))
        #expect(throws: HermesHookInstallationError.unavailablePython) { try missing.status() }
    }
}
