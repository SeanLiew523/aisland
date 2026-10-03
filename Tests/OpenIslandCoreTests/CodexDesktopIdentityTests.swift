import Foundation
import Testing
@testable import OpenIslandCore

struct CodexDesktopIdentityTests {
    @Test(arguments: ["Unknown", "", "Codex.app"])
    func weakTargetUpdatesKeepDesktopConversation(host: String) {
        var state = desktopState()
        state.apply(.jumpTargetUpdated(JumpTargetUpdated(
            sessionID: "desktop", jumpTarget: target(host: host), timestamp: .now
        )))
        #expect(state.session(id: "desktop")?.jumpTarget?.terminalApp == "Codex.app")
        #expect(state.session(id: "desktop")?.jumpTarget?.codexThreadID == "desktop")
        #expect(state.session(id: "desktop")?.isCodexAppSession == true)
    }

    @Test
    func repeatedSessionStartWithoutHostKeepsDesktopConversation() {
        for incoming in [nil, target(host: "Unknown"), target(host: "Codex.app")] as [JumpTarget?] {
            var state = desktopState()
            state.apply(.sessionStarted(SessionStarted(
                sessionID: "desktop", title: "Project", tool: .codex,
                summary: "Restarted hook", timestamp: .now, jumpTarget: incoming
            )))
            #expect(state.session(id: "desktop")?.jumpTarget?.codexThreadID == "desktop")
        }
    }

    @Test
    func attachmentReconciliationDoesNotEraseDesktopIdentity() {
        var state = desktopState()
        let changed = state.reconcileJumpTargets(["desktop": target(host: "Unknown")])
        #expect(!changed)
        #expect(state.session(id: "desktop")?.jumpTarget?.codexThreadID == "desktop")
    }

    @Test(arguments: ["Terminal", "Ghostty", "VS Code"])
    func explicitTerminalOrIDEIsNotReclassified(host: String) {
        let incoming = target(host: host)
        #expect(incoming.preservingCodexDesktopIdentity(from: target(host: "Codex.app", id: "desktop")) == incoming)
        var state = SessionState()
        state.apply(.sessionStarted(SessionStarted(
            sessionID: "cli", title: "CLI", tool: .codex, summary: "Working",
            timestamp: .now, jumpTarget: incoming
        )))
        #expect(state.session(id: "cli")?.isCodexAppSession == false)
    }

    private func desktopState() -> SessionState {
        var state = SessionState()
        state.apply(.sessionStarted(SessionStarted(
            sessionID: "desktop", title: "Project", tool: .codex, summary: "Working",
            timestamp: .now, jumpTarget: target(host: "Codex.app", id: "desktop")
        )))
        return state
    }

    private func target(host: String, id: String? = nil) -> JumpTarget {
        JumpTarget(terminalApp: host, workspaceName: "project", paneTitle: "Codex", codexThreadID: id)
    }
}
