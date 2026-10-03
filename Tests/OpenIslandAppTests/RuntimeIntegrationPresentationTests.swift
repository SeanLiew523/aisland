import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct RuntimeIntegrationPresentationTests {
    @Test func deepSeekJumpDispatchesExactIdentityAndDoesNotClaimSelection() throws {
        let target = JumpTarget(terminalApp: "DeepSeek Harness.app", workspaceName: "project", paneTitle: "task",
            appConversationID: "real-session", runtimeProfileID: "desktop")
        let service = TerminalJumpService(applicationResolver: { _ in URL(fileURLWithPath: "/tmp/app") },
            appRunningChecker: { _ in true }, openAction: { arguments in #expect(arguments == ["-b", "com.deepseek.dsh"]) },
            deepseekNavigator: { value in #expect(value.appConversationID == "real-session"); #expect(value.runtimeProfileID == "desktop") })
        let result = try service.jump(to: target)
        #expect(result.contains("request"))
        #expect(!result.contains("Focused"))
    }
    @Test func failedDeepSeekNavigationDoesNotActivateAnotherConversation() {
        let service = TerminalJumpService(applicationResolver: { _ in URL(fileURLWithPath: "/tmp/app") },
            appRunningChecker: { _ in true }, openAction: { _ in Issue.record("Failed request must not activate fallback") },
            deepseekNavigator: { _ in throw DeepSeekNavigationError.sourceRejected })
        let target = JumpTarget(terminalApp: "DeepSeek Harness.app", workspaceName: "test", paneTitle: "test",
            appConversationID: "s", runtimeProfileID: "desktop")
        #expect(throws: DeepSeekNavigationError.sourceRejected) { try service.jump(to: target) }
    }
    @Test func hermesDiscoveryMatchesCLIEntrypointsOnly() {
        let discovery = ActiveAgentProcessDiscovery { executable, arguments in
            if executable == "/bin/ps" { return """
              10 20 ttys002 /Users/test/.hermes/hermes-agent/venv/bin/python /Users/test/.hermes/hermes-agent/hermes_cli/main.py
              11 20 ttys003 /Users/test/.local/bin/hermes chat
              12 20 ttys004 python /tmp/contains-hermes/report.py
              20 30 ttys002 /bin/zsh
              30 1 ?? /Applications/Terminal.app/Contents/MacOS/Terminal
              """ }
            if executable == "/usr/sbin/lsof" { return "fcwd\nn/tmp/project" }
            return nil
        }
        let sessions = discovery.discover().filter { $0.tool == .hermesCLI }
        #expect(sessions.count == 2)
        #expect(Set(sessions.compactMap(\.terminalTTY)) == ["/dev/ttys002", "/dev/ttys003"])
    }
    @Test func runtimeFailureRemainsVisibleAndReplyIsUnavailable() {
        let session = AgentSession(id: "s", title: "Hermes", tool: .hermesCLI, phase: .completed, summary: "Turn failed", updatedAt: .now,
            jumpTarget: JumpTarget(terminalApp: "Ghostty", workspaceName: "test", paneTitle: "test", tmuxTarget: "%1"), runtimeOutcome: .failed)
        #expect(session.spotlightStatusLabel == "Turn failed")
        #expect(session.spotlightShowsDetailLines)
        #expect(!TerminalTextSender.canReply(to: session, enabled: true))
    }

    @Test func failureAndInterruptDoNotPresentSuccessNotification() {
        let event = AgentEvent.sessionCompleted(SessionCompleted(sessionID: "s", summary: "Failed", timestamp: .now, isInterrupt: true))
        #expect(IslandSurface.notificationSurface(for: event) == nil)
    }
}
