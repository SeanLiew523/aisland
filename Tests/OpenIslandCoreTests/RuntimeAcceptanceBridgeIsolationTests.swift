import Foundation
import SQLite3
import Testing
@testable import OpenIslandCore

struct RuntimeAcceptanceBridgeIsolationTests {
    @Test func disabledMiniMaxObservationDoesNotCreateSessionOrRegistry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("acceptance-monitor-\(UUID())")
        let databaseParent = directory.appendingPathComponent("v2/sqlite")
        try FileManager.default.createDirectory(at: databaseParent,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = databaseParent.appendingPathComponent("runtime-state.sqlite")
        var db: OpaquePointer?
        #expect(sqlite3_open(database.path,&db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let now = Date(), acceptedMs = Int64(now.timeIntervalSince1970 * 1000)
        #expect(sqlite3_exec(db,"CREATE TABLE local_runtime_turn_ingress (turn_id TEXT,session_id TEXT,status TEXT,accepted_at_ms INTEGER,accepted_sequence INTEGER,completed_at_ms INTEGER,input_json TEXT); INSERT INTO local_runtime_turn_ingress VALUES ('t1','s1','accepted',\(acceptedMs),1,NULL,'synthetic test')",nil,nil,nil) == SQLITE_OK)
        let registry = directory.appendingPathComponent("isolated-registry.json")
        let socket = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socket,runtimeLifecycleRegistryURL: registry,monitorMiniMaxCode: false)
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: socket) }
        let client = BridgeCommandClient(socketURL: socket)
        let observed = RuntimeLifecycleHookPayload(source: .minimaxCodeDesktop,event: .sessionObserved,profileID: "fixture",sessionID: "s1",turnID: "t1",cwd: "/tmp/test",timestamp: now,metadataDatabasePath: database.path,sourceRuntimeVersion: "3.1.0")
        #expect(try client.send(.processRuntimeLifecycleHook(observed),timeout: 1) == .acknowledged)
        #expect(!FileManager.default.fileExists(atPath: registry.path))
        #expect(sqlite3_exec(db,"UPDATE local_runtime_turn_ingress SET status='completed',completed_at_ms=\(Int64(Date().timeIntervalSince1970 * 1000))",nil,nil,nil) == SQLITE_OK)
        // The production timer would process the observed fixture within 250ms.
        Thread.sleep(forTimeInterval: 0.3)
        #expect(!FileManager.default.fileExists(atPath: registry.path))
        // Other runtime metadata still reaches this same isolated listener.
        let hermes = RuntimeLifecycleHookPayload(source: .hermesCLI,event: .turnStarted,profileID: "fixture",sessionID: "h1",turnID: "ht1",cwd: "/tmp/test")
        #expect(try client.send(.processRuntimeLifecycleHook(hermes),timeout: 1) == .acknowledged)
        #expect(FileManager.default.fileExists(atPath: registry.path))
    }
}
