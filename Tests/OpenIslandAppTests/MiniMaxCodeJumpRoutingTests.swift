import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@Suite(.serialized)
struct MiniMaxCodeJumpRoutingTests {
    private final class Calls: @unchecked Sendable {
        var targets: [JumpTarget] = []
        var opens: [[String]] = []
    }
    private var target: JumpTarget {
        JumpTarget(terminalApp: "MiniMax Code.app", workspaceName: "acceptance",
                   paneTitle: "own task", appConversationID: "mvs_own",
                   runtimeMetadataDatabasePath: "/admitted/v2/sqlite/runtime-state.sqlite",
                   runtimeSourceVersion: "3.1.0")
    }

    @Test func exactRuntimeMetadataReachesTheVerifier() throws {
        let calls = Calls()
        let service = TerminalJumpService(
            applicationResolver: { $0 == "com.minimax.agent" ? URL(fileURLWithPath: "/Applications/MiniMax Code.app") : nil },
            appRunningChecker: { _ in true },
            openAction: { calls.opens.append($0) },
            miniMaxCodeConversationFocuser: { calls.targets.append($0); return .focused },
            jumpDiagnostics: { _ in })
        #expect(try service.jump(to: target) == "Focused the MiniMaxCode conversation.")
        #expect(calls.targets == [target])
        #expect(calls.opens.isEmpty)
    }

    @Test func failedIdentityVerificationDoesNotOpenWorkspaceOrClaimSuccess() {
        let calls = Calls()
        let service = TerminalJumpService(
            applicationResolver: { _ in URL(fileURLWithPath: "/Applications/MiniMax Code.app") },
            appRunningChecker: { _ in true },
            openAction: { calls.opens.append($0) },
            miniMaxCodeConversationFocuser: { calls.targets.append($0); return .unavailable("active-session-id-unverified") },
            jumpDiagnostics: { _ in })
        #expect(throws: TerminalJumpError.self) { try service.jump(to: target) }
        #expect(calls.targets == [target])
        #expect(calls.opens.isEmpty)
    }
}
