import Foundation
import Testing
import OpenIslandCore
@testable import OpenIslandApp

struct GhosttySourceIdentityRequiredTests {
    private let now = Date(timeIntervalSince1970: 1_000)
    private let nativeID = "a3c6effa-1eac-4d93-9a67-d20bb4625e44"
    private func source(_ tool: AgentTool, surface: String? = nil) -> AgentSession {
        AgentSession(id: nativeID, title: "Fixture", tool: tool, origin: .live, attachmentState: .attached,
            phase: .running, summary: "Fixture", updatedAt: now,
            jumpTarget: JumpTarget(terminalApp: "Ghostty", workspaceName: "shared", paneTitle: "Shell",
                workingDirectory: "/synthetic/shared", terminalSessionID: surface))
    }
    private func resolve(_ session: AgentSession, _ snapshots: [TerminalJumpTargetResolver.GhosttyTerminalSnapshot],
        processes: [ActiveAgentProcessDiscovery.ProcessSnapshot] = []) -> TerminalSessionAttachmentProbe.SessionResolution? {
        TerminalSessionAttachmentProbe().sessionResolutions(for: [session],
            ghosttyAvailability: .available(snapshots.map { .init(sessionID: $0.sessionID,
                workingDirectory: $0.workingDirectory, title: $0.title) }, appIsRunning: true),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            activeProcesses: processes, now: now)[session.id]
    }
    private func pane(_ id: String, title: String = "Shell") -> TerminalJumpTargetResolver.GhosttyTerminalSnapshot {
        .init(sessionID: id, workingDirectory: "/synthetic/shared", title: title)
    }

    @Test(arguments: AgentTool.allCases)
    func everyAgentRejectsUnboundPlainShellAndGenericAgentTitle(_ tool: AgentTool) throws {
        let session = source(tool)
        for title in ["Shell", tool.displayName] {
            for snapshots in [[pane("one", title: title)], [pane("one", title: title), pane("two", title: title)]] {
                #expect(TerminalJumpTargetResolver().matchGhosttySnapshots(snapshots, to: [session], activeProcesses: []).isEmpty)
                #expect(resolve(session, snapshots)?.correctedJumpTarget == nil)
                let terminals = snapshots.map { TerminalJumpService.GhosttyTerminal(id: $0.sessionID,
                    workingDirectory: $0.workingDirectory, title: $0.title) }
                #expect(TerminalJumpService.selectGhosttyTerminal(terminals, target: try #require(session.jumpTarget)) == .missing)
            }
        }
    }

    @Test(arguments: AgentTool.allCases)
    func everyAgentKeepsReceiptIDWhenAnotherShellSharesTheDirectory(_ tool: AgentTool) throws {
        let session = source(tool, surface: "owned")
        let snapshots = [pane("foreign"), pane("owned")]
        #expect(TerminalJumpTargetResolver().matchGhosttySnapshots(snapshots, to: [session], activeProcesses: [])[nativeID]?.sessionID == "owned")
        #expect(resolve(session, snapshots)?.correctedJumpTarget?.terminalSessionID != "foreign")
        #expect(resolve(session, snapshots)?.attachmentState == .attached)
        let terminals = snapshots.map { TerminalJumpService.GhosttyTerminal(id: $0.sessionID,
            workingDirectory: $0.workingDirectory, title: $0.title) }
        #expect(TerminalJumpService.selectGhosttyTerminal(terminals, target: try #require(session.jumpTarget)) == .matched(terminals[1]))
    }

    @Test func nativeTitleEvidenceRequiresWholeUUIDTokenAndOnePage() {
        let session = source(.claudeCode)
        #expect(resolve(session, [pane("owned", title: "Claude · \(nativeID)")])?.correctedJumpTarget?.terminalSessionID == "owned")
        for title in [String(nativeID.prefix(18)), "prefix\(nativeID)", "\(nativeID)suffix", "Claude"] {
            #expect(resolve(session, [pane("foreign", title: title)])?.correctedJumpTarget == nil)
        }
        #expect(resolve(session, [pane("one", title: nativeID), pane("two", title: nativeID)])?.correctedJumpTarget == nil)
        #expect(resolve(source(.claudeCode, surface: "closed"), [pane("foreign", title: nativeID)])?.correctedJumpTarget == nil)
    }

    @Test func sourceActivityRemainsAttachedWithoutInventingSurfaceOrEndingSession() throws {
        for tool in [AgentTool.codex, .claudeCode] {
            let session = source(tool)
            let resolution = try #require(resolve(session, [pane("foreign")], processes: [
                .init(tool: tool, sessionID: nativeID, workingDirectory: "/synthetic/shared", terminalTTY: "/dev/fixture")
            ]))
            #expect(resolution.attachmentState == .attached && resolution.correctedJumpTarget == nil)
        }
    }
}
