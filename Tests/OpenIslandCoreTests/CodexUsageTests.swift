import Foundation
import Testing
@testable import OpenIslandCore

struct CodexUsageTests {
    @Test
    func codexUsageLoaderParsesLastTokenCountRateLimits() throws {
        let rootURL = temporaryRootURL(named: "codex-usage")
        let rolloutURL = rootURL
            .appendingPathComponent("2026/04/03", isDirectory: true)
            .appendingPathComponent("rollout-latest.jsonl")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-04-03T01:49:35.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "info": [
                            "total_token_usage": [
                                "total_tokens": 999_999,
                            ],
                        ],
                        "rate_limits": [
                            "limit_id": "codex",
                            "plan_type": "pro",
                            "primary": [
                                "used_percent": 12.0,
                                "window_minutes": 300,
                                "resets_at": 1_775_158_295,
                            ],
                            "secondary": [
                                "used_percent": 24.0,
                                "window_minutes": 10_080,
                                "resets_at": 1_775_635_184,
                            ],
                        ],
                    ]
                ),
                rolloutLine(
                    timestamp: "2026-04-03T01:50:35.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "info": [
                            "total_token_usage": [
                                "total_tokens": 1_234_567,
                            ],
                        ],
                        "rate_limits": [
                            "limit_id": "codex",
                            "plan_type": "pro",
                            "primary": [
                                "used_percent": 13.0,
                                "window_minutes": 300,
                                "resets_at": 1_775_158_295,
                            ],
                            "secondary": [
                                "used_percent": 25.0,
                                "window_minutes": 10_080,
                                "resets_at": 1_775_635_184,
                            ],
                        ],
                    ]
                ),
            ],
            to: rolloutURL
        )
        try setModificationDate(
            Date(timeIntervalSince1970: 2_000),
            for: rolloutURL
        )

        let snapshot = try CodexUsageLoader.load(fromRootURL: rootURL)

        #expect(resolvedPath(snapshot?.sourceFilePath) == rolloutURL.resolvingSymlinksInPath().path)
        #expect(snapshot?.limitID == "codex")
        #expect(snapshot?.planType == "pro")
        #expect(snapshot?.windows.map(\.label) == ["5h", "7d"])
        #expect(snapshot?.windows.map(\.roundedUsedPercentage) == [13, 25])
        #expect(snapshot?.windows.first?.leftPercentage == 87)
        #expect(snapshot?.windows.first?.resetsAt == Date(timeIntervalSince1970: 1_775_158_295))
        #expect(snapshot?.capturedAt == isoDate("2026-04-03T01:50:35.000Z"))
    }

    @Test
    func codexUsageLoaderFallsBackWhenNewestRolloutHasNoRateLimits() throws {
        let rootURL = temporaryRootURL(named: "codex-usage-fallback")
        let oldRolloutURL = rootURL
            .appendingPathComponent("2026/04/02", isDirectory: true)
            .appendingPathComponent("rollout-has-rate-limits.jsonl")
        let newRolloutURL = rootURL
            .appendingPathComponent("2026/04/03", isDirectory: true)
            .appendingPathComponent("rollout-no-rate-limits.jsonl")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-04-02T17:54:17.621Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "rate_limits": [
                            "limit_id": "codex",
                            "plan_type": "pro",
                            "primary": [
                                "used_percent": 13.0,
                                "window_minutes": 300,
                                "resets_at": 1_775_158_295,
                            ],
                        ],
                    ]
                ),
            ],
            to: oldRolloutURL
        )
        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-04-03T03:00:00.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "user_message",
                        "message": "Start a fresh session.",
                    ]
                ),
            ],
            to: newRolloutURL
        )

        try setModificationDate(Date(timeIntervalSince1970: 1_000), for: oldRolloutURL)
        try setModificationDate(Date(timeIntervalSince1970: 2_000), for: newRolloutURL)

        let snapshot = try CodexUsageLoader.load(fromRootURL: rootURL)

        #expect(resolvedPath(snapshot?.sourceFilePath) == oldRolloutURL.resolvingSymlinksInPath().path)
        #expect(snapshot?.windows.map(\.label) == ["5h"])
        #expect(snapshot?.windows.first?.roundedUsedPercentage == 13)
    }

    @Test func reservedQuotaAndRecentlyTouchedOldFileCannotReplaceCodexQuota() throws {
        let root = temporaryRootURL(named: "codex-buckets")
        defer { try? FileManager.default.removeItem(at: root) }
        func line(_ timestamp: String, _ id: String, _ used: Double) -> String {
            rolloutLine(timestamp: timestamp, type: "event_msg", payload: ["type": "token_count",
                "rate_limits": ["limit_id": id, "primary": ["used_percent": used, "window_minutes": 10080]]])
        }
        let current = root.appendingPathComponent("rollout-current.jsonl")
        let touched = root.appendingPathComponent("rollout-touched.jsonl")
        let reserve = root.appendingPathComponent("rollout-reserve.jsonl")
        try writeRollout([line("2026-10-06T11:00:00Z", "codex", 99),
                          line("2026-10-06T11:01:00Z", "base_model_inference", 0)], to: current)
        try writeRollout([line("2026-10-06T10:00:00Z", "codex", 98)], to: touched)
        try writeRollout([line("2026-10-06T11:02:00Z", "base_model_inference", 0)], to: reserve)
        try setModificationDate(Date(timeIntervalSince1970: 1), for: current)
        let loaded = try CodexUsageLoader.load(fromRootURL: root)
        let value = try #require(loaded)
        #expect(value.limitID == "codex")
        #expect(value.windows.first?.roundedUsedPercentage == 99)
        #expect(resolvedPath(value.sourceFilePath) == current.resolvingSymlinksInPath().path)
    }

    @Test func onlyReservedQuotaDoesNotFabricateCodexZero() throws {
        let root = temporaryRootURL(named: "codex-reserve-only")
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRollout([rolloutLine(timestamp: "2026-10-06T11:00:00Z", type: "event_msg", payload: [
            "type": "token_count", "rate_limits": ["limit_id": "base_model_inference",
            "primary": ["used_percent": 0, "window_minutes": 10080]]])],
            to: root.appendingPathComponent("rollout-reserved.jsonl"))
        #expect(try CodexUsageLoader.load(fromRootURL: root) == nil)
    }

    @Test
    func codexUsageLoaderFormatsNonStandardWindowLengths() throws {
        let rootURL = temporaryRootURL(named: "codex-usage-labels")
        let rolloutURL = rootURL
            .appendingPathComponent("2026/04/03", isDirectory: true)
            .appendingPathComponent("rollout-custom-window.jsonl")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-04-03T05:30:00.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "rate_limits": [
                            "primary": [
                                "used_percent": 8.0,
                                "window_minutes": 90,
                                "resets_at": 1_775_200_000,
                            ],
                            "secondary": [
                                "used_percent": 11.0,
                                "window_minutes": 1_500,
                                "resets_at": 1_775_260_000,
                            ],
                        ],
                    ]
                ),
            ],
            to: rolloutURL
        )

        let snapshot = try CodexUsageLoader.load(fromRootURL: rootURL)

        #expect(snapshot?.windows.map(\.label) == ["1h 30m", "1d 1h"])
    }
}

private func temporaryRootURL(named name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("open-island-\(name)-\(UUID().uuidString)", isDirectory: true)
}

private func writeRollout(_ lines: [String], to url: URL) throws {
    let directoryURL = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
}

private func setModificationDate(_ date: Date, for url: URL) throws {
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
}

private func isoDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)
}

private func resolvedPath(_ value: String?) -> String? {
    guard let value else {
        return nil
    }

    return URL(fileURLWithPath: value).resolvingSymlinksInPath().path
}

private func rolloutLine(
    timestamp: String,
    type: String,
    payload: [String: Any]
) -> String {
    let object: [String: Any] = [
        "timestamp": timestamp,
        "type": type,
        "payload": payload,
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}
