import Foundation
import SQLite3
import Testing
@testable import OpenIslandCore

struct MiniMaxCodeMetadataTests {
    private let time = Date(timeIntervalSince1970: 100)
    private func observation(_ fixture: Fixture, turn: String? = "t1", session: String = "s1", profile: String = "desktop-test",
                             source: RuntimeLifecycleHookPayload.Source = .minimaxCodeDesktop, timestamp: Date? = nil) -> RuntimeLifecycleHookPayload {
        RuntimeLifecycleHookPayload(source: source, event: .sessionObserved, profileID: profile, sessionID: session,
            turnID: turn, cwd: "/tmp/source-test", timestamp: timestamp ?? time,
            terminalApp: "iTerm", terminalSessionID: "original-pane", appConversationID: session,
            metadataDatabasePath: fixture.path, sourceRuntimeVersion: source == .minimaxCodeDesktop ? "3.1.0" : "0.5.3")
    }
    private func succeeds(_ events: [AgentEvent]) -> Bool {
        events.contains { if case let .sessionCompleted(value) = $0 { return value.isInterrupt != true }; return false }
    }
    @Test func acceptedCommittedOutcomesAndDuplicatesUseRealReducer() throws {
        for status in ["completed", "failed", "aborted"] {
            let fixture = try Fixture(); defer { fixture.dispose() }
            try fixture.insert()
            var monitor = MiniMaxCodeLifecycleMonitor(); var reducer = RuntimeLifecycleReducer()
            let start = monitor.observe(observation(fixture), now: time)
            #expect(start.count == 1); #expect(start.first?.event == .turnStarted)
            #expect(start.first?.timestamp == time); #expect(start.first?.sequence == 1)
            _ = start.flatMap { reducer.receive($0) }
            #expect(monitor.observe(observation(fixture), now: time).isEmpty)
            try fixture.exec("UPDATE local_runtime_turn_ingress SET status='\(status)',completed_at_ms=101000 WHERE session_id='s1' AND turn_id='t1'")
            let end = monitor.poll(now: time.addingTimeInterval(1))
            #expect(end.count == 1); #expect(end.first?.sequence == nil)
            #expect(end.first?.timestamp == time.addingTimeInterval(1))
            #expect(end.first?.terminalSessionID == "original-pane")
            #expect(succeeds(end.flatMap { reducer.receive($0) }) == (status == "completed"))
            #expect(monitor.poll(now: time.addingTimeInterval(2)).isEmpty)
            #expect(monitor.observe(observation(fixture, timestamp: time.addingTimeInterval(3)), now: time.addingTimeInterval(3)).isEmpty)
        }
    }
    @Test func walSnapshotNeverObservesAnUncommittedTerminal() throws {
        let fixture = try Fixture(); defer { fixture.dispose() }
        try fixture.exec("PRAGMA journal_mode=WAL"); try fixture.insert()
        let reader = MiniMaxCodeMetadataReader(databasePath: fixture.path)
        try fixture.exec("BEGIN IMMEDIATE; UPDATE local_runtime_turn_ingress SET status='completed',completed_at_ms=101000 WHERE turn_id='t1'")
        let before = try reader.read(sessionID: "s1", turnID: "t1", minimumAcceptedAt: time.addingTimeInterval(-2), now: time.addingTimeInterval(1))
        #expect(before?.status == .accepted)
        try fixture.exec("COMMIT")
        let after = try reader.read(sessionID: "s1", turnID: "t1", minimumAcceptedAt: time.addingTimeInterval(-2), now: time.addingTimeInterval(1))
        #expect(after?.status == .completed)
    }
    @Test func boundIdentityDiscoveryCannotReadAnotherSessionOrOldRow() throws {
        let fixture = try Fixture(); defer { fixture.dispose() }
        try fixture.insert(turn: "old", session: "s1", accepted: 90000, sequence: 1)
        try fixture.insert(turn: "unrelated", session: "s2", accepted: 100000, sequence: 100)
        let reader = MiniMaxCodeMetadataReader(databasePath: fixture.path)
        #expect(try reader.read(sessionID: "s1", turnID: nil, minimumAcceptedAt: time.addingTimeInterval(-2), now: time) == nil)
        #expect(try reader.read(sessionID: "s1", turnID: "unrelated", minimumAcceptedAt: time.addingTimeInterval(-2), now: time) == nil)
        try fixture.insert(turn: "native-new", session: "s1", accepted: 100000, sequence: 2)
        let row = try reader.read(sessionID: "s1", turnID: nil, minimumAcceptedAt: time.addingTimeInterval(-2), now: time)
        #expect(row?.turnID == "native-new")
        #expect(try reader.read(sessionID: "s1' OR 1=1 --", turnID: nil, minimumAcceptedAt: time.addingTimeInterval(-2), now: time) == nil)
    }
    @Test func noFakeStartOrSuccessForTerminalFirstOrRestart() throws {
        let fixture = try Fixture(); defer { fixture.dispose() }
        try fixture.insert(status: "completed", completed: 101000)
        var monitor = MiniMaxCodeLifecycleMonitor(); var reducer = RuntimeLifecycleReducer()
        let output = monitor.observe(observation(fixture), now: time.addingTimeInterval(1))
        #expect(output.count == 1); #expect(output.first?.event == .turnCompleted)
        #expect(output.first?.sourceObservedStart == false)
        #expect(!succeeds(output.flatMap { reducer.receive($0) }))
        #expect(monitor.poll(now: time.addingTimeInterval(2)).isEmpty)
        let registry = fixture.directory.appendingPathComponent("isolated-registry.json")
        var initial = RuntimeLifecycleReducer(registryURL: registry)
        var start = observation(fixture); start.event = .turnStarted
        _ = initial.receive(start)
        var restored = RuntimeLifecycleReducer(registryURL: registry)
        var afterRestart = MiniMaxCodeLifecycleMonitor()
        let recovered = afterRestart.observe(observation(fixture, timestamp: time.addingTimeInterval(60)), now: time.addingTimeInterval(60))
        #expect(recovered.count == 1); #expect(recovered.first?.sourceObservedStart == false)
        #expect(!succeeds(recovered.flatMap { restored.receive($0) }))
    }
    @Test func oldAcceptedAdmissionIsNeverReopenedAsANewStart() throws {
        let fixture = try Fixture(); defer { fixture.dispose() }; try fixture.insert()
        var monitor = MiniMaxCodeLifecycleMonitor(); var reducer = RuntimeLifecycleReducer()
        let late = observation(fixture, timestamp: time.addingTimeInterval(60))
        #expect(monitor.observe(late, now: time.addingTimeInterval(60)).isEmpty)
        try fixture.exec("UPDATE local_runtime_turn_ingress SET status='completed',completed_at_ms=161000 WHERE turn_id='t1'")
        let end = monitor.poll(now: time.addingTimeInterval(61))
        #expect(end.first?.sourceObservedStart == false)
        #expect(!succeeds(end.flatMap { reducer.receive($0) }))
    }
    @Test func laterObservationCannotEndOrReopenTheWrongTurn() throws {
        let fixture = try Fixture(); defer { fixture.dispose() }
        try fixture.insert()
        var monitor = MiniMaxCodeLifecycleMonitor(); var reducer = RuntimeLifecycleReducer()
        _ = monitor.observe(observation(fixture), now: time).flatMap { reducer.receive($0) }
        try fixture.insert(turn: "t2", accepted: 101000, sequence: 2)
        #expect(monitor.observe(observation(fixture, turn: "t2", timestamp: time.addingTimeInterval(1)), now: time.addingTimeInterval(1)).isEmpty)
        try fixture.exec("UPDATE local_runtime_turn_ingress SET status='completed',completed_at_ms=101000 WHERE turn_id='t1'")
        let transition = monitor.poll(now: time.addingTimeInterval(2))
        #expect(transition.map(\.event) == [.turnCompleted, .turnStarted])
        #expect(transition.map(\.turnID) == ["t1", "t2"])
        let transitioned = transition.flatMap { reducer.receive($0) }
        #expect(transitioned.contains { if case .sessionStarted = $0 { return true }; return false })
        #expect(monitor.observe(observation(fixture, turn: "t1", timestamp: time.addingTimeInterval(3)), now: time.addingTimeInterval(3)).isEmpty)
        try fixture.exec("UPDATE local_runtime_turn_ingress SET status='aborted',completed_at_ms=104000 WHERE turn_id='t2'")
        let end = monitor.poll(now: time.addingTimeInterval(4))
        #expect(end.first?.turnID == "t2"); #expect(!succeeds(end.flatMap { reducer.receive($0) }))
    }
    @Test func repeatedStopObservationKeepsAdmissionFloorAndPinnedNativeTurn() throws {
        let fixture = try Fixture(); defer { fixture.dispose() }; try fixture.insert()
        var monitor = MiniMaxCodeLifecycleMonitor()
        _ = monitor.observe(observation(fixture), now: time)
        #expect(monitor.observe(observation(fixture, turn: nil, timestamp: time.addingTimeInterval(30)), now: time.addingTimeInterval(30)).isEmpty)
        try fixture.exec("UPDATE local_runtime_turn_ingress SET status='completed',completed_at_ms=131000 WHERE turn_id='t1'")
        let end = monitor.poll(now: time.addingTimeInterval(31))
        #expect(end.first?.turnID == "t1"); #expect(end.first?.sourceObservedStart == true)
    }
    @Test func malformedSchemaAndPrivatePayloadViewsFailClosed() throws {
        let fixture = try Fixture(); defer { fixture.dispose() }
        let reader = MiniMaxCodeMetadataReader(databasePath: fixture.path)
        try fixture.exec("DROP TABLE local_runtime_turn_ingress; CREATE TABLE local_runtime_turn_ingress (turn_id TEXT, session_id TEXT)")
        #expect(throws: MiniMaxCodeMetadataReader.ReadError.incompatibleSchema) { try reader.read(sessionID: "s1", turnID: "t1", minimumAcceptedAt: time, now: time) }
        try fixture.exec("DROP TABLE local_runtime_turn_ingress; CREATE TABLE private_messages (turn_id TEXT, session_id TEXT, status TEXT, accepted_at_ms INTEGER, accepted_sequence INTEGER, completed_at_ms INTEGER, body TEXT); CREATE VIEW local_runtime_turn_ingress AS SELECT turn_id,session_id,status,accepted_at_ms,accepted_sequence,completed_at_ms FROM private_messages")
        #expect(throws: MiniMaxCodeMetadataReader.ReadError.queryUnavailable) { try reader.read(sessionID: "s1", turnID: "t1", minimumAcceptedAt: time, now: time) }
    }
    @Test func metadataTypesAndTerminalTimesCannotBecomeSuccess() throws {
        for mutation in ["status='bogus'", "completed_at_ms='PRIVATE_ERROR'", "status='completed',completed_at_ms=99000",
                         "status='completed',completed_at_ms=200000", "accepted_at_ms='PRIVATE_PROMPT'", "turn_id=''", "accepted_sequence='PRIVATE_ARG'"] {
            let fixture = try Fixture(); defer { fixture.dispose() }; try fixture.insert()
            try fixture.exec("UPDATE local_runtime_turn_ingress SET \(mutation)")
            var monitor = MiniMaxCodeLifecycleMonitor()
            #expect(monitor.observe(observation(fixture, turn: nil), now: time).isEmpty)
        }
    }
    @Test func missingClosedDatabaseAndSourceVersionMismatchDoNotCreateOrScanFiles() throws {
        let fixture = try Fixture(); defer { fixture.dispose() }
        fixture.close(); try FileManager.default.removeItem(atPath: fixture.path)
        var monitor = MiniMaxCodeLifecycleMonitor()
        var value = observation(fixture); value.sourceRuntimeVersion = "future"
        #expect(monitor.observe(value, now: time).isEmpty); #expect(monitor.monitoredSessionCount == 0)
        #expect(monitor.observe(observation(fixture), now: time).isEmpty)
        #expect(monitor.unavailableSessions.count == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.path))
        #expect(monitor.poll(now: time.addingTimeInterval(91)).isEmpty)
        #expect(monitor.monitoredSessionCount == 0)
    }
    @Test func sourceProfilesAreIndependentAndRegistrationIsBounded() throws {
        let fixture = try Fixture(); defer { fixture.dispose() }; try fixture.insert()
        var monitor = MiniMaxCodeLifecycleMonitor(); var reducer = RuntimeLifecycleReducer()
        for source in [RuntimeLifecycleHookPayload.Source.minimaxCodeDesktop, .minimaxCodeCLI] {
            for profile in ["p1", "p2"] { _ = monitor.observe(observation(fixture, profile: profile, source: source), now: time).flatMap { reducer.receive($0) } }
        }
        #expect(monitor.monitoredSessionCount == 4)
        try fixture.exec("UPDATE local_runtime_turn_ingress SET status='completed',completed_at_ms=101000")
        let ends = monitor.poll(now: time.addingTimeInterval(1))
        #expect(ends.count == 4)
        for end in ends { #expect(succeeds(reducer.receive(end))) }
        for index in 0..<130 { _ = monitor.observe(observation(fixture, turn: nil, session: "unobserved-\(index)"), now: time.addingTimeInterval(1)) }
        #expect(monitor.monitoredSessionCount == 128)
    }

    @Test func twoNativeConversationsInOneWorkspaceKeepIndependentLifecycleAndRestoreIdentity() throws {
        let fixture = try Fixture(); defer { fixture.dispose() }
        try fixture.insert()
        try fixture.insert(turn: "t2", session: "s2", sequence: 2)
        let registry = fixture.directory.appendingPathComponent("two-session-registry.json")
        var monitor = MiniMaxCodeLifecycleMonitor()
        var reducer = RuntimeLifecycleReducer(registryURL: registry)
        var state = SessionState()
        for value in [observation(fixture), observation(fixture, turn: "t2", session: "s2")] {
            for event in monitor.observe(value, now: time).flatMap({ reducer.receive($0) }) { state.apply(event) }
        }
        #expect(monitor.monitoredSessionCount == 2)
        #expect(state.liveRunningCount == 2)
        try fixture.exec("UPDATE local_runtime_turn_ingress SET status='completed',completed_at_ms=101000 WHERE session_id='s1' AND turn_id='t1'")
        let ends = monitor.poll(now: time.addingTimeInterval(1))
        #expect(ends.map(\.sessionID) == ["s1"])
        for event in ends.flatMap({ reducer.receive($0) }) { state.apply(event) }
        #expect(state.liveRunningCount == 1)
        #expect(state.sessions.count == 2)
        let targets = Dictionary(uniqueKeysWithValues: state.sessions.map { ($0.id, $0.jumpTarget) })
        var restored = SessionState()
        for event in RuntimeLifecycleReducer(registryURL: registry).restoredEvents { restored.apply(event) }
        #expect(restored.sessions.count == 2)
        #expect(restored.liveRunningCount == 1)
        #expect(Dictionary(uniqueKeysWithValues: restored.sessions.map { ($0.id, $0.jumpTarget) }) == targets)
        for _ in 0..<3 {
            let alive = MiniMaxCodeDesktopLiveness.aliveSessionIDs(in: restored.sessions, runningSourceVersions: ["3.1.0"])
            _ = restored.markProcessLiveness(aliveSessionIDs: alive)
            _ = restored.removeInvisibleSessions()
        }
        #expect(restored.sessions.count == 2)
        #expect(Set(restored.sessions.compactMap { $0.jumpTarget?.appConversationID }) == ["s1", "s2"])
    }

    @Test func subsequentTerminalFirstNativeTurnSynchronizesWithoutSuccessOrReplay() throws {
        for status in ["completed", "failed", "aborted"] {
            let fixture = try Fixture(); defer { fixture.dispose() }
            try fixture.insert()
            var monitor = MiniMaxCodeLifecycleMonitor()
            var reducer = RuntimeLifecycleReducer()
            var state = SessionState()
            for event in monitor.observe(observation(fixture), now: time).flatMap({ reducer.receive($0) }) { state.apply(event) }
            try fixture.exec("UPDATE local_runtime_turn_ingress SET status='completed',completed_at_ms=101000 WHERE turn_id='t1'")
            for event in monitor.poll(now: time.addingTimeInterval(1)).flatMap({ reducer.receive($0) }) { state.apply(event) }
            try fixture.insert(turn: "t2", status: status, accepted: 102000, sequence: 2, completed: 103000)
            let end = try #require(monitor.observe(observation(fixture, turn: "t2", timestamp: time.addingTimeInterval(3)), now: time.addingTimeInterval(3)).first)
            #expect(end.sourceObservedStart == false)
            let synchronized = reducer.receive(end)
            #expect(synchronized.count == 2)
            #expect(!succeeds(synchronized))
            for event in synchronized { state.apply(event) }
            #expect(state.sessions.first?.updatedAt == time.addingTimeInterval(3))
            #expect(state.sessions.first?.runtimeOutcome == (status == "completed" ? .succeeded : status == "failed" ? .failed : .interrupted))
            #expect(reducer.receive(end).isEmpty)
            var oldReplay = end; oldReplay.turnID = "t1"; oldReplay.timestamp = time.addingTimeInterval(4)
            #expect(reducer.receive(oldReplay).isEmpty)
        }
    }

    @Test func restoredUnobservedRunningTurnCanSynchronizeANewerTerminalButLiveTurnCannot() throws {
        let fixture = try Fixture(); defer { fixture.dispose() }; try fixture.insert()
        let registry = fixture.directory.appendingPathComponent("running-registry.json")
        var firstMonitor = MiniMaxCodeLifecycleMonitor()
        var firstReducer = RuntimeLifecycleReducer(registryURL: registry)
        _ = firstMonitor.observe(observation(fixture), now: time).flatMap { firstReducer.receive($0) }
        try fixture.exec("UPDATE local_runtime_turn_ingress SET status='completed',completed_at_ms=101000 WHERE turn_id='t1'")
        try fixture.insert(turn: "t2", status: "completed", accepted: 102000, sequence: 2, completed: 103000)
        var newMonitor = MiniMaxCodeLifecycleMonitor()
        let end = try #require(newMonitor.observe(observation(fixture, turn: "t2", timestamp: time.addingTimeInterval(3)), now: time.addingTimeInterval(3)).first)
        // A genuinely observed current start cannot be ended by another turn.
        #expect(firstReducer.receive(end).isEmpty)
        var restored = RuntimeLifecycleReducer(registryURL: registry)
        let synchronized = restored.receive(end)
        #expect(synchronized.count == 2)
        #expect(!succeeds(synchronized))
        var state = SessionState()
        for event in synchronized { state.apply(event) }
        #expect(state.sessions.first?.phase == .completed)
        #expect(state.sessions.first?.jumpTarget?.appConversationID == "s1")
        var lateOld = end; lateOld.turnID = "t1"; lateOld.timestamp = time.addingTimeInterval(4)
        #expect(restored.receive(lateOld).isEmpty)
    }

    private final class Fixture {
        let directory: URL
        let path: String
        private var db: OpaquePointer?
        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("minimax-metadata-\(UUID())")
            let parent = directory.appendingPathComponent("v2/sqlite")
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            path = parent.appendingPathComponent("runtime-state.sqlite").path
            guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else { throw MiniMaxCodeMetadataReader.ReadError.databaseUnavailable }
            try exec("CREATE TABLE local_runtime_turn_ingress (turn_id TEXT PRIMARY KEY,session_id TEXT NOT NULL,status TEXT NOT NULL,accepted_at_ms INTEGER NOT NULL,accepted_sequence INTEGER,completed_at_ms INTEGER,input_json TEXT NOT NULL); CREATE TABLE unrelated (body BLOB)")
        }
        func insert(turn: String = "t1", session: String = "s1", status: String = "accepted", accepted: Int64 = 100000, sequence: Int = 1, completed: Int64? = nil) throws {
            try exec("INSERT INTO local_runtime_turn_ingress VALUES ('\(turn)','\(session)','\(status)',\(accepted),\(sequence),\(completed.map(String.init) ?? "NULL"),'{unreadable-private-payload')")
        }
        func exec(_ sql: String) throws {
            guard let db, sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw MiniMaxCodeMetadataReader.ReadError.queryUnavailable }
        }
        func close() { if let db { sqlite3_close(db); self.db = nil } }
        func dispose() { close(); try? FileManager.default.removeItem(at: directory) }
    }
}
