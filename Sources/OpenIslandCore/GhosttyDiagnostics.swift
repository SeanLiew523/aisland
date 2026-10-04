import CryptoKit
import Darwin
import Foundation

/// An opt-in, bounded metadata trace. Callers cannot place free text in a record.
public struct GhosttyDiagnosticEvent: Sendable {
    public let values: [String: String]
    public let flags: [String: Bool]
    public let counts: [String: Int]

    public init(stage: String, agent: String? = nil, event: String? = nil, reason: String,
                nativeID: String? = nil, surfaceID: String? = nil,
                flags: [String: Bool] = [:], counts: [String: Int] = [:]) {
        var values = ["stage": Self.stages.contains(stage) ? stage : "other",
                      "reason": Self.reasons.contains(reason) ? reason : "other"]
        if let agent { values["agent"] = Self.agents.contains(agent) ? agent : "other" }
        if let event { values["event"] = Self.events.contains(event) ? event : "unknown" }
        if let nativeID, !nativeID.isEmpty, nativeID.utf8.count <= 512 { values["nativeIDHash"] = Self.hashID(nativeID) }
        if let surfaceID, !surfaceID.isEmpty, surfaceID.utf8.count <= 512 { values["surfaceIDHash"] = Self.hashID(surfaceID) }
        self.values = values
        self.flags = flags.filter { Self.flagNames.contains($0.key) }
        self.counts = counts.filter { Self.countNames.contains($0.key) }.mapValues { max(-1, min(256, $0)) }
    }

    public static func hashID(_ id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private static let stages: Set<String> = ["binding", "locator", "piCapture", "piLocator", "jump"]
    private static let agents: Set<String> = ["claude", "codex", "grok", "gemini", "hermes", "pi", "oh-my-pi"]
    private static let events: Set<String> = ["startup", "userSubmit", "background", "sessionStart", "interactive", "rpc", "extension", "unknown", "start", "success", "failure"]
    private static let flagNames: Set<String> = ["hasRealTTY", "frontmostBefore", "frontmostAfter", "focusStable", "hasUI", "hasBinding", "isGhostty", "hasSurfaceID"]
    private static let countNames: Set<String> = ["surfaceCount", "cwdMatchCount", "exitStatus"]
    private static let reasons: Set<String> = [
        "invalidSource", "missingTTY", "invalidCWD", "storageUnavailable", "lockUnavailable", "receiptRejected", "receiptHit", "receiptExpired", "backgroundWithoutReceipt", "snapshotUnavailable", "notFrontmost", "focusChanged", "invalidInventory", "focusedCWDNotFound", "differentAdmittedID", "ambiguousCWD", "receiptWritten", "receiptWriteFailed",
        "launchFailed", "timeout", "readTimeout", "exitFailed", "invalidOutput", "emptySnapshot", "parseFailed", "snapshotReady", "notRunning", "tooManySurfaces",
        "noUI", "notGhostty", "inputSourceRejected", "bindingReused", "bindingAdmitted", "bindingRejected",
        "ghostty", "terminal", "other", "unsupportedTerminal", "openFailed", "appleScriptFailed", "conversationUnavailable", "terminal-inventory-unavailable", "terminal-id-or-unique-target-missing", "ambiguous-terminal", "focused-terminal-id-unverified", "unknownError"
    ]
}

public enum GhosttyDiagnostics {
    public static let markerName = ".ghostty-diagnostics-enabled"
    public static let logName = "ghostty-diagnostics.jsonl"
    public static let maximumBytes = 262_144
    public static func record(_ event: GhosttyDiagnosticEvent) {
        write(event, directory: BridgeSocketLocation.defaultURL.deletingLastPathComponent())
    }

    /// No directories or marker are created. Unsafe, absent, busy or full traces
    /// are silently skipped; diagnostics never affect source admission or jump.
    static func write(_ event: GhosttyDiagnosticEvent, directory: URL) {
        let dir = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard dir >= 0 else { return }
        defer { close(dir) }
        var directoryInfo = stat()
        guard fstat(dir, &directoryInfo) == 0, directoryInfo.st_uid == getuid(),
              directoryInfo.st_mode & 0o022 == 0 else { return }
        let marker = openat(dir, markerName, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard marker >= 0 else { return }
        defer { close(marker) }
        guard safeFile(marker, empty: true) else { return }
        let lockName = ".ghostty-diagnostics.lock"
        let lock = openat(dir, lockName, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { return }
        defer { close(lock); _ = unlinkat(dir, lockName, 0) }
        let log = openat(dir, logName, O_CREAT | O_WRONLY | O_APPEND | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard log >= 0 else { return }
        defer { close(log) }
        guard safeFile(log, empty: false) else { return }
        var record: [String: Any] = event.values
        for (key, value) in event.flags { record[key] = value }
        for (key, value) in event.counts { record[key] = value }
        record["timestamp"] = ISO8601DateFormatter().string(from: .now)
        guard var data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), data.count <= 2_048 else { return }
        data.append(10)
        var info = stat()
        guard fstat(log, &info) == 0, info.st_size + Int64(data.count) <= maximumBytes else { return }
        data.withUnsafeBytes { bytes in _ = Darwin.write(log, bytes.baseAddress, bytes.count) }
    }

    private static func safeFile(_ fd: Int32, empty: Bool) -> Bool {
        var info = stat()
        return fstat(fd, &info) == 0 && isSafeFile(info, empty: empty)
    }

    static func isSafeFile(_ info: stat, empty: Bool, userID: uid_t = getuid()) -> Bool {
        info.st_mode & S_IFMT == S_IFREG
            && info.st_uid == userID && info.st_mode & 0o7777 == 0o600
            && info.st_nlink == 1 && (empty ? info.st_size == 0 : info.st_size <= maximumBytes)
    }
}
