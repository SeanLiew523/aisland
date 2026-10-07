import Foundation

/// Grok also dispatches its native envelope to Claude/Cursor compatibility
/// commands. Those AIsland callbacks must leave the native Grok hook in charge.
/// Environment markers alone are never evidence: real child agents inherit them.
public enum GrokCompatibilityHookProvenance {
    private static let compatibilitySources: Set<String> = [
        "claude", "qoder", "qwen", "factory", "droid", "codebuddy", "kimi",
        "zcode", "workbuddy", "cursor"
    ]

    public static func shouldSuppress(
        input: Data, declaredSource: String, environment: [String: String]
    ) -> Bool {
        guard compatibilitySources.contains(declaredSource),
              let identity = try? JSONDecoder().decode(EnvelopeIdentity.self, from: input),
              !identity.sessionID.isEmpty, identity.sessionID == identity.claudeSessionID,
              identity.cwd.hasPrefix("/"), identity.workspaceRoot.hasPrefix("/"),
              !identity.timestamp.isEmpty,
              let event = GrokHookEventName(rawValue: identity.claudeEvent),
              identity.nativeEvent == nativeEventName(event),
              environment["GROK_HOOK_EVENT"] == identity.nativeEvent,
              environment["GROK_SESSION_ID"] == identity.sessionID,
              environment["GROK_WORKSPACE_ROOT"] == identity.workspaceRoot else {
            return false
        }
        return true
    }

    private static func nativeEventName(_ event: GrokHookEventName) -> String {
        // Official HookEventEnvelope::to_hook_json keeps the native snake_case
        // event and adds a separate Claude PascalCase alias, including Stop.
        event.rawValue.enumerated().map { index, character in
            (character.isUppercase && index > 0 ? "_" : "") + character.lowercased()
        }.joined()
    }

    /// Decode identity fields only. Prompt/tool/result contents are neither
    /// inspected nor logged by source admission.
    private struct EnvelopeIdentity: Decodable {
        var nativeEvent: String
        var claudeEvent: String
        var sessionID: String
        var claudeSessionID: String
        var cwd: String
        var workspaceRoot: String
        var timestamp: String

        enum CodingKeys: String, CodingKey {
            case nativeEvent = "hookEventName"
            case claudeEvent = "hook_event_name"
            case sessionID = "sessionId"
            case claudeSessionID = "session_id"
            case cwd, workspaceRoot, timestamp
        }
    }
}
