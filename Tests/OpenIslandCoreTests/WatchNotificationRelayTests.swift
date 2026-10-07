import Foundation
import Testing
@testable import OpenIslandCore

/// Pins the multi-pending cleanup contract for `WatchNotificationRelay`.
/// `removePendingRequestBySession` (the previous implementation) only ever
/// removed the first matching entry; concurrent permission/question prompts
/// for one session left every later entry pinned in `pendingRequests` and
/// the watch SSE stream stuck on stale "actionable" badges.
struct WatchNotificationRelayTests {
    @Test
    func successOnlyCompletionProjectionDoesNotTurnSilentOutcomesIntoCompanionSuccess() {
        let session = AgentSession(id: "runtime-test", title: "Test", tool: .hermesCLI,
            phase: .completed, summary: "Test", updatedAt: .now)
        for outcome in [RuntimeTurnOutcome.failed, .interrupted, .ended] {
            let payload = SessionCompleted(sessionID: session.id, summary: "Test", timestamp: .now,
                runtimeOutcome: outcome)
            #expect(WatchNotificationRelay.completionNotification(for: payload, session: session) == nil)
        }
        let restored = SessionCompleted(sessionID: session.id, summary: "Restored", timestamp: .now,
            isInterrupt: true, runtimeOutcome: .succeeded)
        #expect(WatchNotificationRelay.completionNotification(for: restored, session: session) == nil)
        let ended = SessionCompleted(sessionID: session.id, summary: "Ended", timestamp: .now, isSessionEnd: true)
        #expect(WatchNotificationRelay.completionNotification(for: ended, session: session) == nil)
        let wrongSession = SessionCompleted(sessionID: "other", summary: "Done", timestamp: .now)
        #expect(WatchNotificationRelay.completionNotification(for: wrongSession, session: session) == nil)
        for outcome in [nil, RuntimeTurnOutcome.succeeded] {
            let payload = SessionCompleted(sessionID: session.id, summary: "Done", timestamp: .now, runtimeOutcome: outcome)
            #expect(WatchNotificationRelay.completionNotification(for: payload, session: session)?.sseString()
                .contains("event: sessionCompleted") == true)
        }
    }

    @Test
    func resolvingActionableStateClearsAllPendingRequestsForSession() {
        let relay = WatchNotificationRelay()
        let session = AgentSession(
            id: "session-multi",
            title: "Multi-pending session",
            tool: .claudeCode,
            phase: .running,
            summary: "Spawned subagents",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )

        // Two distinct permissions for the same session — the realistic
        // case is a fan-out where multiple Claude subagents each ask for
        // approval before the parent session resolves.
        relay.notifyEvent(
            .permissionRequested(
                PermissionRequested(
                    sessionID: session.id,
                    request: PermissionRequest(
                        title: "Edit a.swift",
                        summary: "Sub A",
                        affectedPath: "Sources/A.swift"
                    ),
                    timestamp: Date(timeIntervalSince1970: 1_001)
                )
            ),
            session: session
        )
        relay.notifyEvent(
            .permissionRequested(
                PermissionRequested(
                    sessionID: session.id,
                    request: PermissionRequest(
                        title: "Edit b.swift",
                        summary: "Sub B",
                        affectedPath: "Sources/B.swift"
                    ),
                    timestamp: Date(timeIntervalSince1970: 1_002)
                )
            ),
            session: session
        )

        #expect(relay.pendingRequestCountForTests(sessionID: session.id) == 2)

        relay.notifyEvent(
            .actionableStateResolved(
                ActionableStateResolved(
                    sessionID: session.id,
                    summary: "User answered both",
                    timestamp: Date(timeIntervalSince1970: 1_003)
                )
            ),
            session: session
        )

        #expect(relay.pendingRequestCountForTests(sessionID: session.id) == 0)
        #expect(relay.pendingRequestCountForTests() == 0)
    }

    @Test
    func resolvingOneSessionLeavesOtherSessionsUntouched() {
        let relay = WatchNotificationRelay()
        let sessionA = AgentSession(
            id: "session-A",
            title: "A",
            tool: .claudeCode,
            phase: .running,
            summary: "A",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let sessionB = AgentSession(
            id: "session-B",
            title: "B",
            tool: .codex,
            phase: .running,
            summary: "B",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )

        relay.notifyEvent(
            .permissionRequested(
                PermissionRequested(
                    sessionID: sessionA.id,
                    request: PermissionRequest(
                        title: "A",
                        summary: "A",
                        affectedPath: "/A"
                    ),
                    timestamp: Date(timeIntervalSince1970: 1_001)
                )
            ),
            session: sessionA
        )
        relay.notifyEvent(
            .permissionRequested(
                PermissionRequested(
                    sessionID: sessionB.id,
                    request: PermissionRequest(
                        title: "B",
                        summary: "B",
                        affectedPath: "/B"
                    ),
                    timestamp: Date(timeIntervalSince1970: 1_002)
                )
            ),
            session: sessionB
        )

        #expect(relay.pendingRequestCountForTests() == 2)

        relay.notifyEvent(
            .actionableStateResolved(
                ActionableStateResolved(
                    sessionID: sessionA.id,
                    summary: "Resolved A",
                    timestamp: Date(timeIntervalSince1970: 1_003)
                )
            ),
            session: sessionA
        )

        #expect(relay.pendingRequestCountForTests(sessionID: sessionA.id) == 0)
        #expect(relay.pendingRequestCountForTests(sessionID: sessionB.id) == 1)
    }
}
