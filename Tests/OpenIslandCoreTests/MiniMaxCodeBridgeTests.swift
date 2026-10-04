import Foundation
import Darwin
import SQLite3
import Testing
@testable import OpenIslandCore

struct MiniMaxCodeBridgeTests {
    @Test func startupRepairsOwnVisibleIdentityOnlyWhenMetadataMonitoringIsEnabled() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("minimax-restore-bridge-\(UUID())")
        let databaseParent = directory.appendingPathComponent("v2/sqlite")
        try FileManager.default.createDirectory(at: databaseParent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = databaseParent.appendingPathComponent("runtime-state.sqlite")
        var db: OpaquePointer?
        #expect(sqlite3_open(database.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        // Deliberately no turn table: startup must be presence-only.
        #expect(sqlite3_exec(db, "CREATE TABLE local_runtime_sessions(session_id TEXT PRIMARY KEY,visibility TEXT,archived INTEGER,record_json TEXT); INSERT INTO local_runtime_sessions VALUES('s1','visible',0,'PRIVATE_BODY_MUST_NEVER_TRAVEL')", nil, nil, nil) == SQLITE_OK)
        for enabled in [false, true] {
            let registry = directory.appendingPathComponent("registry-\(enabled).json")
            var old = RuntimeLifecycleReducer(registryURL: registry)
            _ = old.receive(RuntimeLifecycleHookPayload(source: .minimaxCodeDesktop, event: .sessionEnded,
                profileID: "desktop-fixture", sessionID: "s1", turnID: "t1", cwd: "/tmp/test",
                timestamp: Date().addingTimeInterval(-1), appConversationID: "s1",
                metadataDatabasePath: database.path, sourceRuntimeVersion: "3.1.0"))
            let socketURL = BridgeSocketLocation.uniqueTestURL()
            let server = BridgeServer(socketURL: socketURL, runtimeLifecycleRegistryURL: registry, monitorMiniMaxCode: enabled)
            try server.start()
            defer { server.stop(); try? FileManager.default.removeItem(at: socketURL) }
            let observer = socket(AF_UNIX, SOCK_STREAM, 0)
            guard observer >= 0 else { throw BridgeTransportError.notConnected }
            defer { close(observer) }
            try disableSocketSigPipe(observer)
            try withUnixSocketAddress(path: socketURL.path) { address, length in
                guard Darwin.connect(observer, address, length) == 0 else { throw BridgeTransportError.notConnected }
            }
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            #expect(setsockopt(observer, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0)
            try writeAll(try BridgeCodec.encodeLine(.command(.registerClient(role: .observer))), to: observer)
            var buffer = Data(); var completed: SessionCompleted?
            while completed == nil {
                var bytes = [UInt8](repeating: 0, count: 16384)
                let count = read(observer, &bytes, bytes.count)
                guard count > 0 else { throw BridgeTransportError.responseTimedOut }
                let data = Data(bytes.prefix(count))
                #expect(!String(decoding: data, as: UTF8.self).contains("PRIVATE_BODY_MUST_NEVER_TRAVEL"))
                buffer.append(data)
                for envelope in try BridgeCodec.decodeLines(from: &buffer) {
                    if case let .event(.sessionCompleted(value)) = envelope { completed = value }
                }
            }
            #expect(completed?.isSessionEnd == !enabled)
            #expect(completed?.isInterrupt == true)
            #expect(enabled ? completed?.runtimeOutcome == nil : completed?.runtimeOutcome == .ended)
        }
    }

    @Test func admissionWaitsForCommittedOutcomeAndRejectsDirectTerminal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("minimax-bridge-\(UUID())")
        let databaseParent = directory.appendingPathComponent("v2/sqlite")
        try FileManager.default.createDirectory(at: databaseParent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = databaseParent.appendingPathComponent("runtime-state.sqlite")
        var db: OpaquePointer?
        #expect(sqlite3_open(database.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let now = Date()
        let acceptedMs = Int64(now.timeIntervalSince1970 * 1000)
        #expect(sqlite3_exec(db, "CREATE TABLE local_runtime_sessions(session_id TEXT PRIMARY KEY,visibility TEXT,archived INTEGER,record_json TEXT); INSERT INTO local_runtime_sessions VALUES ('s1','visible',0,'PRIVATE_BODY_MUST_NEVER_TRAVEL'); CREATE TABLE local_runtime_turn_ingress (turn_id TEXT,session_id TEXT,status TEXT,accepted_at_ms INTEGER,accepted_sequence INTEGER,completed_at_ms INTEGER,input_json TEXT); INSERT INTO local_runtime_turn_ingress VALUES ('t1','s1','accepted',\(acceptedMs),1,NULL,'PRIVATE_BODY_MUST_NEVER_TRAVEL')", nil, nil, nil) == SQLITE_OK)
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: socketURL) }
        let observer = socket(AF_UNIX, SOCK_STREAM, 0)
        guard observer >= 0 else { throw BridgeTransportError.notConnected }
        defer { close(observer) }
        try disableSocketSigPipe(observer)
        try withUnixSocketAddress(path: socketURL.path) { address, length in
            guard Darwin.connect(observer, address, length) == 0 else { throw BridgeTransportError.notConnected }
        }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        #expect(setsockopt(observer, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0)
        try writeAll(try BridgeCodec.encodeLine(.command(.registerClient(role: .observer))), to: observer)
        var buffer = Data()
        func readEnvelopes() throws -> [BridgeEnvelope] {
            var bytes = [UInt8](repeating: 0, count: 16384)
            let count = read(observer, &bytes, bytes.count)
            guard count > 0 else { throw BridgeTransportError.responseTimedOut }
            let data = Data(bytes.prefix(count))
            #expect(!String(decoding: data, as: UTF8.self).contains("PRIVATE_BODY_MUST_NEVER_TRAVEL"))
            buffer.append(data)
            return try BridgeCodec.decodeLines(from: &buffer)
        }
        var registered = false
        while !registered { registered = try readEnvelopes().contains(.response(.acknowledged)) }
        let client = BridgeCommandClient(socketURL: socketURL)
        var payload = RuntimeLifecycleHookPayload(source: .minimaxCodeDesktop, event: .sessionObserved,
            profileID: "desktop-fixture", sessionID: "s1", turnID: "t1", cwd: "/tmp/test",
            timestamp: now, metadataDatabasePath: database.path, sourceRuntimeVersion: "3.1.0")
        #expect(try client.send(.processRuntimeLifecycleHook(payload), timeout: 1) == .acknowledged)
        var events: [AgentEvent] = []
        while !events.contains(where: { if case .sessionStarted = $0 { return true }; return false }) {
            events += try readEnvelopes().compactMap { if case let .event(event) = $0 { return event }; return nil }
        }
        payload.event = .turnCompleted
        payload.resultReason = "completed"
        payload.timestamp = .now
        #expect(try client.send(.processRuntimeLifecycleHook(payload), timeout: 1) == .acknowledged)
        timeout = timeval(tv_sec: 0, tv_usec: 100000)
        #expect(setsockopt(observer, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0)
        var silentBytes = [UInt8](repeating: 0, count: 8192)
        #expect(read(observer, &silentBytes, silentBytes.count) < 0)
        let completedMs = Int64(Date().timeIntervalSince1970 * 1000)
        #expect(sqlite3_exec(db, "UPDATE local_runtime_turn_ingress SET status='completed',completed_at_ms=\(completedMs) WHERE session_id='s1' AND turn_id='t1'", nil, nil, nil) == SQLITE_OK)
        timeout = timeval(tv_sec: 2, tv_usec: 0)
        #expect(setsockopt(observer, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0)
        while !events.contains(where: { if case .sessionCompleted = $0 { return true }; return false }) {
            events += try readEnvelopes().compactMap { if case let .event(event) = $0 { return event }; return nil }
        }
        let completions = events.compactMap { if case let .sessionCompleted(value) = $0 { return value }; return nil }
        #expect(completions.count == 1)
        #expect(completions.first?.runtimeOutcome == .succeeded)
        #expect(completions.first?.isInterrupt != true)
        // Switching source conversations emits SDK SessionEnd even while visible.
        payload.event = .sessionEnded; payload.timestamp = .now
        #expect(try client.send(.processRuntimeLifecycleHook(payload), timeout: 1) == .acknowledged)
        timeout = timeval(tv_sec: 0, tv_usec: 100000)
        #expect(setsockopt(observer, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0)
        #expect(read(observer, &silentBytes, silentBytes.count) < 0)
        #expect(sqlite3_exec(db, "UPDATE local_runtime_sessions SET archived=1 WHERE session_id='s1'", nil, nil, nil) == SQLITE_OK)
        timeout = timeval(tv_sec: 3, tv_usec: 0)
        #expect(setsockopt(observer, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0)
        while !events.contains(where: { if case let .sessionCompleted(value) = $0 { return value.isSessionEnd == true }; return false }) {
            events += try readEnvelopes().compactMap { if case let .event(event) = $0 { return event }; return nil }
        }
        let ends = events.compactMap { if case let .sessionCompleted(value) = $0, value.isSessionEnd == true { return value }; return nil }
        #expect(ends.count == 1); #expect(ends.first?.runtimeOutcome == .ended)
    }
}
