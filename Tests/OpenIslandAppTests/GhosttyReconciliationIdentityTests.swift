import Foundation
import Testing
import OpenIslandCore
@testable import OpenIslandApp

struct GhosttyReconciliationIdentityTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test
    func removedSurfaceIsNeverReplacedByAnotherInTheSameDirectory() {
        let source = session("source", surface: "closed")
        let snapshots = [snapshot("other")]
        #expect(TerminalJumpTargetResolver().matchGhosttySnapshots(snapshots, to: [source], activeProcesses: []).isEmpty)
        let resolutions = resolve([source], snapshots)
        #expect(resolutions["source"]?.correctedJumpTarget == nil)
    }

    @Test
    func twoUnboundSourcesAndTwoSameDirectorySurfacesAreAmbiguousInEitherOrder() {
        let sessions = [session("a"), session("b", tool: .grokBuild)]
        for snapshots in [[snapshot("A"), snapshot("B")], [snapshot("B"), snapshot("A")]] {
            #expect(TerminalJumpTargetResolver().matchGhosttySnapshots(snapshots, to: sessions, activeProcesses: []).isEmpty)
            let resolutions = resolve(sessions, snapshots)
            #expect(resolutions.values.allSatisfy { $0.correctedJumpTarget == nil })
        }
    }

    @Test
    func oneUnboundSourceCannotChooseBetweenTwoSameDirectorySurfaces() {
        let sessions = [session("a")]
        let snapshots = [snapshot("A"), snapshot("B")]
        #expect(TerminalJumpTargetResolver().matchGhosttySnapshots(snapshots, to: sessions, activeProcesses: []).isEmpty)
        #expect(resolve(sessions, snapshots)["a"]?.correctedJumpTarget == nil)
    }

    @Test
    func capturedSurfaceIdentitiesSurviveInventoryAndSourceOrderingChanges() {
        for tool in [AgentTool.ohMyPi, .grokBuild, .claudeCode, .codex] {
            let sessions = [session("a", surface: "A", tool: tool), session("b", surface: "B", tool: tool)]
            for snapshots in [[snapshot("A"), snapshot("B")], [snapshot("B"), snapshot("A")]] {
                let match = TerminalJumpTargetResolver().matchGhosttySnapshots(snapshots, to: sessions.reversed(), activeProcesses: [])
                #expect(match["a"]?.sessionID == "A")
                #expect(match["b"]?.sessionID == "B")
                let resolutions = resolve(sessions, snapshots)
                #expect(resolutions["a"]?.correctedJumpTarget?.terminalSessionID != "B")
                #expect(resolutions["b"]?.correctedJumpTarget?.terminalSessionID != "A")
            }
        }
    }

    @Test
    func genuinelyUniqueUnboundSourceStillGetsAnExactSurface() {
        let sessions = [session("a")]
        let snapshots = [snapshot("A")]
        #expect(TerminalJumpTargetResolver().matchGhosttySnapshots(snapshots, to: sessions, activeProcesses: [])["a"]?.sessionID == "A")
        #expect(resolve(sessions, snapshots)["a"]?.correctedJumpTarget?.terminalSessionID == "A")
    }

    private func session(_ id: String, surface: String? = nil, tool: AgentTool = .ohMyPi) -> AgentSession {
        AgentSession(id: id, title: "Agent", tool: tool, origin: .live, attachmentState: .attached,
                     phase: .running, summary: "Fixture", updatedAt: now,
                     jumpTarget: JumpTarget(terminalApp: "Ghostty", workspaceName: "project", paneTitle: "Shell",
                                            workingDirectory: "/tmp/project", terminalSessionID: surface))
    }

    private func snapshot(_ id: String) -> TerminalJumpTargetResolver.GhosttyTerminalSnapshot {
        .init(sessionID: id, workingDirectory: "/tmp/project", title: "Shell")
    }

    private func resolve(_ sessions: [AgentSession], _ snapshots: [TerminalJumpTargetResolver.GhosttyTerminalSnapshot]) -> [String: TerminalSessionAttachmentProbe.SessionResolution] {
        TerminalSessionAttachmentProbe().sessionResolutions(
            for: sessions,
            ghosttyAvailability: .available(snapshots.map { .init(sessionID: $0.sessionID, workingDirectory: $0.workingDirectory, title: $0.title) }, appIsRunning: true),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            now: now
        )
    }
}
