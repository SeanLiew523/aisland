import Foundation
import SQLite3

public struct MiniMaxCodeTurnMetadata: Equatable, Sendable {
    public enum Status: String, Sendable { case accepted, completed, failed, aborted }
    public var turnID: String
    public var sessionID: String
    public var status: Status
    public var acceptedAt: Date
    public var acceptedSequence: Int
    public var completedAt: Date?
}

/// One short read-only connection per poll. Never opens payload/message tables.
public struct MiniMaxCodeMetadataReader: Sendable {
    public enum ReadError: Error, Equatable, Sendable { case invalidRequest, databaseUnavailable, incompatibleSchema, queryUnavailable, invalidMetadata }
    public let databasePath: String
    public init(databasePath: String) { self.databasePath = databasePath }

    public func read(sessionID: String, turnID: String?, minimumAcceptedAt: Date, now: Date) throws -> MiniMaxCodeTurnMetadata? {
        guard databasePath.hasPrefix("/"), Self.identity(sessionID), turnID.map(Self.identity) ?? true,
              minimumAcceptedAt.timeIntervalSince1970.isFinite, now.timeIntervalSince1970.isFinite,
              now.timeIntervalSince1970 > 0 else { throw ReadError.invalidRequest }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let db = handle else { if let handle { sqlite3_close(handle) }; throw ReadError.databaseUnavailable }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 20)
        try validateSchema(db)
        // Even an unexpected VIEW or changed source query cannot admit payload columns.
        sqlite3_set_authorizer(db, { _, action, table, column, _, _ in
            if action == SQLITE_SELECT { return SQLITE_OK }
            guard action == SQLITE_READ, let table, let column,
                  String(cString: table) == "local_runtime_turn_ingress",
                  ["turn_id", "session_id", "status", "accepted_at_ms", "accepted_sequence", "completed_at_ms"].contains(String(cString: column)) else { return SQLITE_DENY }
            return SQLITE_OK
        }, nil)
        let predicate = turnID == nil ? "accepted_at_ms >= ? ORDER BY accepted_sequence DESC" : "turn_id = ?"
        let sql = "SELECT turn_id, session_id, status, accepted_at_ms, accepted_sequence, completed_at_ms FROM local_runtime_turn_ingress WHERE session_id = ? AND \(predicate) LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            if let statement { sqlite3_finalize(statement) }; throw ReadError.queryUnavailable
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, sessionID, -1, transient) == SQLITE_OK else { throw ReadError.queryUnavailable }
        if let turnID {
            guard sqlite3_bind_text(statement, 2, turnID, -1, transient) == SQLITE_OK else { throw ReadError.queryUnavailable }
        } else {
            let floor = minimumAcceptedAt.timeIntervalSince1970 * 1000
            guard floor >= Double(Int64.min), floor < Double(Int64.max), sqlite3_bind_int64(statement, 2, Int64(floor.rounded(.down))) == SQLITE_OK else { throw ReadError.invalidRequest }
        }
        let stepped = sqlite3_step(statement)
        if stepped == SQLITE_DONE { return nil }
        guard stepped == SQLITE_ROW else { throw ReadError.queryUnavailable }
        guard let nativeTurn = Self.text(statement, 0), Self.identity(nativeTurn),
              let nativeSession = Self.text(statement, 1), nativeSession == sessionID,
              let statusText = Self.text(statement, 2), let status = MiniMaxCodeTurnMetadata.Status(rawValue: statusText),
              sqlite3_column_type(statement, 3) == SQLITE_INTEGER, sqlite3_column_type(statement, 4) == SQLITE_INTEGER else { throw ReadError.invalidMetadata }
        let acceptedMs = sqlite3_column_int64(statement, 3), sequence = sqlite3_column_int64(statement, 4)
        let accepted = Date(timeIntervalSince1970: Double(acceptedMs) / 1000)
        guard acceptedMs > 0, sequence >= 0, sequence <= Int64(Int.max), accepted <= now,
              (turnID != nil || accepted >= minimumAcceptedAt), turnID == nil || nativeTurn == turnID else { return nil }
        let completed: Date?
        if sqlite3_column_type(statement, 5) == SQLITE_NULL { completed = nil }
        else if sqlite3_column_type(statement, 5) == SQLITE_INTEGER {
            let ms = sqlite3_column_int64(statement, 5)
            guard ms >= acceptedMs else { throw ReadError.invalidMetadata }
            completed = Date(timeIntervalSince1970: Double(ms) / 1000)
            guard completed! <= now else { throw ReadError.invalidMetadata }
        } else { throw ReadError.invalidMetadata }
        guard (status == .accepted && completed == nil) || (status != .accepted && completed != nil) else { throw ReadError.invalidMetadata }
        return MiniMaxCodeTurnMetadata(turnID: nativeTurn, sessionID: nativeSession, status: status,
                                       acceptedAt: accepted, acceptedSequence: Int(sequence), completedAt: completed)
    }

    private func validateSchema(_ db: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(local_runtime_turn_ingress)", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            if let statement { sqlite3_finalize(statement) }; throw ReadError.incompatibleSchema
        }
        defer { sqlite3_finalize(statement) }
        let expected = ["turn_id": "TEXT", "session_id": "TEXT", "status": "TEXT", "accepted_at_ms": "INTEGER", "accepted_sequence": "INTEGER", "completed_at_ms": "INTEGER"]
        var matched = Set<String>(); var count = 0
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW, count < 128 else { throw ReadError.incompatibleSchema }
            count += 1
            guard let name = Self.text(statement, 1), let type = Self.text(statement, 2) else { throw ReadError.incompatibleSchema }
            if let required = expected[name] {
                guard type.uppercased() == required, !matched.contains(name) else { throw ReadError.incompatibleSchema }
                matched.insert(name)
            }
        }
        guard matched == Set(expected.keys) else { throw ReadError.incompatibleSchema }
    }
    private static func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) == SQLITE_TEXT, let bytes = sqlite3_column_text(statement, index),
              sqlite3_column_bytes(statement, index) <= 512 else { return nil }
        let count = Int(sqlite3_column_bytes(statement, index))
        return String(data: Data(bytes: bytes, count: count), encoding: .utf8)
    }
    private static func identity(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= 512
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}
