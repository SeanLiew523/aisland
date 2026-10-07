import Foundation
import Darwin

/// Fixed executable + argv invocation, with bounded output and a deadline.
/// Diagnostics never propagate arbitrary source output/configuration.
public enum ConnectionProcessRunner {
    public enum Failure: Error, LocalizedError {
        case timedOut, rejected(Int32), outputTooLarge
        public var errorDescription: String? {
            switch self {
            case .timedOut: "Connection setup timed out. Check the source and try again."
            case let .rejected(code): "Connection setup failed (exit \(code)). Existing source settings were preserved where possible."
            case .outputTooLarge: "Connection setup returned more metadata than allowed."
            }
        }
    }
    public static func run(_ executable: URL, arguments: [String], environment: [String: String],
                           timeout: TimeInterval = 30, maximumOutput: Int = 262_144) throws -> Data {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aisland-connection-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let outputURL = root.appendingPathComponent("stdout")
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = executable; process.arguments = arguments; process.environment = environment
        process.standardOutput = output; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
            if let size = try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumOutput {
                terminateOwnedInvocation(process); throw Failure.outputTooLarge
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            terminateOwnedInvocation(process); throw Failure.timedOut
        }
        guard process.terminationStatus == 0 else { throw Failure.rejected(process.terminationStatus) }
        let size = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? maximumOutput + 1
        guard size <= maximumOutput else { throw Failure.outputTooLarge }
        return try Data(contentsOf: outputURL)
    }

    /// Only children of this invocation, admitted by PID + birth time + parent
    /// chain, are terminated. Existing source app/task processes cannot qualify.
    private static func terminateOwnedInvocation(_ process: Process) {
        if let root = MiniMaxCodeActiveDataDirectory.snapshot(process.processIdentifier) {
            var pids = [Int32](repeating: 0, count: 16_384)
            let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
            if count > 0, count < pids.count {
                let family = MiniMaxCodeActiveDataDirectory.descendantProcesses(root: root,
                    candidates: pids.prefix(Int(count)).compactMap(MiniMaxCodeActiveDataDirectory.snapshot))
                for identity in family.reversed() where identity.pid != root.pid {
                    if MiniMaxCodeActiveDataDirectory.snapshot(identity.pid) == identity { kill(identity.pid, SIGKILL) }
                }
            }
            if MiniMaxCodeActiveDataDirectory.snapshot(root.pid) == root { kill(root.pid, SIGKILL) }
        } else if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()
    }
}
