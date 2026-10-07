import Foundation
import Testing
@testable import OpenIslandCore

struct ClaudeSessionRegistryTests {
    @Test
    func claudeSessionRegistryRoundTripsTrackedSessions() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-registry-\(UUID().uuidString)", isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("claude-session-registry.json")
        let registry = ClaudeSessionRegistry(fileURL: fileURL)

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let records = [
            ClaudeTrackedSessionRecord(
                sessionID: "claude-session-1",
                title: "Claude · open-island",
                origin: .live,
                attachmentState: .attached,
                summary: "Working on the registry.",
                phase: .running,
                updatedAt: Date(timeIntervalSince1970: 1_000),
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: "open-island",
                    paneTitle: "claude ~/Personal/open-island",
                    workingDirectory: "/tmp/open-island",
                    terminalSessionID: "ghostty-claude",
                    terminalTTY: "/dev/ttys002"
                ),
                claudeMetadata: ClaudeSessionMetadata(
                    transcriptPath: "/tmp/claude.jsonl",
                    initialUserPrompt: "Start with Claude recovery.",
                    lastUserPrompt: "Tighten Claude restart recovery.",
                    lastAssistantMessage: "Implementing the registry.",
                    currentTool: "Task",
                    currentToolInputPreview: "Implement ClaudeSessionRegistry",
                    model: "sonnet"
                )
            ),
        ]

        try registry.save(records)
        let reloaded = try registry.load()

        #expect(reloaded == records)
        #expect(reloaded.first?.session.claudeMetadata?.transcriptPath == "/tmp/claude.jsonl")
        #expect(reloaded.first?.session.jumpTarget?.terminalTTY == "/dev/ttys002")
    }

    @Test
    func claudeTrackedSessionRecordRestoresAsStale() {
        let record = ClaudeTrackedSessionRecord(
            sessionID: "claude-session-1",
            title: "Claude · open-island",
            origin: .live,
            attachmentState: .attached,
            summary: "Working on the registry.",
            phase: .running,
            updatedAt: .now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "claude ~/Personal/open-island",
                workingDirectory: "/tmp/open-island",
                terminalSessionID: "ghostty-claude",
                terminalTTY: "/dev/ttys002"
            )
        )

        #expect(record.session.attachmentState == .attached)
        #expect(record.restorableSession.attachmentState == .stale)
        #expect(record.restorableSession.jumpTarget?.terminalSessionID == "ghostty-claude")
    }

    @Test(arguments: AgentTool.allCases.filter(\.isClaudeCodeFork))
    func hookFamilyRoundTripsOriginalIdentityAndMetadata(_ tool: AgentTool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("claude-family-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = ClaudeSessionRegistry(fileURL: root.appendingPathComponent("registry.json"))
        let time = Date(timeIntervalSince1970: 1_000)
        let session = AgentSession(id: "native-\(tool.rawValue)", title: "Source fixture", tool: tool,
            origin: .live, attachmentState: .attached, phase: .running, summary: "Fixture",
            updatedAt: time, firstSeenAt: time,
            jumpTarget: JumpTarget(terminalApp: "ZCode.app", workspaceName: "fixture", paneTitle: "fixture",
                workingDirectory: "/synthetic/workspace", terminalSessionID: "real-native-target"),
            claudeMetadata: ClaudeSessionMetadata(transcriptPath: "/synthetic/fixture.jsonl",
                initialUserPrompt: "Original prompt", currentTool: "Read", agentID: "native-agent"))
        try registry.save([ClaudeTrackedSessionRecord(session: session)])
        let restored = try #require(registry.load().first).restorableSession
        #expect(restored.id == session.id && restored.tool == tool)
        #expect(restored.jumpTarget == session.jumpTarget && restored.claudeMetadata == session.claudeMetadata)
        #expect(restored.updatedAt == time && restored.firstSeenAt == time)
        #expect(restored.attachmentState == .stale)
        #expect(!restored.isProcessAlive && !restored.isHookManaged)
        try registry.save([ClaudeTrackedSessionRecord(session: restored)])
        #expect(try registry.load().first?.restorableSession == restored)
    }

    @Test func untaggedLegacyCacheRestoresClaudeCodeAndRejectsExplicitInvalidTags() throws {
        let record = ClaudeTrackedSessionRecord(sessionID: "legacy-real-id", title: "Legacy",
            summary: "Legacy source", phase: .completed, updatedAt: Date(timeIntervalSince1970: 1_000))
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        let encoded = try encoder.encode(record)
        var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "tool")
        let legacy = try decoder.decode(ClaudeTrackedSessionRecord.self,
            from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.tool == .claudeCode && legacy.sessionID == record.sessionID)
        for tag: Any in ["unknown-source", "codex", "deepseekHarness", "ordinaryClaudeChat", NSNull()] {
            json["tool"] = tag
            let invalid = try JSONSerialization.data(withJSONObject: json)
            #expect(throws: DecodingError.self) { try decoder.decode(ClaudeTrackedSessionRecord.self, from: invalid) }
        }
        let unsupported = ClaudeTrackedSessionRecord(session: AgentSession(id: "foreign", title: "Foreign",
            tool: .codex, phase: .running, summary: "Foreign", updatedAt: .now))
        #expect(!unsupported.shouldRestoreToLiveState)
        #expect(throws: EncodingError.self) { try encoder.encode(unsupported) }
    }


    @Test func demoAndEndedRecordsAreNotRestorable() throws {
        var ended = AgentSession(id: "ended-native", title: "Ended", tool: .workbuddy,
            origin: .live, phase: .completed, summary: "Ended", updatedAt: .now)
        ended.isSessionEnded = true
        let endedRecord = ClaudeTrackedSessionRecord(session: ended)
        let restoredRecord = try JSONDecoder().decode(ClaudeTrackedSessionRecord.self,
            from: JSONEncoder().encode(endedRecord))
        #expect(restoredRecord.isSessionEnded && !restoredRecord.shouldRestoreToLiveState)
        #expect(restoredRecord.session.isSessionEnded)
        var demo = ended; demo.origin = .demo; demo.isSessionEnded = false
        #expect(!ClaudeTrackedSessionRecord(session: demo).shouldRestoreToLiveState)
    }

}
