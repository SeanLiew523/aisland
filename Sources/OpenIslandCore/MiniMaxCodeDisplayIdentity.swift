import Foundation

/// Conversation identity for list deduplication, independent of workspace/TTY.
public enum MiniMaxCodeDisplayIdentity {
    public static func key(for session: AgentSession) -> String? {
        let source: RuntimeLifecycleHookPayload.Source
        switch session.tool {
        case .minimaxCodeDesktop: source = .minimaxCodeDesktop
        case .minimaxCodeCLI: source = .minimaxCodeCLI
        default: return nil
        }
        if let nativeID = session.jumpTarget?.appConversationID, valid(nativeID, maximum: 512),
           let profile = session.jumpTarget?.runtimeProfileID, valid(profile, maximum: 1024) {
            // Native IDs and profile keys are case-sensitive. Length prefixes
            // keep delimiters inside a profile/native ID from colliding.
            return "minimax:\(source.rawValue):native:\(profile.utf8.count):\(profile):\(nativeID.utf8.count):\(nativeID)"
        }
        // Missing native metadata cannot merge unrelated conversations by cwd.
        return "minimax:\(source.rawValue):record:\(session.id.utf8.count):\(session.id)"
    }

    private static func valid(_ value: String, maximum: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= maximum
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}
