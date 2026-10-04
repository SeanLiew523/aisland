import Foundation

/// Desktop hooks run without a terminal process. App liveness keeps each
/// admitted native conversation alive independently of its workspace or PID.
public enum MiniMaxCodeDesktopLiveness {
    public static func aliveSessionIDs(
        in sessions: [AgentSession], runningSourceVersions: Set<String>
    ) -> Set<String> {
        guard runningSourceVersions.contains("3.1.0") else { return [] }
        return Set(sessions.compactMap { session in
            guard session.tool == .minimaxCodeDesktop, session.origin == .live,
                  session.isHookManaged, !session.isSessionEnded,
                  let target = session.jumpTarget, target.terminalApp == "MiniMax Code.app",
                  let nativeID = target.appConversationID, let profileID = target.runtimeProfileID else { return nil }
            let identity = RuntimeLifecycleHookPayload(
                source: .minimaxCodeDesktop, event: .sessionObserved,
                profileID: profileID, sessionID: nativeID,
                cwd: target.workingDirectory ?? "", timestamp: session.updatedAt,
                metadataDatabasePath: target.runtimeMetadataDatabasePath,
                sourceRuntimeVersion: target.runtimeSourceVersion)
            guard identity.isValid, identity.namespacedSessionID == session.id else { return nil }
            return session.id
        })
    }
}
