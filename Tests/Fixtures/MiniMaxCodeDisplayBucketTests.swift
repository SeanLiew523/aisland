import Foundation
import Testing
@testable import OpenIslandCore

struct MiniMaxCodeDisplayIdentityTests {
    private func session(_ id: String, native: String?, profile: String? = "desktop", tool: AgentTool = .minimaxCodeDesktop,
                         age: TimeInterval = 0, cwd: String = "/fixture/shared-workspace") -> AgentSession {
        var value = AgentSession(id: id, title: "MiniMax · fixture", tool: tool, origin: .live,
            attachmentState: .attached, phase: .completed, summary: "Completed", updatedAt: Date().addingTimeInterval(-age),
            jumpTarget: JumpTarget(terminalApp: "MiniMax Code.app", workspaceName: "fixture", paneTitle: "MiniMaxCode Desktop",
                workingDirectory: cwd, appConversationID: native, runtimeProfileID: profile,
                runtimeMetadataDatabasePath: "/fixture/v2/sqlite/runtime-state.sqlite", runtimeSourceVersion: "3.1.0"))
        value.isHookManaged = true; value.isProcessAlive = true
        return value
    }

    @Test func actualBucketKeepsBothSameWorkspaceConversationsAlongsideAnOlderOtherWorkspace() {
        let a = session("record-a", native: "native-a", age: 20 * 60)
        let b = session("record-b", native: "native-b", age: 5 * 60)
        let old = session("old-other", native: "native-c", age: 2 * 60 * 60, cwd: "/fixture/other-workspace")
        let buckets = MiniMaxDisplayBucketFixture(state: SessionState(sessions: [old, a, b])).computeSessionBuckets()
        #expect(buckets.primary.map(\.id) == ["record-b", "record-a", "old-other"])
        #expect(buckets.overflow.isEmpty)
        #expect(Set(buckets.primary.compactMap { $0.jumpTarget?.appConversationID }) == ["native-a", "native-b", "native-c"])
    }

    @Test func actualBucketStillDropsDuplicateRepresentationsOfTheSameNativeConversation() {
        let current = session("current", native: "native-a")
        let historical = session("historical", native: "native-a", age: 3600, cwd: "/fixture/previous-workspace")
        let other = session("other", native: "native-b", age: 60)
        let buckets = MiniMaxDisplayBucketFixture(state: SessionState(sessions: [historical, other, current])).computeSessionBuckets()
        #expect(buckets.primary.map(\.id) == ["current", "other"])
        #expect(buckets.overflow.map(\.id) == ["historical"])
    }

    @Test func actualBucketPreservesRecordsWithoutNativeOrProfileMetadata() {
        let missing = session("missing", native: nil)
        var noTarget = session("no-target", native: nil, age: 1); noTarget.jumpTarget = nil
        let blank = session("blank", native: " ", age: 2)
        let noProfile = session("no-profile", native: "native-a", profile: nil, age: 3)
        let buckets = MiniMaxDisplayBucketFixture(state: SessionState(sessions: [missing, noTarget, blank, noProfile])).computeSessionBuckets()
        #expect(Set(buckets.primary.map(\.id)) == ["missing", "no-target", "blank", "no-profile"])
        #expect(buckets.overflow.isEmpty)
    }

    @Test func sourceProfileAndNativeCaseHaveDistinctLengthPrefixedDisplayIdentities() {
        let identities = [session("desktop", native: "native-a"),
            session("cli", native: "native-a", tool: .minimaxCodeCLI),
            session("profile", native: "native-a", profile: "other"),
            session("case", native: "NATIVE-A"),
            session("delimited-a", native: "x:y", profile: "p"),
            session("delimited-b", native: "y", profile: "p:x")]
        #expect(Set(identities.compactMap { MiniMaxCodeDisplayIdentity.key(for: $0) }).count == identities.count)
        let buckets = MiniMaxDisplayBucketFixture(state: SessionState(sessions: identities)).computeSessionBuckets()
        #expect(buckets.primary.count == identities.count)
        #expect(buckets.overflow.isEmpty)
    }

    @Test func actualBucketKeepsExistingGhosttyPaneDeduplication() {
        var current = session("ghostty-current", native: nil, tool: .claudeCode)
        current.jumpTarget = JumpTarget(terminalApp: "Ghostty", workspaceName: "fixture", paneTitle: "Claude",
            workingDirectory: "/fixture/shared-workspace", terminalSessionID: "same-pane")
        var old = current; old.id = "ghostty-old"; old.updatedAt = Date().addingTimeInterval(-3600)
        #expect(MiniMaxCodeDisplayIdentity.key(for: current) == nil)
        let buckets = MiniMaxDisplayBucketFixture(state: SessionState(sessions: [old, current])).computeSessionBuckets()
        #expect(buckets.primary.map(\.id) == ["ghostty-current"])
        #expect(buckets.overflow.map(\.id) == ["ghostty-old"])
    }
}
