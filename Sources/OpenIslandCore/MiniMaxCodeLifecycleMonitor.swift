import Foundation

/// Serialized by its owner. It creates no timer, thread, source process or DB write.
public struct MiniMaxCodeLifecycleMonitor: Sendable {
    private struct Cursor: Sendable {
        var observation: RuntimeLifecycleHookPayload
        var admissionFloor: Date
        var targetTurnID: String?
        var active: MiniMaxCodeTurnMetadata?
        var pending: RuntimeLifecycleHookPayload?
        var seenTurns: [String] = []
        var latestSequence: Int?
        var expiresAt: Date
    }
    private var cursors: [String: Cursor] = [:]
    public private(set) var unavailableSessions: Set<String> = []
    public var monitoredSessionCount: Int { cursors.count }
    private let idleRetention: TimeInterval = 90
    public init() {}

    @discardableResult
    public mutating func observe(_ payload: RuntimeLifecycleHookPayload, now: Date = .now) -> [RuntimeLifecycleHookPayload] {
        guard payload.isValid, payload.source.isMiniMaxCode, now.timeIntervalSince1970.isFinite,
              payload.timestamp.timeIntervalSince1970 > 0, payload.timestamp <= now,
              payload.event == .sessionObserved || payload.event == .sessionEnded else { return [] }
        let key = payload.namespacedSessionID
        if payload.event == .sessionEnded {
            // Session release is not a turn outcome. Settle any committed fact first.
            let events = pollSession(key, now: now)
            cursors.removeValue(forKey: key); unavailableSessions.remove(key)
            return events
        }
        if var previous = cursors[key] {
            guard payload.timestamp >= previous.observation.timestamp,
                  payload.metadataDatabasePath == previous.observation.metadataDatabasePath,
                  payload.sourceRuntimeVersion == previous.observation.sourceRuntimeVersion else { return [] }
            if let id = payload.turnID, previous.seenTurns.contains(id), previous.active?.turnID != id { return [] }
            if previous.active != nil {
                if let id = payload.turnID, id != previous.active?.turnID {
                    // Poll the current turn to its own final fact before admitting a later one.
                    previous.pending = payload
                } else {
                    previous.observation = mergeMetadata(payload, previous.observation)
                }
            } else if previous.targetTurnID == payload.turnID {
                // Repeated Stop/start observations do not move the admission floor forward.
                previous.observation = mergeMetadata(payload, previous.observation)
                previous.expiresAt = now.addingTimeInterval(idleRetention)
            } else {
                previous.observation = mergeMetadata(payload, previous.observation)
                previous.targetTurnID = payload.turnID
                previous.admissionFloor = payload.timestamp.addingTimeInterval(-2)
                previous.expiresAt = now.addingTimeInterval(idleRetention)
            }
            cursors[key] = previous
        } else {
            guard cursors.count < 128 else { return [] }
            cursors[key] = Cursor(observation: payload, admissionFloor: payload.timestamp.addingTimeInterval(-2),
                                  targetTurnID: payload.turnID, expiresAt: now.addingTimeInterval(idleRetention))
        }
        return pollSession(key, now: now)
    }

    public mutating func poll(now: Date = .now) -> [RuntimeLifecycleHookPayload] {
        guard now.timeIntervalSince1970.isFinite, now.timeIntervalSince1970 > 0 else { return [] }
        return cursors.keys.sorted().flatMap { pollSession($0, now: now) }
    }

    private mutating func pollSession(_ key: String, now: Date) -> [RuntimeLifecycleHookPayload] {
        guard var cursor = cursors[key] else { return [] }
        if now >= cursor.expiresAt {
            cursors.removeValue(forKey: key); unavailableSessions.remove(key); return []
        }
        guard let path = cursor.observation.metadataDatabasePath else { return [] }
        let row: MiniMaxCodeTurnMetadata?
        do {
            row = try MiniMaxCodeMetadataReader(databasePath: path).read(sessionID: cursor.observation.sessionID,
                  turnID: cursor.active?.turnID ?? cursor.targetTurnID, minimumAcceptedAt: cursor.admissionFloor, now: now)
            unavailableSessions.remove(key)
        } catch {
            unavailableSessions.insert(key)
            return []
        }
        guard let row else {
            if cursor.active != nil { unavailableSessions.insert(key) }
            return []
        }
        if let active = cursor.active {
            guard active.turnID == row.turnID, active.acceptedAt == row.acceptedAt,
                  active.acceptedSequence == row.acceptedSequence else { return [] }
            cursor.expiresAt = now.addingTimeInterval(idleRetention)
            if row.status == .accepted { cursors[key] = cursor; return [] }
            let end = projected(row, observation: cursor.observation, observedStart: true)
            cursor.active = nil; cursor.latestSequence = row.acceptedSequence
            appendSeen(row.turnID, to: &cursor)
            if let pending = cursor.pending {
                cursor.pending = nil; cursor.observation = mergeMetadata(pending, cursor.observation)
                cursor.targetTurnID = pending.turnID; cursor.admissionFloor = pending.timestamp.addingTimeInterval(-2)
            }
            cursors[key] = cursor
            return [end] + (cursor.targetTurnID != row.turnID ? pollSession(key, now: now) : [])
        }
        guard !cursor.seenTurns.contains(row.turnID), cursor.latestSequence.map({ row.acceptedSequence > $0 }) ?? true else { return [] }
        // Exact native identity can synchronize an older terminal after restart,
        // but cannot turn an already-running old admission into a fresh start.
        guard row.status != .accepted || row.acceptedAt >= cursor.admissionFloor else { return [] }
        cursor.targetTurnID = row.turnID; cursor.latestSequence = row.acceptedSequence
        cursor.expiresAt = now.addingTimeInterval(idleRetention)
        let result: RuntimeLifecycleHookPayload
        if row.status == .accepted {
            cursor.active = row
            result = projected(row, observation: cursor.observation, observedStart: true)
        } else {
            // Fast completion/reload: synchronize real terminal state without a fake start.
            appendSeen(row.turnID, to: &cursor)
            result = projected(row, observation: cursor.observation, observedStart: false)
        }
        cursors[key] = cursor
        return [result]
    }

    private func projected(_ row: MiniMaxCodeTurnMetadata, observation: RuntimeLifecycleHookPayload, observedStart: Bool) -> RuntimeLifecycleHookPayload {
        var result = observation
        result.turnID = row.turnID; result.sourceObservedStart = observedStart
        switch row.status {
        case .accepted: result.event = .turnStarted; result.timestamp = row.acceptedAt; result.sequence = row.acceptedSequence; result.resultReason = nil
        case .completed: result.event = .turnCompleted; result.timestamp = row.completedAt!; result.sequence = nil; result.resultReason = "completed"
        case .failed: result.event = .turnFailed; result.timestamp = row.completedAt!; result.sequence = nil; result.resultReason = "failed"
        case .aborted: result.event = .turnInterrupted; result.timestamp = row.completedAt!; result.sequence = nil; result.resultReason = "aborted"
        }
        return result
    }
    private func appendSeen(_ id: String, to cursor: inout Cursor) {
        cursor.seenTurns.append(id)
        if cursor.seenTurns.count > 256 { cursor.seenTurns.removeFirst(cursor.seenTurns.count - 256) }
    }
    private func mergeMetadata(_ incoming: RuntimeLifecycleHookPayload, _ old: RuntimeLifecycleHookPayload) -> RuntimeLifecycleHookPayload {
        var value = incoming
        value.terminalApp = value.terminalApp ?? old.terminalApp
        value.terminalSessionID = value.terminalSessionID ?? old.terminalSessionID
        value.terminalTTY = value.terminalTTY ?? old.terminalTTY
        value.appConversationID = value.appConversationID ?? old.appConversationID
        value.navigationSocketPath = value.navigationSocketPath ?? old.navigationSocketPath
        value.tmuxTarget = value.tmuxTarget ?? old.tmuxTarget
        value.tmuxSocketPath = value.tmuxSocketPath ?? old.tmuxSocketPath
        value.warpPaneUUID = value.warpPaneUUID ?? old.warpPaneUUID
        if value.cwd.isEmpty { value.cwd = old.cwd }
        return value
    }
}
