import Foundation

/// Metadata-only contract shared by Hermes CLI and the DeepSeek desktop plugin.
public struct RuntimeLifecycleHookPayload: Equatable, Codable, Sendable {
    public enum Source: String, Codable, Sendable {
        case hermesCLI, deepseekHarness, minimaxCodeDesktop, minimaxCodeCLI
        public var tool: AgentTool {
            switch self {
            case .hermesCLI: .hermesCLI
            case .deepseekHarness: .deepseekHarness
            case .minimaxCodeDesktop: .minimaxCodeDesktop
            case .minimaxCodeCLI: .minimaxCodeCLI
            }
        }
        public var isMiniMaxCode: Bool { self == .minimaxCodeDesktop || self == .minimaxCodeCLI }
    }
    public enum Event: String, Codable, Sendable {
        case turnStarted, turnCompleted, turnFailed, turnInterrupted, sessionEnded, sessionObserved
    }
    public var source: Source
    public var event: Event
    public var profileID: String
    public var sessionID: String
    public var turnID: String?
    public var sequence: Int?
    public var cwd: String
    public var timestamp: Date
    public var terminalApp: String?
    public var terminalSessionID: String?
    public var terminalTTY: String?
    public var appBundleID: String?
    public var appConversationID: String?
    public var sourceObservedStart: Bool?
    public var metadataDatabasePath: String?
    public var sourceRuntimeVersion: String?
    public var navigationSocketPath: String?
    public var resultReason: String?
    public var tmuxTarget: String?
    public var tmuxSocketPath: String?
    public var warpPaneUUID: String?

    enum CodingKeys: String, CodingKey {
        case source, event, sequence, cwd, timestamp
        case profileID = "profile_id", sessionID = "session_id", turnID = "turn_id"
        case terminalApp = "terminal_app", terminalSessionID = "terminal_session_id", terminalTTY = "terminal_tty"
        case appBundleID = "app_bundle_id", appConversationID = "app_conversation_id", resultReason = "result_reason"
        case sourceObservedStart = "source_observed_start"
        case metadataDatabasePath = "metadata_database_path", sourceRuntimeVersion = "source_runtime_version"
        case navigationSocketPath = "navigation_socket_path"
        case tmuxTarget = "tmux_target", tmuxSocketPath = "tmux_socket_path", warpPaneUUID = "warp_pane_uuid"
    }
    public init(source: Source, event: Event, profileID: String, sessionID: String, turnID: String? = nil,
                sequence: Int? = nil, cwd: String, timestamp: Date = .now, terminalApp: String? = nil,
                terminalSessionID: String? = nil, terminalTTY: String? = nil, appBundleID: String? = nil,
                appConversationID: String? = nil, resultReason: String? = nil, tmuxTarget: String? = nil,
                tmuxSocketPath: String? = nil, warpPaneUUID: String? = nil, navigationSocketPath: String? = nil, sourceObservedStart: Bool? = nil, metadataDatabasePath: String? = nil, sourceRuntimeVersion: String? = nil) {
        self.source = source; self.event = event; self.profileID = profileID; self.sessionID = sessionID
        self.turnID = turnID; self.sequence = sequence; self.cwd = cwd; self.timestamp = timestamp
        self.terminalApp = terminalApp; self.terminalSessionID = terminalSessionID; self.terminalTTY = terminalTTY
        self.appBundleID = appBundleID; self.appConversationID = appConversationID; self.resultReason = resultReason
        self.sourceObservedStart = sourceObservedStart
        self.metadataDatabasePath = metadataDatabasePath; self.sourceRuntimeVersion = sourceRuntimeVersion
        self.navigationSocketPath = navigationSocketPath
        self.tmuxTarget = tmuxTarget; self.tmuxSocketPath = tmuxSocketPath; self.warpPaneUUID = warpPaneUUID
    }
    /// Length-prefixed identity avoids delimiter collisions across profile/session IDs.
    public var namespacedSessionID: String {
        "runtime:\(source.rawValue):\(profileID.utf8.count):\(profileID):\(sessionID)"
    }
    public static let hermesResultReasons: Set<String> = [
        "unknown", "text_response", "budget_exhausted", "max_iterations_reached", "pending_tool_result",
        "context_compression_exhausted", "context_compression_timeout", "compaction_handoff_not_actionable",
        "ollama_runtime_context_too_small", "interpreter_shutdown", "local_processing_error", "repeated_outer_errors",
        "error_near_max_iterations", "session_persistence_failed", "guardrail_halt", "partial_stream_recovery",
        "fallback_prior_turn_content", "empty_response_exhausted", "interrupted_by_system", "interrupted_during_api_call",
        "review_input_budget_exhausted", "redirect_restart_limit_exceeded", "rebuilt_restart_limit_exceeded",
        "all_retries_exhausted_no_response"
    ]
    public var isValid: Bool {
        func identity(_ value: String?, maximum: Int, required: Bool = false) -> Bool {
            guard let value else { return !required }
            return (!required || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                && value.utf8.count <= maximum && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        }
        if event == .sessionObserved {
            guard source.isMiniMaxCode,
                  let path = metadataDatabasePath, path.hasPrefix("/"), path.hasSuffix("/v2/sqlite/runtime-state.sqlite"),
                  sourceRuntimeVersion == (source == .minimaxCodeDesktop ? "3.1.0" : "0.5.3") else { return false }
        }
        let reasons: Set<String> = source.isMiniMaxCode ? ["completed", "failed", "aborted", "unknown"] : source == .hermesCLI ? Self.hermesResultReasons : ["completed", "error", "blocked", "max-tokens", "aborted:user", "aborted:parent", "aborted:hook", "aborted:disposed", "aborted:legacy", "aborted:unknown", "interrupted", "forked", "unknown"]
        return identity(profileID, maximum: 1024, required: true) && identity(sessionID, maximum: 512, required: true)
            && identity(turnID, maximum: 512, required: event != .sessionEnded && event != .sessionObserved)
            && identity(cwd, maximum: 4096) && identity(terminalApp, maximum: 128)
            && identity(terminalSessionID, maximum: 512) && identity(terminalTTY, maximum: 128)
            && identity(appBundleID, maximum: 255) && identity(appConversationID, maximum: 512)
            && identity(metadataDatabasePath, maximum: 4096) && identity(sourceRuntimeVersion, maximum: 64)
            && identity(navigationSocketPath, maximum: 4096) && identity(tmuxTarget, maximum: 128)
            && identity(tmuxSocketPath, maximum: 4096) && identity(warpPaneUUID, maximum: 128)
            && (sequence == nil || sequence! >= 0) && timestamp.timeIntervalSince1970.isFinite
            && (resultReason == nil || reasons.contains(resultReason!))
    }
    public var jumpTarget: JumpTarget {
        JumpTarget(terminalApp: source == .deepseekHarness ? "DeepSeek Harness.app" : source == .minimaxCodeDesktop ? "MiniMax Code.app" : (terminalApp ?? "Unknown"),
                   workspaceName: WorkspaceNameResolver.workspaceName(for: cwd), paneTitle: source.tool.displayName,
                   workingDirectory: cwd.isEmpty ? nil : cwd, terminalSessionID: terminalSessionID,
                   terminalTTY: terminalTTY, tmuxTarget: tmuxTarget, tmuxSocketPath: tmuxSocketPath,
                   warpPaneUUID: warpPaneUUID, appConversationID: appConversationID,
                   runtimeProfileID: profileID, runtimeNavigationSocketPath: navigationSocketPath,
                   runtimeMetadataDatabasePath: metadataDatabasePath, runtimeSourceVersion: sourceRuntimeVersion)
    }
}

/// Only a live, observed matching turn can produce a success notification.
/// Persisted starts are intentionally restored as unobserved after a bridge restart.
public struct RuntimeLifecycleReducer: Sendable {
    private struct Cursor: Codable, Sendable {
        var turnID: String?
        var timestamp: Date
        var sequence: Int?
        var finished: Bool
        var observedStart: Bool
        var seenTurns: Set<String>
        var sessionEnded: Bool
        var lastPayload: RuntimeLifecycleHookPayload
    }
    private var cursors: [String: Cursor] = [:]
    private let registryURL: URL?
    public init(registryURL: URL? = nil) {
        self.registryURL = registryURL
        if let registryURL, let data = try? Data(contentsOf: registryURL),
           let stored = try? JSONDecoder().decode([String: Cursor].self, from: data) {
            cursors = stored.mapValues { cursor in var value = cursor; value.observedStart = false; return value }
        }
    }
    /// Restore metadata and phase without replaying a completion notification.
    public var restoredEvents: [AgentEvent] {
        cursors.keys.sorted().flatMap { id -> [AgentEvent] in
            guard let cursor = cursors[id], !cursor.observedStart else { return [] }
            let payload = cursor.lastPayload
            var events = [AgentEvent.sessionStarted(SessionStarted(sessionID: id,
                title: "\(payload.source.tool.displayName) · \(WorkspaceNameResolver.workspaceName(for: payload.cwd))",
                tool: payload.source.tool, origin: .live, initialPhase: cursor.finished ? .completed : .running,
                summary: cursor.finished ? "Restored turn state" : "Running", timestamp: payload.timestamp, jumpTarget: payload.jumpTarget))]
            if cursor.finished {
                events.append(.sessionCompleted(SessionCompleted(sessionID: id,
                    summary: payload.event == .turnCompleted ? "Turn completed" : payload.event == .turnFailed ? "Turn failed" : payload.event == .turnInterrupted ? "Turn interrupted" : "Session ended",
                    timestamp: payload.timestamp, isInterrupt: true, isSessionEnd: cursor.sessionEnded,
                    runtimeOutcome: payload.event == .turnCompleted ? .succeeded : payload.event == .turnFailed ? .failed : payload.event == .turnInterrupted ? .interrupted : .ended)))
            }
            return events
        }
    }

    public mutating func receive(_ incoming: RuntimeLifecycleHookPayload) -> [AgentEvent] {
        guard incoming.isValid, incoming.event != .sessionObserved else { return [] }
        var payload = incoming
        let id = payload.namespacedSessionID
        let previous = cursors[id]
        if let old = previous?.lastPayload {
            payload.terminalApp = payload.terminalApp ?? old.terminalApp
            payload.terminalSessionID = payload.terminalSessionID ?? old.terminalSessionID
            payload.terminalTTY = payload.terminalTTY ?? old.terminalTTY
            payload.appConversationID = payload.appConversationID ?? old.appConversationID
            payload.navigationSocketPath = payload.navigationSocketPath ?? old.navigationSocketPath
            payload.tmuxTarget = payload.tmuxTarget ?? old.tmuxTarget
            payload.tmuxSocketPath = payload.tmuxSocketPath ?? old.tmuxSocketPath
            payload.warpPaneUUID = payload.warpPaneUUID ?? old.warpPaneUUID
            if payload.cwd.isEmpty { payload.cwd = old.cwd }
        }
        if let previous {
            guard payload.timestamp >= previous.timestamp else { return [] }
            if let sequence = payload.sequence, let oldSequence = previous.sequence, sequence <= oldSequence { return [] }
            // MiniMax's reader may first observe a committed terminal for a
            // newer native turn. Synchronize it silently after a finished or
            // restored-unobserved cursor; never replace a live observed turn.
            // BridgeServer admits MiniMax outcomes only through its DB monitor.
            let synchronizesNewNativeTerminal = payload.source.isMiniMaxCode
                && payload.sourceObservedStart == false
                && [.turnCompleted, .turnFailed, .turnInterrupted].contains(payload.event)
                && !previous.observedStart
                && payload.sourceRuntimeVersion == (payload.source == .minimaxCodeDesktop ? "3.1.0" : "0.5.3")
                && payload.metadataDatabasePath?.hasPrefix("/") == true
                && payload.metadataDatabasePath?.hasSuffix("/v2/sqlite/runtime-state.sqlite") == true
                && payload.turnID.map { $0 != previous.turnID && !previous.seenTurns.contains($0) } == true
            if payload.event == .turnStarted {
                // Replayed starts cannot reopen completed turns or become live after restart.
                if let turn = payload.turnID, previous.seenTurns.contains(turn) { return [] }
            } else {
                if let turn = payload.turnID, let current = previous.turnID, turn != current,
                   !synchronizesNewNativeTerminal { return [] }
                if payload.event == .sessionEnded {
                    if previous.sessionEnded { return [] }
                } else if previous.finished && !synchronizesNewNativeTerminal { return [] }
            }
        }
        let started = payload.event == .turnStarted
        let summary: String
        switch payload.event {
        case .turnStarted: summary = "Running"
        case .turnCompleted: summary = "Turn completed"
        case .turnFailed: summary = "Turn failed"
        case .turnInterrupted: summary = "Turn interrupted"
        case .sessionEnded: summary = "Session ended"
        case .sessionObserved: return []
        }
        cursors[id] = Cursor(turnID: payload.turnID ?? previous?.turnID, timestamp: payload.timestamp,
                             sequence: payload.sequence ?? previous?.sequence, finished: !started, observedStart: started,
                             seenTurns: (previous?.seenTurns ?? []).union(payload.turnID.map { [$0] } ?? []),
                             sessionEnded: payload.event == .sessionEnded, lastPayload: payload)
        if let registryURL, let data = try? JSONEncoder().encode(cursors) {
            try? FileManager.default.createDirectory(at: registryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: registryURL, options: .atomic)
        }
        var events: [AgentEvent] = []
        if previous == nil || started || previous?.observedStart == false {
            events.append(.sessionStarted(SessionStarted(sessionID: id,
                title: "\(payload.source.tool.displayName) · \(WorkspaceNameResolver.workspaceName(for: payload.cwd))",
                tool: payload.source.tool, origin: .live, initialPhase: started ? .running : .completed,
                summary: summary, timestamp: payload.timestamp, jumpTarget: payload.jumpTarget)))
        } else {
            events.append(.jumpTargetUpdated(JumpTargetUpdated(sessionID: id, jumpTarget: payload.jumpTarget, timestamp: payload.timestamp)))
        }
        if !started {
            let success = payload.event == .turnCompleted && previous?.observedStart == true && payload.sourceObservedStart != false
            events.append(.sessionCompleted(SessionCompleted(sessionID: id, summary: summary,
                timestamp: payload.timestamp, isInterrupt: !success, isSessionEnd: payload.event == .sessionEnded,
                runtimeOutcome: payload.event == .turnCompleted ? .succeeded : payload.event == .turnFailed ? .failed : payload.event == .turnInterrupted ? .interrupted : .ended)))
        }
        return events
    }
}
