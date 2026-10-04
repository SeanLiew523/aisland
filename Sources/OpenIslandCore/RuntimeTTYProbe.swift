import Darwin
import Foundation

/// Reads only PID, PPID and controlling TTY. Hook stdin is a JSON pipe and
/// cannot identify its source terminal; inherited TTY values are not evidence.
enum RuntimeTTYProbe {
    static let maximumHops = 8
    static let timeBudget: TimeInterval = 1.5

    static func currentTTY() -> String? {
        resolve(startPID: getpid(), query: processRow)
    }

    static func resolve(startPID: pid_t, query: (pid_t, TimeInterval) -> String?,
                        now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) -> String? {
        let deadline = now() + timeBudget
        var pid = startPID
        var visited: Set<pid_t> = []
        for _ in 0..<maximumHops {
            guard pid > 1, visited.insert(pid).inserted else { return nil }
            let remaining = deadline - now()
            guard remaining > 0, let raw = query(pid, min(0.2, remaining)),
                  now() <= deadline, let sample = parse(raw, expectedPID: pid) else { return nil }
            if let tty = sample.tty { return tty }
            pid = sample.parentPID
        }
        return nil
    }

    struct Sample: Equatable {
        var parentPID: pid_t
        var tty: String?
    }

    static func parse(_ output: String, expectedPID: pid_t) -> Sample? {
        guard output.utf8.count <= 1_024 else { return nil }
        let fields = output.split(whereSeparator: { $0.isWhitespace })
        guard fields.count == 3, let pid = decimalPID(fields[0]), pid == expectedPID,
              let parent = decimalPID(fields[1]) else { return nil }
        let rawTTY = String(fields[2])
        if ["??", "?", "-"].contains(rawTTY) { return .init(parentPID: parent, tty: nil) }
        let value = rawTTY.hasPrefix("/dev/") ? String(rawTTY.dropFirst(5)) : rawTTY
        guard value.hasPrefix("tty"), value.count > 3, value.utf8.count <= 123,
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0) }),
              !value.contains("..") else { return nil }
        return .init(parentPID: parent, tty: "/dev/" + value)
    }

    private static func decimalPID(_ text: Substring) -> pid_t? {
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }), let value = Int32(text), value >= 0 else { return nil }
        return value
    }

    private static func processRow(_ pid: pid_t, timeout: TimeInterval) -> String? {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "pid=,ppid=,tty="]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0), readFinished = DispatchSemaphore(value: 0)
        let output = Output()
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        DispatchQueue.global().async {
            var collected = Data()
            while let chunk = try? pipe.fileHandleForReading.read(upToCount: 1_025 - collected.count), !chunk.isEmpty {
                collected.append(chunk)
                if collected.count > 1_024 { output.set(nil); readFinished.signal(); return }
            }
            output.set(collected)
            readFinished.signal()
        }
        guard finished.wait(timeout: .now() + timeout) == .success else { process.terminate(); return nil }
        guard readFinished.wait(timeout: .now() + 0.02) == .success, process.terminationStatus == 0,
              let data = output.value, data.count <= 1_024 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private final class Output: @unchecked Sendable {
        private let lock = NSLock()
        private var data: Data?
        func set(_ value: Data?) { lock.lock(); defer { lock.unlock() }; data = value }
        var value: Data? { lock.lock(); defer { lock.unlock() }; return data }
    }
}
