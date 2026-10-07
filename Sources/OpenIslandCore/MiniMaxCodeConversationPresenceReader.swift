import Foundation
import SQLite3

/// Reads only one previously admitted conversation's durable visibility facts.
public struct MiniMaxCodeConversationPresenceReader: Sendable {
    public enum Presence: Equatable, Sendable { case visible, archived, hidden, missing }
    public enum ReadError: Error, Equatable, Sendable { case invalidRequest, databaseUnavailable, incompatibleSchema, queryUnavailable, invalidMetadata }
    public let databasePath: String
    public init(databasePath: String) { self.databasePath = databasePath }

    public func read(sessionID: String) throws -> Presence {
        guard databasePath.hasPrefix("/"), databasePath.hasSuffix("/v2/sqlite/runtime-state.sqlite"),
              !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              sessionID.utf8.count <= 512,
              !sessionID.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw ReadError.invalidRequest }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let db = handle else { if let handle { sqlite3_close(handle) }; throw ReadError.databaseUnavailable }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 20)
        var schema: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(local_runtime_sessions)", -1, &schema, nil) == SQLITE_OK,
              let schema else { if let schema { sqlite3_finalize(schema) }; throw ReadError.incompatibleSchema }
        defer { sqlite3_finalize(schema) }
        let expected = ["session_id": "TEXT", "visibility": "TEXT", "archived": "INTEGER"]
        var found = Set<String>(); var count = 0
        while true {
            let result = sqlite3_step(schema)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW, count < 128,
                  let name = Self.text(schema, 1), let type = Self.text(schema, 2) else { throw ReadError.incompatibleSchema }
            count += 1
            if let required = expected[name] {
                guard type.uppercased() == required, !found.contains(name),
                      name != "session_id" || sqlite3_column_int(schema, 5) == 1 else { throw ReadError.incompatibleSchema }
                found.insert(name)
            }
        }
        guard found == Set(expected.keys) else { throw ReadError.incompatibleSchema }
        // A view into message/record_json data cannot pass this column whitelist.
        sqlite3_set_authorizer(db, { _, action, table, column, _, _ in
            if action == SQLITE_SELECT { return SQLITE_OK }
            guard action == SQLITE_READ, let table, let column,
                  String(cString: table) == "local_runtime_sessions",
                  ["session_id", "visibility", "archived"].contains(String(cString: column)) else { return SQLITE_DENY }
            return SQLITE_OK
        }, nil)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT session_id, visibility, archived FROM local_runtime_sessions WHERE session_id = ? LIMIT 1", -1, &statement, nil) == SQLITE_OK,
              let statement else { if let statement { sqlite3_finalize(statement) }; throw ReadError.queryUnavailable }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, sessionID, -1, transient) == SQLITE_OK else { throw ReadError.queryUnavailable }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return .missing }
        guard result == SQLITE_ROW else { throw ReadError.queryUnavailable }
        guard Self.text(statement, 0) == sessionID, let visibility = Self.text(statement, 1),
              ["visible", "hidden"].contains(visibility), sqlite3_column_type(statement, 2) == SQLITE_INTEGER else { throw ReadError.invalidMetadata }
        let archived = sqlite3_column_int64(statement, 2)
        guard archived == 0 || archived == 1 else { throw ReadError.invalidMetadata }
        return archived == 1 ? .archived : visibility == "hidden" ? .hidden : .visible
    }

    private static func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) == SQLITE_TEXT, let bytes = sqlite3_column_text(statement, index),
              sqlite3_column_bytes(statement, index) <= 512 else { return nil }
        return String(data: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index))), encoding: .utf8)
    }
}
