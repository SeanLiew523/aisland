import Foundation
import SQLite3
import Testing
@testable import OpenIslandCore

struct MiniMaxCodeConversationPresenceTests {
    private let time = Date(timeIntervalSince1970: 100)
    private func observation(_ fixture: Fixture, session: String = "s1", turn: String = "t1", at: Date? = nil) -> RuntimeLifecycleHookPayload {
        RuntimeLifecycleHookPayload(source: .minimaxCodeDesktop, event: .sessionObserved, profileID: "desktop-test",
            sessionID: session, turnID: turn, cwd: "/tmp/shared-workspace", timestamp: at ?? time,
            terminalApp: "MiniMaxCode.app", appConversationID: session,
            metadataDatabasePath: fixture.path, sourceRuntimeVersion: "3.1.0")
    }
    private func apply(_ payloads: [RuntimeLifecycleHookPayload], reducer: inout RuntimeLifecycleReducer, state: inout SessionState) {
        for payload in payloads { for event in reducer.receive(payload) { state.apply(event) } }
    }
    @Test func switchingVisibleConversationsRetainsBothCompletedCardsAndExactTargets() throws {
        let fixture = try Fixture(); defer { fixture.dispose() }
        try fixture.add(session: "s1", turn: "t1"); try fixture.add(session: "s2", turn: "t2")
        var monitor = MiniMaxCodeLifecycleMonitor(); var reducer = RuntimeLifecycleReducer(); var state = SessionState()
        apply(monitor.observe(observation(fixture), now: time), reducer: &reducer, state: &state)
        apply(monitor.observe(observation(fixture, session: "s2", turn: "t2"), now: time), reducer: &reducer, state: &state)
        try fixture.exec("UPDATE local_runtime_turn_ingress SET status='completed',completed_at_ms=101000")
        apply(monitor.poll(now: time.addingTimeInterval(1)), reducer: &reducer, state: &state)
        var detach = observation(fixture, session: "s2", turn: "t2", at: time.addingTimeInterval(2)); detach.event = .sessionEnded
        let detached = monitor.observe(detach, now: time.addingTimeInterval(2))
        #expect(!detached.contains { $0.event == .sessionEnded })
        apply(detached, reducer: &reducer, state: &state)
        for _ in 0..<3 {
            _ = state.markProcessLiveness(aliveSessionIDs: MiniMaxCodeDesktopLiveness.aliveSessionIDs(in: state.sessions, runningSourceVersions: ["3.1.0"]))
            _ = state.removeInvisibleSessions()
        }
        #expect(state.sessions.count == 2)
        #expect(state.sessions.allSatisfy { $0.phase == .completed && !$0.isSessionEnded })
        #expect(Set(state.sessions.compactMap { $0.jumpTarget?.appConversationID }) == ["s1", "s2"])
        // Presence outlives the short turn-admission cursor, without global discovery.
        #expect(monitor.poll(now: time.addingTimeInterval(100)).isEmpty)
        try fixture.exec("UPDATE local_runtime_sessions SET archived=1 WHERE session_id='s2'")
        let archived = monitor.poll(now: time.addingTimeInterval(102))
        #expect(archived.map(\.sessionID) == ["s2"]); #expect(archived.first?.resultReason == "archived")
        apply(archived, reducer: &reducer, state: &state); _ = state.removeInvisibleSessions()
        #expect(state.sessions.count == 1); #expect(state.sessions.first?.jumpTarget?.appConversationID == "s1")
    }

    @Test func detachDoesNotInterruptAnAcceptedTurnAndLaterDeletionIsDefinitive() throws {
        let fixture = try Fixture(); defer { fixture.dispose() }; try fixture.add()
        var monitor = MiniMaxCodeLifecycleMonitor(); var reducer = RuntimeLifecycleReducer()
        _ = monitor.observe(observation(fixture), now: time).flatMap { reducer.receive($0) }
        var detach = observation(fixture, at: time.addingTimeInterval(1)); detach.event = .sessionEnded
        #expect(!monitor.observe(detach, now: time.addingTimeInterval(1)).contains { $0.event == .sessionEnded })
        try fixture.exec("UPDATE local_runtime_turn_ingress SET status='completed',completed_at_ms=102000")
        let completed = monitor.poll(now: time.addingTimeInterval(2))
        #expect(completed.first?.event == .turnCompleted); #expect(completed.first?.sourceObservedStart == true)
        let events = completed.flatMap { reducer.receive($0) }
        #expect(events.contains { if case let .sessionCompleted(value) = $0 { return value.isInterrupt == false }; return false })
        try fixture.exec("DELETE FROM local_runtime_sessions WHERE session_id='s1'")
        let deleted = monitor.poll(now: time.addingTimeInterval(4))
        #expect(deleted.first?.event == .sessionEnded); #expect(deleted.first?.resultReason == "deleted")
        #expect(monitor.poll(now: time.addingTimeInterval(6)).isEmpty)
    }

    @Test func unavailableUnknownAndNeverSeenMetadataCannotDeclareDeletion() throws {
        let fixture = try Fixture(); defer { fixture.dispose() }; try fixture.add()
        var monitor = MiniMaxCodeLifecycleMonitor(); _ = monitor.observe(observation(fixture), now: time)
        try fixture.exec("ALTER TABLE local_runtime_sessions RENAME TO protected_sessions")
        var detach = observation(fixture, at: time.addingTimeInterval(1)); detach.event = .sessionEnded
        #expect(monitor.observe(detach, now: time.addingTimeInterval(1)).isEmpty)
        #expect(monitor.poll(now: time.addingTimeInterval(3)).isEmpty)
        try fixture.exec("ALTER TABLE protected_sessions RENAME TO local_runtime_sessions; UPDATE local_runtime_sessions SET visibility='future-value'")
        #expect(monitor.poll(now: time.addingTimeInterval(5)).isEmpty)
        try fixture.exec("UPDATE local_runtime_sessions SET visibility='visible'; DELETE FROM local_runtime_sessions WHERE session_id='s1'")
        var neverSeen = MiniMaxCodeLifecycleMonitor()
        #expect(!neverSeen.observe(observation(fixture), now: time).contains { $0.event == .sessionEnded })
        #expect(neverSeen.observe(detach, now: time.addingTimeInterval(1)).isEmpty)
    }

    @Test func exactPresenceReaderUsesOnlyBoundMetadataAndCommittedWalState() throws {
        let fixture = try Fixture(); defer { fixture.dispose() }
        try fixture.exec("PRAGMA journal_mode=WAL"); try fixture.add()
        try fixture.add(session: "foreign", turn: "foreign-turn")
        let reader = MiniMaxCodeConversationPresenceReader(databasePath: fixture.path)
        #expect(try reader.read(sessionID: "s1") == .visible)
        #expect(try reader.read(sessionID: "s1' OR 1=1 --") == .missing)
        try fixture.exec("BEGIN IMMEDIATE; UPDATE local_runtime_sessions SET visibility='hidden' WHERE session_id='s1'")
        #expect(try reader.read(sessionID: "s1") == .visible)
        try fixture.exec("COMMIT")
        #expect(try reader.read(sessionID: "s1") == .hidden)
        try fixture.exec("UPDATE local_runtime_sessions SET archived=2 WHERE session_id='s1'")
        #expect(throws: MiniMaxCodeConversationPresenceReader.ReadError.invalidMetadata) { try reader.read(sessionID: "s1") }
        try fixture.exec("DROP TABLE local_runtime_sessions; CREATE TABLE local_runtime_sessions(session_id TEXT PRIMARY KEY, visibility TEXT, archived TEXT)")
        #expect(throws: MiniMaxCodeConversationPresenceReader.ReadError.incompatibleSchema) { try reader.read(sessionID: "s1") }
        try fixture.exec("DROP TABLE local_runtime_sessions; DROP TABLE private_messages; CREATE TABLE private_messages(session_id TEXT,body TEXT); CREATE VIEW local_runtime_sessions AS SELECT session_id,body AS visibility,0 AS archived FROM private_messages")
        #expect(throws: MiniMaxCodeConversationPresenceReader.ReadError.incompatibleSchema) { try reader.read(sessionID: "s1") }
    }

    @Test func visibleObservationRepairsOnlyMatchingOldFalseEndWithoutSuccessAndPersistsRepair() throws {
        let fixture = try Fixture(); defer { fixture.dispose() }; try fixture.add()
        let registry = fixture.directory.appendingPathComponent("registry.json")
        var oldReducer = RuntimeLifecycleReducer(registryURL: registry)
        var old = observation(fixture); old.event = .sessionEnded
        _ = oldReducer.receive(old) // Simulate a previous shipped raw SDK SessionEnd.
        var restored = RuntimeLifecycleReducer(registryURL: registry); var state = SessionState()
        for event in restored.restoredEvents { state.apply(event) }
        #expect(state.sessions.first?.isSessionEnded == true)
        var monitor = MiniMaxCodeLifecycleMonitor()
        let observed = observation(fixture, at: time.addingTimeInterval(10))
        let outputs = monitor.observe(observed, now: time.addingTimeInterval(10))
        #expect(outputs.map(\.event) == [.sessionObserved]) // Old accepted turn cannot be replayed.
        let available = try #require(outputs.first)
        var foreign = available; foreign.profileID = "another-profile"
        #expect(restored.receive(foreign).isEmpty)
        foreign = available; foreign.sourceRuntimeVersion = "3.2.0"
        #expect(restored.receive(foreign).isEmpty)
        foreign = available; foreign.metadataDatabasePath = "/foreign/v2/sqlite/runtime-state.sqlite"
        #expect(restored.receive(foreign).isEmpty)
        let repaired = restored.receive(available)
        #expect(repaired.contains { if case let .sessionCompleted(value) = $0 { return value.isInterrupt == true && value.isSessionEnd == false && value.runtimeOutcome == nil }; return false })
        for event in repaired { state.apply(event) }
        #expect(state.sessions.first?.isSessionEnded == false)
        #expect(state.sessions.first?.jumpTarget?.appConversationID == "s1")
        #expect(restored.receive(available).isEmpty)
        var again = SessionState()
        for event in RuntimeLifecycleReducer(registryURL: registry).restoredEvents { again.apply(event) }
        #expect(again.sessions.first?.isSessionEnded == false)
        #expect(again.sessions.first?.phase == .completed)
    }

    @Test func ownRegistryPresenceOnlyRecoveryNeedsNoNewTaskOrTurnQuery() throws {
        let fixture = try Fixture(); defer { fixture.dispose() }; try fixture.add()
        let registry = fixture.directory.appendingPathComponent("startup-registry.json")
        var old = RuntimeLifecycleReducer(registryURL: registry)
        var ended = observation(fixture); ended.event = .sessionEnded
        _ = old.receive(ended)
        // A presence-only restoration must still work with the turn table unavailable.
        try fixture.exec("DROP TABLE local_runtime_turn_ingress")
        var restored = RuntimeLifecycleReducer(registryURL: registry)
        let admitted = try #require(restored.restoredMiniMaxDesktopObservations.first)
        var monitor = MiniMaxCodeLifecycleMonitor()
        let output = monitor.restoreDesktopPresence(admitted)
        #expect(output.map(\.event) == [.sessionObserved])
        #expect(monitor.monitoredSessionCount == 0)
        let events = output.flatMap { restored.receive($0) }
        #expect(events.contains { if case let .sessionCompleted(value) = $0 { return value.isInterrupt == true && value.isSessionEnd == false }; return false })
        var state = SessionState()
        for event in restored.restoredEvents { state.apply(event) }
        #expect(state.sessions.first?.isSessionEnded == false)
        #expect(state.sessions.first?.jumpTarget?.appConversationID == "s1")
        var foreign = admitted; foreign.sourceRuntimeVersion = "3.2.0"
        #expect(monitor.restoreDesktopPresence(foreign).isEmpty)
        foreign = admitted; foreign.source = .minimaxCodeCLI; foreign.sourceRuntimeVersion = "0.5.3"
        #expect(monitor.restoreDesktopPresence(foreign).isEmpty)
        foreign = admitted; foreign.metadataDatabasePath = "relative/runtime-state.sqlite"
        #expect(monitor.restoreDesktopPresence(foreign).isEmpty)
        foreign = admitted; foreign.appConversationID = "foreign-native-id"
        #expect(monitor.restoreDesktopPresence(foreign).isEmpty)
        #expect(monitor.observe(foreign).isEmpty)
    }

    @Test func boundedPresenceWatchesAdmitNewIdentitiesWithoutEvictingActiveTurns() throws {
        let fixture = try Fixture(); defer { fixture.dispose() }; try fixture.add()
        var monitor = MiniMaxCodeLifecycleMonitor()
        _ = monitor.observe(observation(fixture), now: time)
        let now = time.addingTimeInterval(2)
        for index in 0..<129 {
            let session = "visible-\(index)"
            try fixture.add(session: session, turn: "turn-\(index)")
            let value = observation(fixture, session: session, turn: "turn-\(index)", at: time.addingTimeInterval(Double(index) / 1000))
            let admitted = monitor.restoreDesktopPresence(value, now: now)
            #expect(admitted.first?.sessionID == session)
        }
        // Only inactive watches may leave the bounded set; the actual accepted turn stays pinned.
        #expect(monitor.monitoredSessionCount == 1)
        try fixture.exec("UPDATE local_runtime_turn_ingress SET status='completed',completed_at_ms=103000 WHERE turn_id='t1'; UPDATE local_runtime_sessions SET archived=1 WHERE session_id IN ('visible-0','visible-128')")
        let changed = monitor.poll(now: now.addingTimeInterval(2))
        #expect(changed.filter { $0.event == .turnCompleted }.map(\.sessionID) == ["s1"])
        #expect(changed.filter { $0.event == .sessionEnded }.map(\.sessionID) == ["visible-128"])
    }

    private final class Fixture {
        let directory: URL; let path: String
        private var db: OpaquePointer?
        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("minimax-presence-\(UUID())")
            let parent = directory.appendingPathComponent("v2/sqlite")
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            path = parent.appendingPathComponent("runtime-state.sqlite").path
            guard sqlite3_open(path, &db) == SQLITE_OK else { throw MiniMaxCodeConversationPresenceReader.ReadError.databaseUnavailable }
            try exec("CREATE TABLE local_runtime_sessions(session_id TEXT PRIMARY KEY,visibility TEXT NOT NULL,archived INTEGER NOT NULL,record_json TEXT NOT NULL); CREATE TABLE local_runtime_turn_ingress(turn_id TEXT PRIMARY KEY,session_id TEXT,status TEXT,accepted_at_ms INTEGER,accepted_sequence INTEGER,completed_at_ms INTEGER,input_json TEXT); CREATE TABLE private_messages(body BLOB)")
        }
        func add(session: String = "s1", turn: String = "t1") throws {
            try exec("INSERT INTO local_runtime_sessions VALUES('\(session)','visible',0,'PRIVATE_BODY_UNREADABLE'); INSERT INTO local_runtime_turn_ingress VALUES('\(turn)','\(session)','accepted',100000,1,NULL,'PRIVATE_PROMPT_UNREADABLE')")
        }
        func exec(_ sql: String) throws {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw MiniMaxCodeConversationPresenceReader.ReadError.queryUnavailable }
        }
        func dispose() { sqlite3_close(db); try? FileManager.default.removeItem(at: directory) }
    }
}
