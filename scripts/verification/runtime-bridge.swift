import Foundation
import OpenIslandCore
import Darwin
import Dispatch

/// An isolated live-source receiver using the production codec, reducer and
/// observer. Records only task identity, coarse outcome and navigation metadata.
@main
struct RuntimeAcceptanceBridge {
    static func main() async throws {
        guard (2...3).contains(CommandLine.arguments.count),
              CommandLine.arguments[1].hasPrefix("/"),
              CommandLine.arguments[1] != BridgeSocketLocation.defaultURL.path,
              CommandLine.arguments[1] != BridgeSocketLocation.legacyURL.path else {
            throw BridgeTransportError.malformedEnvelope
        }
        let socket = URL(fileURLWithPath: CommandLine.arguments[1])
        let server = BridgeServer(socketURL: socket,
            runtimeLifecycleRegistryURL: socket.deletingLastPathComponent().appendingPathComponent("lifecycle.json"))
        try server.start()
        defer { server.stop() }
        let client = LocalBridgeClient(socketURL: socket)
        let receipt: FileHandle?
        if CommandLine.arguments.count == 3 {
            let path = CommandLine.arguments[2]
            guard path.hasPrefix("/"), !FileManager.default.fileExists(atPath: path) else {
                throw BridgeTransportError.malformedEnvelope
            }
            FileManager.default.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
            receipt = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        } else { receipt = nil }
        var socketStat = stat()
        _ = lstat(socket.path, &socketStat)
        let socketIdentity = socketStat.st_ino
        signal(SIGTERM, SIG_IGN)
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        termination.setEventHandler { client.disconnect(); server.stop() }
        termination.resume()
        defer {
            termination.cancel(); client.disconnect(); server.stop(); try? receipt?.close()
            var current = stat()
            if lstat(socket.path, &current) == 0, current.st_ino == socketIdentity { _ = unlink(socket.path) }
        }
        let events = try client.connect()
        try await client.send(.registerClient(role: .observer))
        write(["receiver": "ready", "socket": socket.path], receipt: receipt)
        for try await event in events {
            switch event {
            case let .sessionStarted(value):
                write(["event": "sessionStarted", "sessionID": value.sessionID,
                    "tool": value.tool.rawValue, "phase": value.initialPhase.rawValue,
                    "timestamp": value.timestamp.timeIntervalSince1970,
                    "terminalApp": value.jumpTarget?.terminalApp ?? "Unknown",
                    "sourceConversationID": value.jumpTarget?.appConversationID ?? "",
                    "navigationSocket": value.jumpTarget?.runtimeNavigationSocketPath ?? ""], receipt: receipt)
            case let .sessionCompleted(value):
                write(["event": "sessionCompleted", "sessionID": value.sessionID,
                    "outcome": value.runtimeOutcome?.rawValue ?? "unknown",
                    "isInterrupt": value.isInterrupt ?? false, "isSessionEnd": value.isSessionEnd ?? false,
                    "timestamp": value.timestamp.timeIntervalSince1970], receipt: receipt)
            default: break
            }
        }
    }
    static func write(_ value: [String: Any], receipt: FileHandle?) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        print(text)
        fflush(stdout)
        try? receipt?.write(contentsOf: data + Data([10]))
    }
}
