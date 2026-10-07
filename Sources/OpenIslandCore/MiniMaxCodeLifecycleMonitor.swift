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
    private struct PresenceWatch: Sendable {
        var observation: RuntimeLifecycleHookPayload
        var knownVisible = false
        var nextCheck: Date
        var expiresAt: Date
    }
    private var presenceWatches: [String: PresenceWatch] = [:]
    public private(set) var unavailableSessions: Set<String> = []
    public var monitoredSessionCount: Int { cursors.count }
    private let idleRetention: TimeInterval = 90
    public init() {}

    /// Owner supplies identities from AIsland's own admitted runtime registry.
    /// This never queries turns or invents a start/completion after restart.
    public mutating func restoreDesktopPresence(_ payload: RuntimeLifecycleHookPayload, now: Date = .now) -> [RuntimeLifecycleHookPayload] {
        guard payload.isValid, payload.source == .minimaxCodeDesktop, payload.event == .sessionObserved,
              payload.appConversationID == nil || payload.appConversationID == payload.sessionID,
              payload.timestamp.timeIntervalSince1970 > 0, payload.timestamp <= now,
              now.timeIntervalSince1970.isFinite else { return [] }
        let key = payload.namespacedSessionID
        guard presenceWatches[key] == nil, reserveIdentity(key) else { return [] }
        presenceWatches[key] = PresenceWatch(observation: payload, nextCheck: now, expiresAt: now.addingTimeInterval(idleRetention))
        return pollPresence(key, now: now, force: true)
    }

    @discardableResult
    public mutating func observe(_ payload: RuntimeLifecycleHookPayload, now: Date = .now) -> [RuntimeLifecycleHookPayload] {
        guard payload.isValid, payload.source.isMiniMaxCode, now.timeIntervalSince1970.isFinite,
              payload.timestamp.timeIntervalSince1970 > 0, payload.timestamp <= now,
              payload.event == .sessionObserved || payload.event == .sessionEnded else { return [] }
        guard payload.source != .minimaxCodeDesktop || payload.appConversationID == nil || payload.appConversationID == payload.sessionID else { return [] }
        let key = payload.namespacedSessionID
        if payload.event == .sessionEnded {
            // Desktop SessionEnd also means resume_other/idle_timeout/SDK release.
            // Only durable visibility facts can end that conversation.
            if payload.source == .minimaxCodeDesktop {
                guard let previous = presenceWatches[key], payload.timestamp >= previous.observation.timestamp,
                      payload.metadataDatabasePath == previous.observation.metadataDatabasePath,
                      payload.sourceRuntimeVersion == previous.observation.sourceRuntimeVersion else { return [] }
                return pollSession(key, now: now) + pollPresence(key, now: now, force: true)
            }
            let events = pollSession(key, now: now)
            cursors.removeValue(forKey: key); unavailableSessions.remove(key)
            return events + [payload]
        }
        if let previous = presenceWatches[key] {
            guard payload.timestamp >= previous.observation.timestamp,
                  payload.metadataDatabasePath == previous.observation.metadataDatabasePath,
                  payload.sourceRuntimeVersion == previous.observation.sourceRuntimeVersion else { return [] }
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
            guard reserveIdentity(key) else { return [] }
            cursors[key] = Cursor(observation: payload, admissionFloor: payload.timestamp.addingTimeInterval(-2),
                                  targetTurnID: payload.turnID, expiresAt: now.addingTimeInterval(idleRetention))
        }
        let turns = pollSession(key, now: now)
        if payload.source == .minimaxCodeDesktop {
            var watch = presenceWatches[key] ?? PresenceWatch(observation: payload, nextCheck: now, expiresAt: now.addingTimeInterval(idleRetention))
            watch.observation = mergeMetadata(payload, watch.observation)
            watch.expiresAt = now.addingTimeInterval(idleRetention)
            presenceWatches[key] = watch
            return turns + pollPresence(key, now: now, force: true)
        }
        return turns
    }

    public mutating func poll(now: Date = .now) -> [RuntimeLifecycleHookPayload] {
        guard now.timeIntervalSince1970.isFinite, now.timeIntervalSince1970 > 0 else { return [] }
        let turns = cursors.keys.sorted().flatMap { pollSession($0, now: now) }
        return turns + presenceWatches.keys.sorted().flatMap { pollPresence($0, now: now) }
    }

    private mutating func reserveIdentity(_ key: String) -> Bool {
        let identities = Set(cursors.keys).union(presenceWatches.keys)
        if identities.contains(key) || identities.count < 128 { return true }
        // Presence watches must not permanently consume the admission budget.
        // Retain active turns; evict the oldest inactive watch, leaving its card intact.
        guard let oldest = presenceWatches.keys.filter({ cursors[$0]?.active == nil }).min(by: {
            let lhs = presenceWatches[$0]!.observation.timestamp, rhs = presenceWatches[$1]!.observation.timestamp
            return lhs == rhs ? $0 < $1 : lhs < rhs
        }) else { return false }
        presenceWatches.removeValue(forKey: oldest); cursors.removeValue(forKey: oldest); unavailableSessions.remove(oldest)
        return true
    }

    private mutating func pollPresence(_ key: String, now: Date, force: Bool = false) -> [RuntimeLifecycleHookPayload] {
        guard var watch = presenceWatches[key], force || now >= watch.nextCheck,
              let path = watch.observation.metadataDatabasePath else { return [] }
        if !watch.knownVisible && now >= watch.expiresAt { presenceWatches.removeValue(forKey: key); return [] }
        watch.nextCheck = now.addingTimeInterval(2)
        presenceWatches[key] = watch
        let presence: MiniMaxCodeConversationPresenceReader.Presence
        do { presence = try MiniMaxCodeConversationPresenceReader(databasePath: path).read(sessionID: watch.observation.sessionID) }
        catch { return [] } // Unavailable/unknown metadata is never deletion evidence.
        if presence == .missing && !watch.knownVisible { return [] }
        var projected = watch.observation
        projected.appConversationID = watch.observation.sessionID
        projected.turnID = nil; projected.sequence = nil; projected.timestamp = now
        projected.sourceObservedStart = false
        if presence == .visible {
            let newlyVisible = !watch.knownVisible
            watch.knownVisible = true; presenceWatches[key] = watch
            // Repairs only an already-ended reducer cursor, without replaying success.
            projected.event = .sessionObserved; projected.resultReason = "visible"
            return newlyVisible || force ? [projected] : []
        }
        projected.event = .sessionEnded
        projected.resultReason = presence == .archived ? "archived" : presence == .hidden ? "hidden" : "deleted"
        presenceWatches.removeValue(forKey: key); cursors.removeValue(forKey: key); unavailableSessions.remove(key)
        return [projected]
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
