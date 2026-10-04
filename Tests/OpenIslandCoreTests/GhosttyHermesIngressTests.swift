import Darwin
import Foundation
import Testing
@testable import OpenIslandCore

/// Synthetic stdin reaches the real callback executable and a temporary bridge.
/// No source process, terminal UI, source configuration, or GUI locator is used.
struct GhosttyHermesIngressTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AISLAND_TEST_HOOKS_BINARY"] != nil))
    func ghosttyTurnsWithoutWindowIDsReachTheirConfiguredBridge() throws {
        let helper = try #require(ProcessInfo.processInfo.environment["AISLAND_TEST_HOOKS_BINARY"])
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL, monitorMiniMaxCode: false)
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: socketURL) }

        let observer = socket(AF_UNIX, SOCK_STREAM, 0)
        guard observer >= 0 else { throw BridgeTransportError.notConnected }
        defer { close(observer) }
        try disableSocketSigPipe(observer)
        try withUnixSocketAddress(path: socketURL.path) { address, length in
            guard Darwin.connect(observer, address, length) == 0 else { throw BridgeTransportError.notConnected }
        }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        #expect(setsockopt(observer, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0)
        try writeAll(try BridgeCodec.encodeLine(.command(.registerClient(role: .observer))), to: observer)
        var buffer = Data()
        func readEnvelopes() throws -> [BridgeEnvelope] {
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = read(observer, &bytes, bytes.count)
            guard count > 0 else { throw BridgeTransportError.responseTimedOut }
            buffer.append(contentsOf: bytes.prefix(count))
            return try BridgeCodec.decodeLines(from: &buffer)
        }
        while !(try readEnvelopes().contains(.response(.acknowledged))) {}

        func fire(_ event: String, session: String, tty: String, terminal: String) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: helper)
            process.arguments = ["--source", "hermes", "--profile-id", "/tmp/aisland-ghostty-fixture"]
            process.environment = ["PATH": "/usr/bin:/bin", "TERM_PROGRAM": terminal, "TTY": tty,
                                   "OPEN_ISLAND_SOCKET_PATH": socketURL.path]
            let input = Pipe()
            process.standardInput = input
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            let payload: [String: Any] = ["hook_event_name": event, "session_id": session, "cwd": "/tmp",
                "extra": ["turn_id": "turn-" + session, "completed": true]]
            try input.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: payload))
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }
        // Two Ghostty panes plus Terminal: no UUID collision, no focused-pane lookup.
        for (session, tty, terminal) in [("ghostty-one", "/dev/ttys021", "ghostty"),
                                        ("ghostty-two", "/dev/ttys022", "ghostty"),
                                        ("terminal-one", "/dev/ttys023", "Apple_Terminal")] {
            try fire("pre_llm_call", session: session, tty: tty, terminal: terminal)
            try fire("on_session_end", session: session, tty: tty, terminal: terminal)
        }
        var events: [AgentEvent] = []
        while events.filter({ if case .sessionCompleted = $0 { return true }; return false }).count < 3 {
            events += try readEnvelopes().compactMap { if case let .event(event) = $0 { return event }; return nil }
        }
        var state = SessionState()
        events.forEach { state.apply($0) }
        #expect(state.sessions.count == 3)
        #expect(state.sessions.allSatisfy { $0.tool == .hermesCLI && $0.phase == .completed && $0.runtimeOutcome == .succeeded })
        let ghostty = state.sessions.filter { $0.jumpTarget?.terminalApp == "Ghostty" }
        #expect(ghostty.count == 2)
        #expect(ghostty.allSatisfy { $0.jumpTarget?.terminalSessionID == nil })
        #expect(Set(ghostty.compactMap { $0.jumpTarget?.terminalTTY }) == ["/dev/ttys021", "/dev/ttys022"])
        #expect(state.sessions.filter { $0.jumpTarget?.terminalApp == "Terminal" }.count == 1)
    }
}
