import Foundation
import Testing
import OpenIslandCore
@testable import OpenIslandApp

struct GhosttyJumpDiagnosticsTests {
    @Test func harnessAndAcceptanceNeverReadTheOrdinaryMarker() {
        #expect(GhosttyJumpDiagnostics.shouldRecord(loadRuntimeState: true, isAcceptance: false))
        #expect(!GhosttyJumpDiagnostics.shouldRecord(loadRuntimeState: false, isAcceptance: false))
        #expect(!GhosttyJumpDiagnostics.shouldRecord(loadRuntimeState: true, isAcceptance: true))
    }
    private let target = JumpTarget(terminalApp: "Ghostty", workspaceName: "private workspace", paneTitle: "private title", workingDirectory: "/private/path", terminalSessionID: "abc")
    @Test func clickStagesUseFixedCategoriesAndHashedSurfaceOnly() {
        let start = GhosttyJumpDiagnostics.event(target: target, phase: "start")
        #expect(start.values["reason"] == "ghostty")
        #expect(start.values["surfaceIDHash"] == GhosttyDiagnosticEvent.hashID("abc"))
        #expect(start.flags["hasSurfaceID"] == true)
        #expect(GhosttyJumpDiagnostics.event(target: target, phase: "success").values["event"] == "success")
        #expect(!String(describing: start).contains("private"))
    }
    @Test func errorsNeverLogDescriptionsArgumentsOrUnapprovedReasons() {
        for error in [TerminalJumpError.appleScriptFailed("private stderr"), .openFailed(["private argv"]), .conversationUnavailable("private app", "private reason")] {
            let event = GhosttyJumpDiagnostics.event(target: target, phase: "failure", error: error)
            #expect(!String(describing: event).contains("private"))
        }
        #expect(GhosttyJumpDiagnostics.event(target: target, phase: "failure", error: TerminalJumpError.conversationUnavailable("Ghostty", "focused-terminal-id-unverified")).values["reason"] == "focused-terminal-id-unverified")
        #expect(GhosttyJumpDiagnostics.event(target: nil, phase: "failure").flags["hasSurfaceID"] == false)
    }
}
