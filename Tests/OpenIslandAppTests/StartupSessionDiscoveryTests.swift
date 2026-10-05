import Foundation
import Testing
import OpenIslandCore
@testable import OpenIslandApp

private actor HistoryPause {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false
    private let entered = StartupFixtureSignal()
    func waitUntilEntered() async throws { try await entered.wait() }
    func wait() async {
        isWaiting = true
        entered.signal()
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { isOpen = true; continuation?.resume(); continuation = nil }
}

private final class ScanCountingFileManager: FileManager, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    override func fileExists(atPath path: String) -> Bool {
        lock.withLock { count += 1 }
        return super.fileExists(atPath: path)
    }
    var scanCount: Int { lock.withLock { count } }
}

/// A synchronous source can pause without blocking the main actor consumer.
private final class StartupScanGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var open = false
    private var waiting = false
    private var trace: [String] = []
    private let entered = StartupFixtureSignal()
    func waitUntilEntered() async throws { try await entered.wait() }
    func record(_ event: String) { condition.lock(); trace.append(event); condition.unlock() }
    func wait() {
        condition.lock()
        waiting = true
        entered.signal()
        while !open { condition.wait() }
        condition.unlock()
    }
    func release() { condition.lock(); open = true; condition.broadcast(); condition.unlock() }
    var isWaiting: Bool { condition.lock(); defer { condition.unlock() }; return waiting }
    var events: [String] { condition.lock(); defer { condition.unlock() }; return trace }
}

@MainActor private final class DiscoveryState {
    var value = SessionState() {
        didSet {
            for watcher in watchers.values where watcher.predicate(value) { watcher.signal.signal() }
        }
    }
    private var watchers: [UUID: (predicate: (SessionState) -> Bool, signal: StartupFixtureSignal)] = [:]
    func waitFor(_ predicate: @escaping (SessionState) -> Bool) async throws {
        guard !predicate(value) else { return }
        let id = UUID(), signal = StartupFixtureSignal()
        watchers[id] = (predicate, signal)
        defer { watchers.removeValue(forKey: id) }
        try await signal.wait()
    }
}

private struct DiscoveryFixture {
    let root: URL
    let codex: CodexSessionStore
    let claude: ClaudeSessionRegistry
    let openCode: OpenCodeSessionRegistry
    let cursor: CursorSessionRegistry
    let pi: PiSessionRegistry
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("startup-discovery-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        codex = CodexSessionStore(fileURL: root.appendingPathComponent("codex.json"))
        claude = ClaudeSessionRegistry(fileURL: root.appendingPathComponent("claude.json"))
        openCode = OpenCodeSessionRegistry(fileURL: root.appendingPathComponent("opencode.json"))
        cursor = CursorSessionRegistry(fileURL: root.appendingPathComponent("cursor.json"))
        pi = PiSessionRegistry(fileURL: root.appendingPathComponent("pi.json"))
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
    @MainActor func coordinator(state: DiscoveryState, sources: SessionDiscoveryCoordinator.StartupDiscoverySources? = nil, codexFileManager: FileManager = .default) -> SessionDiscoveryCoordinator {
        let discovery = SessionDiscoveryCoordinator(codexSessionStore: codex, claudeSessionRegistry: claude,
            openCodeSessionRegistry: openCode, cursorSessionRegistry: cursor, piSessionRegistry: pi, loadArchivedCodexSessionIDs: { [] }, startupSources: sources,
            codexRolloutDiscovery: CodexRolloutDiscovery(rootURL: root.appendingPathComponent("rollouts"), fileManager: codexFileManager),
            claudeTranscriptDiscovery: ClaudeTranscriptDiscovery(rootURL: root.appendingPathComponent("transcripts")))
        discovery.stateAccessor = { state.value }
        discovery.stateUpdater = { state.value = $0 }
        return discovery
    }
    func save(_ sessions: [AgentSession]) throws {
        try codex.save(sessions.filter { $0.tool == .codex }.map(CodexTrackedSessionRecord.init(session:)))
        try claude.save(sessions.filter { $0.tool.isClaudeCodeFork }.map(ClaudeTrackedSessionRecord.init(session:)))
        try openCode.save(sessions.filter { $0.tool == .openCode }.map(OpenCodeTrackedSessionRecord.init(session:)))
        try cursor.save(sessions.filter { $0.tool == .cursor }.map(CursorTrackedSessionRecord.init(session:)))
        try pi.save(sessions.filter { $0.tool == .ohMyPi }.map(PiTrackedSessionRecord.init(session:)))
    }
    func bytes() throws -> [Data] {
        try [codex.fileURL, claude.fileURL, openCode.fileURL, cursor.fileURL, pi.fileURL].map { try Data(contentsOf: $0) }
    }
    func records() throws -> [AgentSession] {
        try codex.load().map(\.session) + claude.load().map(\.session) + openCode.load().map(\.session)
            + cursor.load().map(\.session) + pi.load().map(\.session)
    }
}

@MainActor private func waitForDiscovery(_ predicate: @MainActor () async throws -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while !(try await predicate()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    try #require(try await predicate())
}

@Suite(.timeLimit(.minutes(1)))
@MainActor struct StartupSessionDiscoveryTests {
    private func session(_ id: String, tool: AgentTool, at date: Date) -> AgentSession {
        var value = AgentSession(id: id, title: id, tool: tool, origin: .live, attachmentState: .attached,
            phase: .running, summary: "Current fixture", updatedAt: date,
            jumpTarget: JumpTarget(terminalApp: "Ghostty", workspaceName: "fixture", paneTitle: id,
                workingDirectory: "/synthetic/workspace", terminalSessionID: id),
            codexMetadata: tool == .codex ? CodexSessionMetadata(currentTool: "CurrentTool") : nil,
            claudeMetadata: tool.isClaudeCodeFork ? ClaudeSessionMetadata(transcriptPath: "/synthetic/\(id).jsonl", currentTool: "CurrentTool") : nil)
        value.isProcessAlive = true
        value.isHookManaged = true
        return value
    }

    private func payload(_ records: [AgentSession], prune: Bool = false,
        discoveredCodex: [AgentSession] = [], discoveredClaude: [AgentSession] = []) -> SessionDiscoveryCoordinator.StartupDiscoveryPayload {
        .init(codexRecords: records.filter { $0.tool == .codex }.map(CodexTrackedSessionRecord.init(session:)), codexRecordsNeedPrune: prune,
            claudeRecords: records.filter { $0.tool.isClaudeCodeFork }.map(ClaudeTrackedSessionRecord.init(session:)), claudeRecordsNeedPrune: prune,
            openCodeRecords: records.filter { $0.tool == .openCode }.map(OpenCodeTrackedSessionRecord.init(session:)), openCodeRecordsNeedPrune: prune,
            cursorRecords: records.filter { $0.tool == .cursor }.map(CursorTrackedSessionRecord.init(session:)), cursorRecordsNeedPrune: prune,
            piRecords: records.filter { $0.tool == .ohMyPi }.map(PiTrackedSessionRecord.init(session:)), piRecordsNeedPrune: prune,
            discoveredCodexRecords: discoveredCodex.map(CodexTrackedSessionRecord.init(session:)), discoveredClaudeSessions: discoveredClaude)
    }

    @Test func pausedHistoryCannotDropLiveNativeCardsOrReplaceSameIdentity() async throws {
        let fixture = try DiscoveryFixture(); defer { fixture.cleanup() }
        let state = DiscoveryState(), discovery = fixture.coordinator(state: state), pause = HistoryPause()
        let now = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970))
        let stale = session("codex-live", tool: .codex, at: now.addingTimeInterval(-60))
        let history = session("codex-history", tool: .codex, at: now.addingTimeInterval(-120))
        let snapshot = payload([stale, history])
        let applyHistory = Task { await pause.wait(); discovery.applyStartupDiscoveryPayload(snapshot) }
        defer { Task { await pause.release() } }
        try await pause.waitUntilEntered()
        #expect(await pause.isWaiting)

        for (id, tool): (String, AgentTool) in [("hermes-live", .hermesCLI), ("minimax-live", .minimaxCodeDesktop),
            ("deepseek-live", .deepseekHarness), ("codex-live", .codex)] {
            let live = session(id, tool: tool, at: now)
            state.value.apply(.sessionStarted(.init(sessionID: id, title: live.title, tool: tool, origin: .live,
                summary: live.summary, timestamp: now, jumpTarget: live.jumpTarget, codexMetadata: live.codexMetadata)))
        }
        state.value.apply(.sessionCompleted(.init(sessionID: "minimax-live", summary: "Fixture completed", timestamp: now)))
        let admitted = state.value.sessions
        await pause.release()
        await applyHistory.value
        for live in admitted { #expect(state.value.session(id: live.id) == live) }
        #expect(state.value.session(id: history.id)?.attachmentState == .stale)
        #expect(state.value.sessions.count == 5)
        try await waitForDiscovery { try fixture.codex.load().count == 2 }
    }

    @Test func everyRegistryPrunesMergedStateAndPreservesLateArrivalsAndAliases() async throws {
        let fixture = try DiscoveryFixture(); defer { fixture.cleanup() }
        let state = DiscoveryState(), discovery = fixture.coordinator(state: state)
        let now = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970))
        let tools: [AgentTool] = [.codex, .claudeCode, .openCode, .cursor, .ohMyPi]
        let current = tools.map { session("current-\($0.rawValue)", tool: $0, at: now) }
        let arrivals = tools.map { session("late-\($0.rawValue)", tool: $0, at: now) }
        let expired = tools.map { session("expired-\($0.rawValue)", tool: $0, at: now.addingTimeInterval(-172_800)) }
        state.value = SessionState(sessions: current)
        discovery.scheduleCodexSessionPersistence(); discovery.scheduleClaudeSessionPersistence()
        discovery.scheduleOpenCodeSessionPersistence(); discovery.scheduleCursorSessionPersistence(); discovery.schedulePiSessionPersistence()
        // Live events and their cache writes happen after the scan snapshot.
        state.value = SessionState(sessions: current + arrivals)
        try fixture.save(current + arrivals + expired)
        let before = try fixture.bytes()
        let stale = current.map { value in
            var old = value
            old.title = "Cached title"; old.phase = .completed; old.summary = "Cached status"
            old.updatedAt = now.addingTimeInterval(60) // History time cannot establish runtime authority.
            old.jumpTarget = JumpTarget(terminalApp: "Codex.app", workspaceName: "cached", paneTitle: "cached",
                workingDirectory: nil, terminalSessionID: "wrong-cached-target")
            old.codexMetadata = CodexSessionMetadata(currentTool: "CachedTool")
            return old
        }
        var alias = try #require(stale.first { $0.tool == .claudeCode })
        alias.id = "transcript-history-alias"
        discovery.applyStartupDiscoveryPayload(payload(stale, prune: true,
            discoveredCodex: stale.filter { $0.tool == .codex }, discoveredClaude: [alias]))
        for live in current + arrivals { #expect(state.value.session(id: live.id) == live) }
        #expect(state.value.session(id: alias.id) == nil)
        #expect(try fixture.bytes() == before) // No synchronous old-snapshot write.

        let expectedIDs = Set((current + arrivals).map(\.id))
        try await waitForDiscovery { Set(try fixture.records().map(\.id)) == expectedIDs }
        let saved = try fixture.records()
        for live in current + arrivals {
            let persisted = try #require(saved.first { $0.id == live.id })
            #expect(persisted.title == live.title && persisted.phase == live.phase)
            #expect(persisted.jumpTarget == live.jumpTarget && persisted.codexMetadata == live.codexMetadata)
        }
    }

    @Test func ordinaryRediscoveryCanStillUpdateUnprotectedSessions() throws {
        let fixture = try DiscoveryFixture(); defer { fixture.cleanup() }
        let state = DiscoveryState(), discovery = fixture.coordinator(state: state)
        let old = session("codex-existing", tool: .codex, at: .distantPast)
        state.value = SessionState(sessions: [old])
        var newer = old
        newer.title = "New discovered title"; newer.phase = .completed; newer.updatedAt = .distantFuture
        let merged = try #require(discovery.mergeDiscoveredSessions([newer]).first)
        #expect(merged.title == newer.title && merged.phase == .completed && merged.updatedAt == newer.updatedAt)
    }

    @Test func familyPersistenceKeepsSourcesAndExcludesDemoSyntheticAndForeignSessions() async throws {
        let fixture = try DiscoveryFixture(); defer { fixture.cleanup() }
        let state = DiscoveryState(), discovery = fixture.coordinator(state: state)
        let now = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970))
        let family = AgentTool.allCases.filter(\.isClaudeCodeFork).map {
            session("native-\($0.rawValue)", tool: $0, at: now)
        }
        var demo = session("demo", tool: .zcode, at: now); demo.origin = .demo
        let synthetic = session("synthetic-claude", tool: .claudeCode, at: now)
        let foreign = session("foreign", tool: .codex, at: now)
        var ended = session("ended", tool: .workbuddy, at: now); ended.isSessionEnded = true
        let expired = session("expired", tool: .zcode, at: now.addingTimeInterval(-172_800))
        discovery.syntheticClaudeSessionPrefix = "synthetic-"
        state.value = SessionState(sessions: family + [demo, synthetic, foreign, ended, expired])
        discovery.scheduleClaudeSessionPersistence()
        try await waitForDiscovery { try fixture.claude.load().count == family.count }
        let saved = try fixture.claude.load()
        #expect(Set(saved.map(\.tool)) == Set(family.map(\.tool)))
        #expect(Set(saved.map(\.sessionID)) == Set(family.map(\.id)))
        state.value = SessionState()
        discovery.applyStartupDiscoveryPayload(payload(saved.map(\.session)))
        for original in family {
            let restored = try #require(state.value.session(id: original.id))
            #expect(restored.tool == original.tool && restored.jumpTarget == original.jumpTarget)
            #expect(restored.claudeMetadata == original.claudeMetadata && restored.updatedAt == original.updatedAt)
            #expect(restored.attachmentState == .stale && !restored.isHookManaged && !restored.isProcessAlive)
        }
    }


    @Test func cacheAndFirstDiscoveryApplyBeforeRemainingSourcesWhileCacheCanEnrich() async throws {
        let fixture = try DiscoveryFixture(); defer { fixture.cleanup() }
        let gate = StartupScanGate(); defer { gate.release() }
        let state = DiscoveryState()
        let now = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970))
        var cached = session("cached-codex", tool: .codex, at: now.addingTimeInterval(-120))
        cached.jumpTarget = JumpTarget(terminalApp: "Unknown", workspaceName: "fixture", paneTitle: "fixture",
            workingDirectory: "/synthetic/workspace")
        let zcode = session("cached-zcode", tool: .zcode, at: now.addingTimeInterval(-120))
        try fixture.save([cached, zcode])
        let first = session("first-codex", tool: .codex, at: now)
        let later = session("later-codex", tool: .codex, at: now)
        let claude = session("later-claude", tool: .claudeCode, at: now)
        var enriched = cached
        enriched.updatedAt = now; enriched.phase = .completed; enriched.title = "Source enriched"
        enriched.jumpTarget = JumpTarget(terminalApp: "Codex.app", workspaceName: "fixture", paneTitle: "fixture",
            workingDirectory: "/synthetic/workspace", terminalSessionID: "exact-desktop-id")
        enriched.codexMetadata = CodexSessionMetadata(initialUserPrompt: "Source prompt", currentTool: "SourceTool")
        let enrichment = CodexTrackedSessionRecord(session: enriched)
        var duplicate = first; duplicate.title = "Older duplicate"; duplicate.updatedAt = now.addingTimeInterval(-60)
        let older = CodexTrackedSessionRecord(session: duplicate)
        let sources = SessionDiscoveryCoordinator.StartupDiscoverySources(codex: { emit in
            gate.record("codex-start")
            emit(CodexTrackedSessionRecord(session: first))
            emit(enrichment)
            gate.wait()
            emit(CodexTrackedSessionRecord(session: later))
            emit(older)
            gate.record("codex-finish")
        }, claude: { emit in
            gate.record("claude-start")
            emit(claude)
        })
        let discovery = fixture.coordinator(state: state, sources: sources)
        let workflow = Task {
            await discovery.discoverStartupSessions { batch in
                if !batch.codexRecords.isEmpty { gate.record("cache-applied") }
                discovery.applyStartupDiscoveryPayload(batch)
            }
        }
        try await gate.waitUntilEntered()
        try await state.waitFor { $0.session(id: cached.id)?.title == "Source enriched" }
        #expect(gate.isWaiting)
        #expect(gate.events == ["cache-applied", "codex-start"])
        #expect(state.value.session(id: zcode.id)?.tool == .zcode)
        #expect(state.value.session(id: first.id) != nil)
        #expect(state.value.session(id: later.id) == nil && state.value.session(id: claude.id) == nil)
        let surfacedCache = try #require(state.value.session(id: cached.id))
        #expect(surfacedCache.phase == .completed && surfacedCache.isCodexAppSession)
        #expect(surfacedCache.codexMetadata?.initialUserPrompt == "Source prompt")
        #expect(surfacedCache.jumpTarget?.terminalSessionID == "exact-desktop-id")
        gate.release()
        await workflow.value
        #expect(gate.events == ["cache-applied", "codex-start", "codex-finish", "claude-start"])
        #expect(state.value.sessions.count == 5)
        #expect(state.value.session(id: first.id)?.title == first.title)
    }

    @Test func runtimeIngressBetweenBatchesProtectsNativeIdentityTargetAndLateTranscriptAlias() async throws {
        let fixture = try DiscoveryFixture(); defer { fixture.cleanup() }
        let gate = StartupScanGate(); defer { gate.release() }
        let state = DiscoveryState()
        let now = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970))
        let cachedCodex = session("cached-codex", tool: .codex, at: now.addingTimeInterval(-120))
        let cachedZcode = session("native-zcode", tool: .zcode, at: now.addingTimeInterval(-120))
        try fixture.save([cachedCodex, cachedZcode])
        var staleCodex = cachedCodex
        staleCodex.title = "Late history"; staleCodex.phase = .running; staleCodex.updatedAt = now.addingTimeInterval(120)
        staleCodex.jumpTarget = JumpTarget(terminalApp: "Codex.app", workspaceName: "wrong", paneTitle: "wrong",
            workingDirectory: "/synthetic/wrong", terminalSessionID: "wrong-target")
        let lateCodex = CodexTrackedSessionRecord(session: staleCodex)
        var alias = cachedZcode; alias.id = "late-transcript-alias"; alias.tool = .claudeCode
        alias.title = "Wrong alias"; alias.updatedAt = now.addingTimeInterval(120)
        alias.jumpTarget = staleCodex.jumpTarget
        let lateAlias = alias
        let sources = SessionDiscoveryCoordinator.StartupDiscoverySources(codex: { emit in
            gate.wait()
            emit(lateCodex)
        }, claude: { emit in emit(lateAlias) })
        let discovery = fixture.coordinator(state: state, sources: sources)
        let workflow = Task { await discovery.discoverStartupSessions { discovery.applyStartupDiscoveryPayload($0) } }
        try await gate.waitUntilEntered()
        try await state.waitFor { $0.sessions.count == 2 }
        #expect(gate.isWaiting)
        let events: [AgentEvent] = [
            .sessionCompleted(.init(sessionID: cachedCodex.id, summary: "Live completed", timestamp: now)),
            .sessionHeartbeat(.init(sessionID: cachedZcode.id, timestamp: now)),
            .jumpTargetUpdated(.init(sessionID: cachedZcode.id,
                jumpTarget: JumpTarget(terminalApp: "ZCode.app", workspaceName: "live", paneTitle: "live",
                    workingDirectory: "/synthetic/live", terminalSessionID: "live-native-target"), timestamp: now)),
            .sessionCompleted(.init(sessionID: cachedZcode.id, summary: "Live ZCode completed", timestamp: now)),
        ]
        for event in events { discovery.protectFromStartupHistory(event); state.value.apply(event) }
        let live = state.value.sessions
        gate.release()
        await workflow.value
        for current in live { #expect(state.value.session(id: current.id) == current) }
        #expect(state.value.session(id: lateAlias.id) == nil)
        #expect(state.value.session(id: cachedZcode.id)?.tool == .zcode)
        #expect(state.value.session(id: cachedZcode.id)?.jumpTarget?.terminalSessionID == "live-native-target")
        try await waitForDiscovery {
            try fixture.codex.load().first?.phase == .completed && fixture.claude.load().first?.summary == "Live ZCode completed"
        }
        // After startup, ordinary source updates retain their existing merge semantics.
        #expect(discovery.mergeDiscoveredSessions([staleCodex]).first { $0.id == cachedCodex.id }?.title == "Late history")
    }

    @Test func cacheAdmissionRejectsExpiredDemoAndEndedFamilyRecords() throws {
        let fixture = try DiscoveryFixture(); defer { fixture.cleanup() }
        let state = DiscoveryState(), discovery = fixture.coordinator(state: state)
        let now = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970))
        let current = session("current-workbuddy", tool: .workbuddy, at: now)
        let expired = session("expired-zcode", tool: .zcode, at: now.addingTimeInterval(-172_800))
        var demo = session("demo-zcode", tool: .zcode, at: now); demo.origin = .demo
        var ended = session("ended-workbuddy", tool: .workbuddy, at: now); ended.isSessionEnded = true
        try fixture.save([current, expired, demo, ended])
        let batch = discovery.loadStartupCachePayload()
        #expect(batch.claudeRecords.map(\.sessionID) == [current.id])
        #expect(batch.claudeRecordsNeedPrune)
    }



    @Test func periodicRescanYieldsStartupFirstFlightAndResumesAfterFinish() async throws {
        let fixture = try DiscoveryFixture(); defer { fixture.cleanup() }
        let gate = StartupScanGate(); defer { gate.release() }
        let manager = ScanCountingFileManager(), state = DiscoveryState()
        let sources = SessionDiscoveryCoordinator.StartupDiscoverySources(codex: { _ in gate.wait() }, claude: { _ in })
        let discovery = fixture.coordinator(state: state, sources: sources, codexFileManager: manager)
        discovery.beginStartupHistory()
        discovery.rediscoverCodexAppSessionsIfNeeded()
        #expect(manager.scanCount == 0) // Reserved before the history task is scheduled.
        let workflow = Task { await discovery.discoverStartupSessions { discovery.applyStartupDiscoveryPayload($0) } }
        try await gate.waitUntilEntered()
        #expect(gate.isWaiting)
        discovery.rediscoverCodexAppSessionsIfNeeded()
        #expect(manager.scanCount == 0) // Streaming scan owns first flight; live state still accepts events.
        let live = session("live-native", tool: .zcode, at: .now)
        state.value = SessionState(sessions: [live])
        #expect(state.value.session(id: live.id) == live)
        gate.release()
        await workflow.value
        discovery.rediscoverCodexAppSessionsIfNeeded()
        try await waitForDiscovery { manager.scanCount == 1 }
    }

    @Test func runtimeBeforeFirstCacheApplyRemainsAuthoritative() async throws {
        let fixture = try DiscoveryFixture(); defer { fixture.cleanup() }
        let state = DiscoveryState()
        let now = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970))
        let cached = session("native-workbuddy", tool: .workbuddy, at: now.addingTimeInterval(120))
        try fixture.save([cached])
        let sources = SessionDiscoveryCoordinator.StartupDiscoverySources(codex: { _ in }, claude: { _ in })
        let discovery = fixture.coordinator(state: state, sources: sources)
        discovery.beginStartupHistory()
        let event = AgentEvent.sessionStarted(.init(sessionID: cached.id, title: "Live source", tool: .workbuddy,
            origin: .live, summary: "Live arrived", timestamp: now,
            jumpTarget: JumpTarget(terminalApp: "WorkBuddy.app", workspaceName: "live", paneTitle: "live",
                workingDirectory: "/synthetic/live", terminalSessionID: "live-workbuddy")))
        discovery.protectFromStartupHistory(event); state.value.apply(event)
        let live = try #require(state.value.session(id: cached.id))
        await discovery.discoverStartupSessions { discovery.applyStartupDiscoveryPayload($0) }
        #expect(state.value.session(id: cached.id) == live)
    }

}
