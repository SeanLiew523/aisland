import Foundation
import SQLite3
import Testing
@testable import OpenIslandCore

struct MiniMaxCodeNavigationMetadataTests {
    @Test func exactBoundIdentityAndOnlyMetadataAreReturned() throws {
        let fixture = try NavigationFixture(); defer { fixture.dispose() }
        try fixture.insert(id: "mvs_quoted'ID", title: "回复特定字符串")
        let row = try fixture.reader.conversation(sessionID: "mvs_quoted'ID", sourceVersion: "3.1.0")
        #expect(row?.sessionID == "mvs_quoted'ID")
        #expect(row?.title == "回复特定字符串")
        #expect(row?.workspacePath == "/tmp/synthetic-workspace")
        #expect(row?.projectID == 67)
        #expect(try fixture.reader.conversation(sessionID: "missing' OR 1=1 --", sourceVersion: "3.1.0") == nil)
        #expect(try fixture.reader.conversation(sessionID: "missing", sourceVersion: "3.1.0") == nil)
    }

    @Test func duplicateNormalizedTitleAcrossProjectsIsUnavailable() throws {
        let fixture = try NavigationFixture(); defer { fixture.dispose() }
        try fixture.insert(id: "first", title: "同名任务")
        try fixture.insert(id: "second", title: "\u{3000}同名任务\u{00a0}", project: 68)
        #expect(throws: MiniMaxCodeNavigationMetadata.ReadError.ambiguousTitle) {
            try fixture.reader.conversation(sessionID: "first", sourceVersion: "3.1.0")
        }
        try fixture.exec("UPDATE local_runtime_sessions SET archived=1 WHERE session_id='second'")
        #expect(throws: MiniMaxCodeNavigationMetadata.ReadError.ambiguousTitle) {
            try fixture.reader.conversation(sessionID: "first", sourceVersion: "3.1.0")
        }
    }

    @Test func hiddenOldAndChildTitleCollisionsCannotProveSelectionWithoutCopy() throws {
        for mutation in ["visibility='hidden'", "columnar_version=2", "parent_session_id='first'", "session_kind='peek'"] {
            let fixture = try NavigationFixture(); defer { fixture.dispose() }
            try fixture.insert(id: "first", title: "Same local title")
            try fixture.insert(id: "second", title: "Same local title", project: 68)
            try fixture.exec("UPDATE local_runtime_sessions SET \(mutation) WHERE session_id='second'")
            #expect(throws: MiniMaxCodeNavigationMetadata.ReadError.ambiguousTitle) {
                try fixture.reader.conversation(sessionID: "first", sourceVersion: "3.1.1")
            }
        }
    }

    @Test func hiddenArchivedOldAndChildSessionsAreNeverAdmitted() throws {
        for mutation in ["archived=1", "visibility='hidden'", "columnar_version=2", "session_kind='peek'"] {
            let fixture = try NavigationFixture(); defer { fixture.dispose() }
            try fixture.insert(); try fixture.exec("UPDATE local_runtime_sessions SET \(mutation)")
            #expect(try fixture.reader.conversation(sessionID: "observed", sourceVersion: "3.1.0") == nil)
        }
        let fixture = try NavigationFixture(); defer { fixture.dispose() }; try fixture.insert()
        try fixture.exec("UPDATE local_runtime_sessions SET parent_session_id='parent'")
        #expect(throws: MiniMaxCodeNavigationMetadata.ReadError.invalidMetadata) {
            try fixture.reader.conversation(sessionID: "observed", sourceVersion: "3.1.0")
        }
    }

    @Test func ordinaryDefaultWorkspaceConversationIsAdmitted() throws {
        let fixture = try NavigationFixture(); defer { fixture.dispose() }; try fixture.insert()
        try fixture.exec("UPDATE local_runtime_sessions SET is_default_workspace=1, session_kind='conversation', project_id=5")
        let record = try #require(try fixture.reader.conversation(sessionID: "observed", sourceVersion: "3.1.0"))
        #expect(record.sessionID == "observed")
        #expect(record.isDefaultWorkspace)
        #expect(try fixture.reader.conversation(sessionID: "observed", sourceVersion: "3.1.1") == record)
    }

    @Test func versionSchemaViewsAndInvalidProjectFlagFailClosed() throws {
        let fixture = try NavigationFixture(); defer { fixture.dispose() }; try fixture.insert()
        #expect(throws: MiniMaxCodeNavigationMetadata.ReadError.unsupportedVersion) {
            try fixture.reader.conversation(sessionID: "observed", sourceVersion: "3.2.0")
        }
        try fixture.exec("UPDATE local_runtime_sessions SET is_default_workspace=2")
        #expect(throws: MiniMaxCodeNavigationMetadata.ReadError.unsupportedProject) {
            try fixture.reader.conversation(sessionID: "observed", sourceVersion: "3.1.0")
        }
        try fixture.exec("ALTER TABLE local_runtime_sessions RENAME TO private_payload; CREATE VIEW local_runtime_sessions AS SELECT * FROM private_payload")
        #expect(throws: MiniMaxCodeNavigationMetadata.ReadError.incompatibleSchema) {
            try fixture.reader.conversation(sessionID: "observed", sourceVersion: "3.1.0")
        }
        try fixture.exec("DROP VIEW local_runtime_sessions; CREATE TABLE local_runtime_sessions(session_id TEXT PRIMARY KEY,title TEXT)")
        #expect(throws: MiniMaxCodeNavigationMetadata.ReadError.incompatibleSchema) {
            try fixture.reader.conversation(sessionID: "observed", sourceVersion: "3.1.0")
        }
    }

    @Test func invalidTypedValuesAreRejectedAndMissingFileIsNeverCreated() throws {
        let fixture = try NavigationFixture(); defer { fixture.dispose() }; try fixture.insert()
        try fixture.exec("UPDATE local_runtime_sessions SET project_id='not-an-integer'")
        #expect(throws: MiniMaxCodeNavigationMetadata.ReadError.invalidMetadata) {
            try fixture.reader.conversation(sessionID: "observed", sourceVersion: "3.1.0")
        }
        let missing = fixture.directory.appendingPathComponent("missing/v2/sqlite/runtime-state.sqlite").path
        #expect(throws: MiniMaxCodeNavigationMetadata.ReadError.databaseUnavailable) {
            try MiniMaxCodeNavigationMetadata(databasePath: missing).conversation(sessionID: "observed", sourceVersion: "3.1.0")
        }
        #expect(!FileManager.default.fileExists(atPath: missing))
        #expect(throws: MiniMaxCodeNavigationMetadata.ReadError.invalidRequest) {
            try MiniMaxCodeNavigationMetadata(databasePath: "/tmp/arbitrary.sqlite").conversation(sessionID: "observed", sourceVersion: "3.1.0")
        }
    }

    @Test func walReadsCommittedSnapshotWithoutMutatingSource() throws {
        let fixture = try NavigationFixture(); defer { fixture.dispose() }; try fixture.insert()
        try fixture.exec("PRAGMA journal_mode=WAL; BEGIN IMMEDIATE; UPDATE local_runtime_sessions SET title='uncommitted'")
        #expect(try fixture.reader.conversation(sessionID: "observed", sourceVersion: "3.1.0")?.title == "Synthetic task")
        try fixture.exec("ROLLBACK")
        #expect(try fixture.reader.conversation(sessionID: "observed", sourceVersion: "3.1.0")?.title == "Synthetic task")
    }
}

private final class NavigationFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("minimax-nav-" + UUID().uuidString)
    var db: OpaquePointer?
    var path: String { directory.appendingPathComponent("v2/sqlite/runtime-state.sqlite").path }
    var reader: MiniMaxCodeNavigationMetadata { .init(databasePath: path) }
    init() throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw FixtureError.sqlite }
        try exec("""
        CREATE TABLE local_runtime_sessions(session_id TEXT PRIMARY KEY,title TEXT,workspace_dir TEXT,
        project_workspace_dir TEXT,project_id INTEGER,visibility TEXT,archived INTEGER,columnar_version INTEGER,
        is_default_workspace INTEGER,parent_session_id TEXT,session_kind TEXT,
        record_json TEXT,error_message TEXT,input_payload TEXT);
        """)
    }
    func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw FixtureError.sqlite }
    }
    func insert(id: String = "observed", title: String = "Synthetic task", project: Int = 67) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO local_runtime_sessions VALUES(?,?, '/tmp/synthetic-workspace','/tmp/synthetic-workspace',?, 'visible',0,3,0,NULL,'task','PRIVATE_SENTINEL','PRIVATE_SENTINEL','PRIVATE_SENTINEL')", -1, &statement, nil) == SQLITE_OK else { throw FixtureError.sqlite }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, id, -1, transient); sqlite3_bind_text(statement, 2, title, -1, transient)
        sqlite3_bind_int(statement, 3, Int32(project))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw FixtureError.sqlite }
    }
    func dispose() { sqlite3_close(db); db = nil; try? FileManager.default.removeItem(at: directory) }
    enum FixtureError: Error { case sqlite }
}
