import Foundation
import Testing
import OpenIslandCore
@testable import OpenIslandApp

private actor HistoryPause {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false
    func wait() async {
        isWaiting = true
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { isOpen = true; continuation?.resume(); continuation = nil }
}

@MainActor private final class DiscoveryState {
    var value = SessionState()
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
    @MainActor func coordinator(state: DiscoveryState) -> SessionDiscoveryCoordinator {
        let discovery = SessionDiscoveryCoordinator(codexSessionStore: codex, claudeSessionRegistry: claude,
            openCodeSessionRegistry: openCode, cursorSessionRegistry: cursor, piSessionRegistry: pi, loadArchivedCodexSessionIDs: { [] })
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
        try await waitForDiscovery { await pause.isWaiting }

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

}
