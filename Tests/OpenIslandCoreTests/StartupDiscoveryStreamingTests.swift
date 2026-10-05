import Foundation
import Testing
@testable import OpenIslandCore

private final class FileDiscoveryGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var open = false
    private var ids: [String] = []
    private var finished = false
    func accept(_ id: String) {
        condition.lock()
        ids.append(id)
        if ids.count == 1 { while !open { condition.wait() } }
        condition.unlock()
    }
    func finish() { condition.lock(); finished = true; condition.unlock() }
    func release() { condition.lock(); open = true; condition.broadcast(); condition.unlock() }
    var snapshot: (ids: [String], finished: Bool) {
        condition.lock(); defer { condition.unlock() }; return (ids, finished)
    }
}

@MainActor struct StartupDiscoveryStreamingTests {
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("streaming-discovery-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func write(_ contents: String, name: String, root: URL, modifiedAt: Date) throws {
        let path = root.appendingPathComponent(name)
        try contents.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: path.path)
    }
    private func waitForFirst(_ gate: FileDiscoveryGate) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while gate.snapshot.ids.isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(!gate.snapshot.ids.isEmpty)
    }
    private func codexLine(_ id: String, time: Date) throws -> String {
        let timestamp = ISO8601DateFormatter().string(from: time)
        let json: [String: Any] = ["type": "session_meta", "timestamp": timestamp,
            "payload": ["id": id, "cwd": "/synthetic/workspace", "timestamp": timestamp,
                "originator": "Codex Desktop", "source": "cli"]]
        return String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self) + "\n"
    }

    @Test func codexCallbackSurfacesFirstCompleteFileBeforeRestAndKeepsSingleFlight() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let gate = FileDiscoveryGate(); defer { gate.release() }
        let now = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970))
        try write(codexLine("first-native", time: now), name: "rollout-first.jsonl", root: root, modifiedAt: now)
        try write(codexLine("second-native", time: now.addingTimeInterval(-1)), name: "rollout-second.jsonl", root: root, modifiedAt: now.addingTimeInterval(-1))
        try write(codexLine("first-native", time: now.addingTimeInterval(-2)), name: "rollout-duplicate.jsonl", root: root, modifiedAt: now.addingTimeInterval(-2))
        let discovery = CodexRolloutDiscovery(rootURL: root)
        let scan = Task.detached {
            let records = discovery.discoverRecentSessions(now: now, onSession: { gate.accept($0.sessionID) })
            gate.finish()
            return records
        }
        try await waitForFirst(gate)
        #expect(gate.snapshot.ids == ["first-native"] && !gate.snapshot.finished)
        #expect(discovery.discoverRecentSessions(now: now).isEmpty) // Callback holds no state lock.
        gate.release()
        let records = await scan.value
        #expect(gate.snapshot.ids == ["first-native", "second-native"] && gate.snapshot.finished)
        #expect(records.map(\.sessionID) == ["first-native", "second-native"])
        #expect(records.allSatisfy { $0.jumpTarget?.terminalApp == "Codex.app" })
        let transcriptPath = try #require(records.first?.session.codexMetadata?.transcriptPath)
        // macOS enumeration can return the /private alias of the temp root.
        #expect(FileManager.default.contentsEqual(atPath: transcriptPath,
            andPath: root.appendingPathComponent("rollout-first.jsonl").path))
    }

    @Test func claudeCallbackSurfacesFirstCompleteFileBeforeRestAndPreservesArrayAPI() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let gate = FileDiscoveryGate(); defer { gate.release() }
        let now = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970))
        let first = #"{"type":"attachment","sessionId":"first-native","cwd":"/synthetic/workspace","entrypoint":"claude-desktop"}"#
        let second = #"{"type":"attachment","sessionId":"second-native","cwd":"/synthetic/workspace","entrypoint":"cli"}"#
        try write(first + "\n", name: "first.jsonl", root: root, modifiedAt: now)
        try write(second + "\n", name: "second.jsonl", root: root, modifiedAt: now.addingTimeInterval(-1))
        let discovery = ClaudeTranscriptDiscovery(rootURL: root)
        let scan = Task.detached {
            let sessions = discovery.discoverRecentSessions(now: now, onSession: { gate.accept($0.id) })
            gate.finish()
            return sessions
        }
        try await waitForFirst(gate)
        #expect(gate.snapshot.ids == ["first-native"] && !gate.snapshot.finished)
        gate.release()
        let sessions = await scan.value
        #expect(gate.snapshot.ids == ["first-native", "second-native"] && gate.snapshot.finished)
        #expect(sessions == discovery.discoverRecentSessions(now: now))
        #expect(sessions.first?.jumpTarget?.terminalApp == "Claude.app")
        #expect(sessions.last?.jumpTarget?.terminalApp == "Unknown")
        #expect(sessions.allSatisfy { $0.tool == .claudeCode })
    }
}
