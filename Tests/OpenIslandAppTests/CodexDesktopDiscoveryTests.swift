import Foundation
import Testing
import OpenIslandCore
@testable import OpenIslandApp

@MainActor
struct CodexDesktopDiscoveryTests {
    @Test(arguments: ["Unknown", "", "Codex.app", "nil"])
    func rolloutRepairsIncompleteCachedDesktopTarget(host: String) {
        let existing = session(host: host, id: nil)
        let merged = merge(existing: existing, discovered: session(host: "Codex.app", id: "desktop"))
        #expect(merged.jumpTarget?.terminalApp == "Codex.app")
        #expect(merged.jumpTarget?.codexThreadID == "desktop")
        #expect(merged.isCodexAppSession)
    }

    @Test(arguments: ["Terminal", "Ghostty", "VS Code"])
    func explicitLiveTerminalIdentitySurvivesHistoricalDesktopRollout(host: String) {
        let merged = merge(existing: session(host: host, id: nil), discovered: session(host: "Codex.app", id: "desktop"))
        #expect(merged.jumpTarget?.terminalApp == host)
        #expect(!merged.isCodexAppSession)
    }

    @Test(arguments: [SessionPhase.waitingForApproval, .waitingForAnswer])
    func newerRolloutRepairsJumpWithoutRemovingPendingAction(phase: SessionPhase) {
        var existing = session(host: "Unknown", id: nil)
        existing.phase = phase
        existing.summary = "Pending action"
        if phase == .waitingForApproval {
            existing.permissionRequest = PermissionRequest(title: "Approve", summary: "Pending action", affectedPath: "file.swift")
        } else {
            existing.questionPrompt = QuestionPrompt(title: "Choose", options: [])
        }
        var discovered = session(host: "Codex.app", id: "desktop")
        discovered.updatedAt = existing.updatedAt.addingTimeInterval(60)
        let merged = merge(existing: existing, discovered: discovered)
        #expect(merged.phase == phase)
        #expect(merged.summary == "Pending action")
        #expect(merged.permissionRequest == existing.permissionRequest)
        #expect(merged.questionPrompt == existing.questionPrompt)
        #expect(merged.jumpTarget?.codexThreadID == "desktop")
    }

    private func merge(existing: AgentSession, discovered: AgentSession) -> AgentSession {
        let coordinator = SessionDiscoveryCoordinator()
        coordinator.stateAccessor = { SessionState(sessions: [existing]) }
        return coordinator.mergeDiscoveredSessions([discovered])[0]
    }

    private func session(host: String, id: String?) -> AgentSession {
        AgentSession(id: "desktop", title: "Project", tool: .codex, phase: .running,
                     summary: "Working", updatedAt: Date(timeIntervalSince1970: 2_000),
                     jumpTarget: host == "nil" ? nil : JumpTarget(
                        terminalApp: host, workspaceName: "project", paneTitle: "Codex", codexThreadID: id
                     ))
    }
}
