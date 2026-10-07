import Foundation
import Testing
@testable import OpenIslandCore

struct MiniMaxCodeDesktopLivenessTests {
    private func fixtureState() -> SessionState {
        var reducer = RuntimeLifecycleReducer()
        var state = SessionState()
        for (index, nativeID) in ["native-a", "native-b"].enumerated() {
            let payload = RuntimeLifecycleHookPayload(
                source: .minimaxCodeDesktop, event: .turnStarted, profileID: "desktop",
                sessionID: nativeID, turnID: "turn-\(index)", sequence: index + 1,
                cwd: "/fixture/shared-project", timestamp: Date(timeIntervalSince1970: 100),
                appConversationID: nativeID,
                metadataDatabasePath: "/fixture/v2/sqlite/runtime-state.sqlite", sourceRuntimeVersion: "3.1.0")
            for event in reducer.receive(payload) { state.apply(event) }
        }
        return state
    }

    @Test func sameWorkspaceNativeConversationsSurviveRepeatedNormalPolling() {
        var state = fixtureState()
        let originalTargets = Dictionary(uniqueKeysWithValues: state.sessions.map { ($0.id, $0.jumpTarget) })
        #expect(state.sessions.count == 2)
        #expect(MiniMaxCodeDesktopLiveness.aliveSessionIDs(in: state.sessions, runningSourceVersions: ["3.1.1"])
                == Set(state.sessions.map(\.id)))
        for _ in 0..<4 {
            let alive = MiniMaxCodeDesktopLiveness.aliveSessionIDs(in: state.sessions, runningSourceVersions: ["3.1.0"])
            #expect(alive == Set(state.sessions.map(\.id)))
            let changed = state.markProcessLiveness(aliveSessionIDs: alive)
            let removed = state.removeInvisibleSessions()
            #expect(changed.isEmpty)
            #expect(!removed)
        }
        #expect(state.liveRunningCount == 2)
        #expect(Set(state.sessions.compactMap { $0.jumpTarget?.appConversationID }) == ["native-a", "native-b"])
        #expect(Dictionary(uniqueKeysWithValues: state.sessions.map { ($0.id, $0.jumpTarget) }) == originalTargets)
    }

    @Test func absentOrUnsupportedDesktopStillExpiresAfterTwoMissingPolls() {
        for versions in [Set<String>(), Set(["3.2.0"])] {
            var state = fixtureState()
            let alive = MiniMaxCodeDesktopLiveness.aliveSessionIDs(in: state.sessions, runningSourceVersions: versions)
            #expect(alive.isEmpty)
            let firstPoll = state.markProcessLiveness(aliveSessionIDs: alive)
            let secondPoll = state.markProcessLiveness(aliveSessionIDs: alive)
            let removed = state.removeInvisibleSessions()
            #expect(firstPoll.isEmpty)
            #expect(secondPoll.count == 2)
            #expect(removed)
            #expect(state.sessions.isEmpty)
        }
    }

    @Test func endedWrongIdentityAndUnadmittedRowsAreNeverRevived() {
        let original = fixtureState().sessions[0]
        var ended = original; ended.isSessionEnded = true
        var cli = original; cli.tool = .minimaxCodeCLI
        var wrongID = original; wrongID.jumpTarget?.appConversationID = "another-native-id"
        var wrongVersion = original; wrongVersion.jumpTarget?.runtimeSourceVersion = "3.2.0"
        var noDatabase = original; noDatabase.jumpTarget?.runtimeMetadataDatabasePath = nil
        var unhooked = original; unhooked.isHookManaged = false
        var demo = original; demo.origin = .demo
        for rejected in [ended, cli, wrongID, wrongVersion, noDatabase, unhooked, demo] {
            #expect(MiniMaxCodeDesktopLiveness.aliveSessionIDs(in: [rejected], runningSourceVersions: ["3.1.0"]).isEmpty)
        }
    }
}
