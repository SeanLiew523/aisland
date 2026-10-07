import Foundation
import Testing
import OpenIslandCore
@testable import OpenIslandApp

/// Availability is an explicit input; monitor guards are extracted verbatim
/// from production by test-startup-recognition-isolated.py.
@MainActor struct StartupDesktopCacheLivenessTests {
    private func session(_ id: String, tool: AgentTool, at date: Date) -> AgentSession {
        AgentSession(id: id, title: id, tool: tool, origin: .live, attachmentState: .attached,
            phase: .running, summary: "Fixture", updatedAt: date,
            jumpTarget: JumpTarget(terminalApp: "Unknown", workspaceName: "fixture", paneTitle: id,
                workingDirectory: "/synthetic/workspace", terminalSessionID: id))
    }
    @Test func restoredDesktopSourcesRequireRunningAppAndKeepCompletionStaleGuard() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("desktop-liveness-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = ClaudeSessionRegistry(fileURL: root.appendingPathComponent("registry.json"))
        let now = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970))
        var records: [AgentSession] = []
        for (tool, app): (AgentTool, String) in [(.zcode, "ZCode.app"), (.workbuddy, "WorkBuddy.app")] {
            for (name, age, phase): (String, TimeInterval, SessionPhase) in [
                ("running", 1_000, .running), ("recent", 10, .completed), ("stale", 1_000, .completed),
            ] {
                var native = session("\(tool.rawValue)-\(name)", tool: tool, at: now.addingTimeInterval(-age))
                native.phase = phase
                native.jumpTarget?.terminalApp = app
                native.jumpTarget?.appConversationID = "native-\(name)"
                native.jumpTarget?.appDeepLinkURL = "fixture://conversation/\(name)"
                records.append(native)
            }
        }
        try registry.save(records.map(ClaudeTrackedSessionRecord.init(session:)))
        let restored = try registry.load().map(\.restorableSession)
        #expect(restored.allSatisfy { !$0.isProcessAlive && !$0.isHookManaged && $0.attachmentState == .stale })
        let monitor = DesktopCacheLivenessFixture()
        var state = SessionState(sessions: restored)
        let alive = monitor.aliveSessionIDs(for: restored, zcodeRunning: true, workbuddyRunning: true)
        #expect(alive == Set(["zcode-running", "zcode-recent", "workbuddy-running", "workbuddy-recent"]))
        state.markProcessLiveness(aliveSessionIDs: alive)
        state.markProcessLiveness(aliveSessionIDs: alive) // Preserve the existing two-poll grace.
        for original in records {
            let current = try #require(state.session(id: original.id))
            #expect(current.isProcessAlive == alive.contains(original.id))
            #expect(current.updatedAt == original.updatedAt && current.jumpTarget == original.jumpTarget)
        }
        let closed = monitor.aliveSessionIDs(for: state.sessions, zcodeRunning: false, workbuddyRunning: false)
        #expect(closed.isEmpty)
        state.markProcessLiveness(aliveSessionIDs: closed)
        state.markProcessLiveness(aliveSessionIDs: closed)
        #expect(state.sessions.allSatisfy { !$0.isProcessAlive })
        #expect(monitor.aliveSessionIDs(for: restored, zcodeRunning: true, workbuddyRunning: false)
            == Set(["zcode-running", "zcode-recent"]))
    }

}
