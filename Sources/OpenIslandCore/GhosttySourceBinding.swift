import CryptoKit
import Darwin
import Foundation

/// Source metadata only. Never reads prompt text or terminal contents.
public struct GhosttySourceBinding: Codable, Equatable, Sendable {
    public var sessionID: String
    public var workingDirectory: String
    public var title: String?
    public var capturedAt: Date

    public init(sessionID: String, workingDirectory: String, title: String?, capturedAt: Date) {
        self.sessionID = sessionID
        self.workingDirectory = workingDirectory
        self.title = title
        self.capturedAt = capturedAt
    }
}

public enum GhosttySourceEvent: Equatable, Sendable {
    case startup, userSubmit, background
}

public typealias GhosttySourceBindingProvider = (String, String, String?, String, GhosttySourceEvent) -> GhosttySourceBinding?

struct GhosttySourceSnapshot: Sendable {
    struct Surface: Sendable {
        var id: String
        var cwd: String
        var title: String?
    }
    var frontmostBefore: Bool
    var frontmostAfter: Bool
    var focusedBefore: String
    var focusedAfter: String
    var surfaces: [Surface]
}

/// Hook processes are short lived. A private on-disk receipt keeps their first
/// verified source binding stable across tools, stops and interleaved sessions.
struct GhosttySourceBindingStore {
    var directory: URL
    var snapshotProvider: () -> GhosttySourceSnapshot?
    var now: () -> Date = Date.init

    static func production(
        agent: String, sessionID: String, tty: String?, cwd: String, event: GhosttySourceEvent
    ) -> GhosttySourceBinding? {
        let directory = BridgeSocketLocation.defaultURL.deletingLastPathComponent()
            .appendingPathComponent("ghostty-source-bindings", isDirectory: true)
        return Self(directory: directory, snapshotProvider: GhosttySourceLocator.snapshot)
            .resolve(agent: agent, sessionID: sessionID, tty: tty, cwd: cwd, event: event)
    }

    func resolve(
        agent: String, sessionID: String, tty: String?, cwd: String, event: GhosttySourceEvent
    ) -> GhosttySourceBinding? {
        guard !agent.isEmpty, agent.utf8.count <= 32, sessionID.utf8.count <= 512,
              !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let tty = Self.realTTY(tty), let normalizedCWD = Self.path(cwd) else { return nil }
        let keyData = try? JSONEncoder().encode([agent, sessionID, tty])
        guard let keyData else { return nil }
        let key = SHA256.hash(data: keyData).map { String(format: "%02x", $0) }.joined()
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            let attrs = try fm.attributesOfItem(atPath: directory.path)
            guard attrs[.type] as? FileAttributeType == .typeDirectory,
                  (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { return nil }
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        } catch { return nil }
        let lockURL = directory.appendingPathComponent(key + ".lock")
        let lockFD = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lockFD >= 0 else { return nil }
        defer { close(lockFD) }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { return nil }
        defer { _ = flock(lockFD, LOCK_UN) }
        let receiptURL = directory.appendingPathComponent(key + ".json")
        var admittedID: String?
        if let attrs = try? fm.attributesOfItem(atPath: receiptURL.path) {
            guard attrs[.type] as? FileAttributeType == .typeRegular,
                  ((attrs[.size] as? NSNumber)?.intValue ?? Int.max) <= 16_384,
                  (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  let data = readReceipt(receiptURL),
                  let binding = try? JSONDecoder().decode(GhosttySourceBinding.self, from: data),
                  !binding.sessionID.isEmpty,
                  now().timeIntervalSince(binding.capturedAt) >= 0 else { return nil }
            // A changed cwd does not identify a different surface. Keep the ID;
            // terminal shells and agents can legitimately change directories.
            if now().timeIntervalSince(binding.capturedAt) < 24 * 60 * 60 { return binding }
            guard event != .background else { return nil }
            // Refresh an aged receipt only from an admitted source event and
            // only if that same surface is still focused. Never replace its ID.
            admittedID = binding.sessionID
        }
        guard event != .background,
              let snapshot = snapshotProvider(),
              snapshot.frontmostBefore, snapshot.frontmostAfter,
              !snapshot.focusedBefore.isEmpty, snapshot.focusedBefore == snapshot.focusedAfter,
              !snapshot.surfaces.isEmpty, snapshot.surfaces.count <= 256,
              snapshot.surfaces.allSatisfy({ !$0.id.isEmpty }),
              Set(snapshot.surfaces.map(\.id)).count == snapshot.surfaces.count else { return nil }
        let matches = snapshot.surfaces.filter { Self.path($0.cwd) == normalizedCWD }
        guard let focused = matches.first(where: { $0.id == snapshot.focusedBefore }),
              admittedID == nil || admittedID == focused.id,
              event == .userSubmit || matches.count == 1 else { return nil }
        let binding = GhosttySourceBinding(sessionID: focused.id, workingDirectory: normalizedCWD,
                                           title: focused.title, capturedAt: now())
        do {
            let data = try JSONEncoder().encode(binding)
            try data.write(to: receiptURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: receiptURL.path)
            return binding
        } catch { return nil }
    }

    private func readReceipt(_ url: URL) -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              (info.st_mode & 0o077) == 0,
              info.st_uid == getuid(), info.st_size <= 16_384 else { return nil }
        guard let data = try? handle.read(upToCount: 16_385), data.count <= 16_384 else { return nil }
        return data
    }

    private static func realTTY(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.hasPrefix("/dev/tty"), value.count > 8, value.utf8.count <= 128,
              !value.contains(where: { $0.isWhitespace }) else { return nil }
        return value
    }

    private static func path(_ value: String) -> String? {
        guard value.utf8.count <= 4_096, value.hasPrefix("/"), !value.contains("\u{1f}"), !value.contains("\n") else { return nil }
        return URL(fileURLWithPath: value).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

enum GhosttySourceLocator {
    // Public Ghostty metadata API: no undocumented tty/pid properties, title
    // mutation, keystrokes, activation or focus changes.
    static let script = """
    tell application "Ghostty"
        if not (it is running) then return ""
        if not frontmost then return ""
        set firstID to id of focused terminal of selected tab of front window
        set rows to ""
        set surfaceCount to 0
        repeat with win in windows
            repeat with tabRef in tabs of win
                repeat with terminalRef in terminals of tabRef
                    set surfaceCount to surfaceCount + 1
                    if surfaceCount > 256 then return ""
                    set rows to rows & (id of terminalRef as text) & (ASCII character 31) & (working directory of terminalRef as text) & (ASCII character 31) & (name of terminalRef as text) & linefeed
                end repeat
            end repeat
        end repeat
        if not frontmost then return ""
        set lastID to id of focused terminal of selected tab of front window
        if firstID is not lastID then return ""
        return (firstID as text) & linefeed & rows
    end tell
    """

    static func parse(_ text: String) -> GhosttySourceSnapshot? {
        guard text.utf8.count <= 1_048_576 else { return nil }
        var lines = text.components(separatedBy: "\n")
        guard let focused = lines.first, !focused.isEmpty else { return nil }
        lines.removeFirst()
        while lines.last == "" { lines.removeLast() }
        guard !lines.isEmpty, lines.count <= 256 else { return nil }
        var surfaces: [GhosttySourceSnapshot.Surface] = []
        for line in lines {
            let values = line.components(separatedBy: "\u{1f}")
            guard values.count == 3, !values[0].isEmpty else { return nil }
            surfaces.append(.init(id: values[0], cwd: values[1], title: values[2]))
        }
        return .init(frontmostBefore: true, frontmostAfter: true, focusedBefore: focused,
                     focusedAfter: focused, surfaces: surfaces)
    }

    static func snapshot() -> GhosttySourceSnapshot? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        let output = Output()
        let readFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            while let data = try? pipe.fileHandleForReading.read(upToCount: 16_384), !data.isEmpty {
                output.append(data)
            }
            readFinished.signal()
        }
        guard finished.wait(timeout: .now() + 1.5) == .success else {
            process.terminate()
            return nil
        }
        guard readFinished.wait(timeout: .now() + 0.2) == .success,
              process.terminationStatus == 0, let data = output.value,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(text.trimmingCharacters(in: .newlines))
    }

    private final class Output: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var overflow = false
        func append(_ value: Data) {
            lock.lock(); defer { lock.unlock() }
            if data.count + value.count > 1_048_576 { overflow = true }
            if !overflow { data.append(value) }
        }
        var value: Data? {
            lock.lock(); defer { lock.unlock() }
            return overflow ? nil : data
        }
    }
}
