import Foundation
import SQLite3

public struct MiniMaxCodeConversationMetadata: Equatable, Sendable {
    public let sessionID: String
    public let title: String
    public let workspacePath: String
    public let projectWorkspacePath: String
    public let projectID: Int64
    public var isDefaultWorkspace: Bool = false
}

/// Only an already-observed session ID is admitted. Never reads record_json,
/// error/input fields, session bodies, auth, or project alias JSON.
public struct MiniMaxCodeNavigationMetadata: Sendable {
    public enum ReadError: String, Error, Equatable, Sendable {
        case invalidRequest, unsupportedVersion, databaseUnavailable, incompatibleSchema
        case queryUnavailable, invalidMetadata, unsupportedProject, ambiguousTitle
    }
    public let databasePath: String
    public init(databasePath: String) { self.databasePath = databasePath }

    public func conversation(sessionID: String, sourceVersion: String) throws -> MiniMaxCodeConversationMetadata? {
        guard MiniMaxCodeCompatibility.supportsDesktop(sourceVersion) else { throw ReadError.unsupportedVersion }
        guard databasePath.hasPrefix("/"), databasePath.hasSuffix("/v2/sqlite/runtime-state.sqlite"),
              Self.valid(sessionID, maximum: 512) else { throw ReadError.invalidRequest }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let db = handle else {
            if let handle { sqlite3_close(handle) }; throw ReadError.databaseUnavailable
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 20)
        try validateSchema(db)
        // One transaction keeps the exact row and the ambiguity check on the
        // same snapshot. Authorizer permits only the explicit read transaction.
        sqlite3_set_authorizer(db, Self.authorizer, nil)
        guard sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK else { throw ReadError.queryUnavailable }
        defer { _ = sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
        let sql = """
        SELECT session_id,title,workspace_dir,project_workspace_dir,project_id,
               visibility,archived,columnar_version,is_default_workspace,parent_session_id,session_kind
        FROM local_runtime_sessions WHERE session_id=? LIMIT 2
        """
        let statement = try prepare(sql, db: db)
        defer { sqlite3_finalize(statement) }
        try bind(sessionID, to: statement)
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return nil }
        guard step == SQLITE_ROW else { throw ReadError.queryUnavailable }
        guard let id = Self.text(statement, 0, maximum: 512), id == sessionID,
              let rawTitle = Self.text(statement, 1, maximum: 512),
              let workspace = Self.text(statement, 2, maximum: 4096), workspace.hasPrefix("/"),
              let projectPath = Self.text(statement, 3, maximum: 4096), projectPath.hasPrefix("/"),
              sqlite3_column_type(statement, 4) == SQLITE_INTEGER,
              let visibility = Self.text(statement, 5, maximum: 32),
              [6, 7, 8].allSatisfy({ sqlite3_column_type(statement, Int32($0)) == SQLITE_INTEGER }),
              sqlite3_column_type(statement, 9) == SQLITE_NULL,
              let kind = Self.text(statement, 10, maximum: 32) else { throw ReadError.invalidMetadata }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.valid(title, maximum: 512), Self.valid(workspace, maximum: 4096),
              Self.valid(projectPath, maximum: 4096), sqlite3_column_int64(statement, 4) > 0 else {
            throw ReadError.invalidMetadata
        }
        guard visibility == "visible", sqlite3_column_int64(statement, 6) == 0,
              sqlite3_column_int64(statement, 7) == 3,
              ["task", "conversation", "unknown"].contains(kind) else { return nil }
        let projectFlag = sqlite3_column_int64(statement, 8)
        guard projectFlag == 0 || projectFlag == 1 else { throw ReadError.unsupportedProject }
        let record = MiniMaxCodeConversationMetadata(sessionID: id, title: title, workspacePath: workspace,
                                                     projectWorkspacePath: projectPath,
                                                     projectID: sqlite3_column_int64(statement, 4),
                                                     isDefaultWorkspace: projectFlag == 1)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ReadError.incompatibleSchema }
        // Aggregate only: no other session's identity, title, or path leaves
        // SQLite. Conservative global uniqueness avoids project/pinned aliases.
        // Same Unicode whitespace normalization as AX title comparison.
        let whitespace = "char(9,10,11,12,13,32,133,160,5760,8192,8193,8194,8195,8196,8197,8198,8199,8200,8201,8202,8232,8233,8239,8287,12288)"
        let duplicateSQL = """
        SELECT COUNT(session_id) FROM local_runtime_sessions
        WHERE trim(title,\(whitespace))=? AND archived=0 AND visibility='visible'
              AND columnar_version=3 AND parent_session_id IS NULL
              AND session_kind IN ('task','conversation','unknown')
        """
        let duplicates = try prepare(duplicateSQL, db: db)
        defer { sqlite3_finalize(duplicates) }
        try bind(title, to: duplicates)
        guard sqlite3_step(duplicates) == SQLITE_ROW,
              sqlite3_column_type(duplicates, 0) == SQLITE_INTEGER else { throw ReadError.queryUnavailable }
        guard sqlite3_column_int64(duplicates, 0) == 1 else { throw ReadError.ambiguousTitle }
        return record
    }

    private static let columns = ["session_id": "TEXT", "title": "TEXT", "workspace_dir": "TEXT",
        "project_workspace_dir": "TEXT", "project_id": "INTEGER", "visibility": "TEXT",
        "archived": "INTEGER", "columnar_version": "INTEGER", "is_default_workspace": "INTEGER",
        "parent_session_id": "TEXT", "session_kind": "TEXT"]
    private static let authorizer: @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32 = { _, action, table, column, _, _ in
        if action == SQLITE_SELECT { return SQLITE_OK }
        if action == SQLITE_TRANSACTION, let table,
           ["BEGIN", "ROLLBACK"].contains(String(cString: table)) { return SQLITE_OK }
        if action == SQLITE_FUNCTION, let column,
           ["trim", "char", "count"].contains(String(cString: column).lowercased()) { return SQLITE_OK }
        guard action == SQLITE_READ, let table, let column,
              String(cString: table) == "local_runtime_sessions",
              columns.keys.contains(String(cString: column)) else { return SQLITE_DENY }
        return SQLITE_OK
    }
    private func validateSchema(_ db: OpaquePointer) throws {
        let type = try prepare("SELECT type FROM sqlite_master WHERE name='local_runtime_sessions'", db: db)
        defer { sqlite3_finalize(type) }
        guard sqlite3_step(type) == SQLITE_ROW, Self.text(type, 0, maximum: 16) == "table",
              sqlite3_step(type) == SQLITE_DONE else { throw ReadError.incompatibleSchema }
        let statement = try prepare("PRAGMA table_info(local_runtime_sessions)", db: db)
        defer { sqlite3_finalize(statement) }
        var matched = Set<String>(); var count = 0
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW, count < 128,
                  let name = Self.text(statement, 1, maximum: 128),
                  let type = Self.text(statement, 2, maximum: 128) else { throw ReadError.incompatibleSchema }
            count += 1
            if let expected = Self.columns[name] {
                guard type.uppercased() == expected, !matched.contains(name),
                      name != "session_id" || sqlite3_column_int(statement, 5) == 1 else {
                    throw ReadError.incompatibleSchema
                }
                matched.insert(name)
            }
        }
        guard matched == Set(Self.columns.keys) else { throw ReadError.incompatibleSchema }
    }
    private func prepare(_ sql: String, db: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            if let statement { sqlite3_finalize(statement) }; throw ReadError.queryUnavailable
        }
        return statement
    }
    private func bind(_ value: String, to statement: OpaquePointer) throws {
        guard sqlite3_bind_text(statement, 1, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK else {
            throw ReadError.queryUnavailable
        }
    }
    private static func text(_ statement: OpaquePointer, _ column: Int32, maximum: Int) -> String? {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
              sqlite3_column_bytes(statement, column) <= maximum,
              let bytes = sqlite3_column_text(statement, column) else { return nil }
        return String(data: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column))), encoding: .utf8)
    }
    private static func valid(_ value: String, maximum: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= maximum
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}
