import Darwin
import Foundation
import Testing
@testable import OpenIslandCore

struct DeepSeekNavigationClientTests {
    @Test func dispatchReceiptRequiresAllIdentityFields() throws {
        let request = DeepSeekNavigationClient.Request(profileID: "desktop", sessionID: "s", requestID: "r")
        let valid = #"{"version":1,"request_id":"r","profile_id":"desktop","session_id":"s","status":"dispatched"}"#
        try DeepSeekNavigationClient.validate(Data(valid.utf8), for: request)
        for invalid in [valid.replacingOccurrences(of: "\"r\"", with: "\"wrong\""),
                        valid.replacingOccurrences(of: "\"desktop\"", with: "\"wrong\""),
                        valid.replacingOccurrences(of: "\"s\"", with: "\"wrong\""),
                        valid.replacingOccurrences(of: "\"dispatched\"", with: "\"selected\""),
                        valid.replacingOccurrences(of: "\"dispatched\"", with: "\"failed\""), "{}"] {
            #expect(throws: (any Error).self) { try DeepSeekNavigationClient.validate(Data(invalid.utf8), for: request) }
        }
    }
    @Test func uniqueSocketRoundTripAndTimeout() throws {
        for reply in [true, false] {
            let socketURL = BridgeSocketLocation.uniqueTestURL()
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw DeepSeekNavigationError.unavailable }
            defer { close(fd); try? FileManager.default.removeItem(at: socketURL) }
            try withUnixSocketAddress(path: socketURL.path) { address, length in
                #expect(bind(fd, address, length) == 0)
            }
            #expect(listen(fd, 1) == 0)
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                defer { done.signal() }
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                defer { close(client) }
                var bytes = [UInt8](repeating: 0, count: 4096)
                let count = read(client, &bytes, bytes.count)
                guard count > 0 else { return }
                if reply {
                    guard var object = try? JSONSerialization.jsonObject(with: Data(bytes.prefix(count))) as? [String: Any] else { return }
                    object.removeValue(forKey: "action"); object["status"] = "dispatched"
                    guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
                    data.append(10); try? writeAll(data, to: client)
                } else { Thread.sleep(forTimeInterval: 0.1) }
            }
            let target = JumpTarget(terminalApp: "DeepSeek Harness.app", workspaceName: "test", paneTitle: "test",
                appConversationID: "real-session", runtimeProfileID: "desktop", runtimeNavigationSocketPath: socketURL.path)
            if reply { try DeepSeekNavigationClient().dispatch(target: target, timeout: 0.5) }
            else { #expect(throws: DeepSeekNavigationError.timedOut) { try DeepSeekNavigationClient().dispatch(target: target, timeout: 0.02) } }
            #expect(done.wait(timeout: .now() + 1) == .success)
        }
    }
    @Test func peerThatDoesNotReadCannotExtendWriteDeadline() throws {
        var descriptors: [Int32] = [-1, -1]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        let writer = descriptors[0]; let peer = descriptors[1]
        defer { close(writer); close(peer) }
        try disableSocketSigPipe(writer); try makeSocketNonBlocking(writer)
        var size: Int32 = 2048
        #expect(setsockopt(writer, SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size)) == 0)
        let started = Date()
        #expect(throws: DeepSeekNavigationError.timedOut) {
            try DeepSeekNavigationClient.send(Data(repeating: 65, count: 2_000_000), fd: writer, deadline: started.addingTimeInterval(0.03))
        }
        #expect(Date().timeIntervalSince(started) < 0.3)
    }

    @Test func unavailableEndpointAndMissingIdentityFail() {
        let target = JumpTarget(terminalApp: "DeepSeek Harness.app", workspaceName: "test", paneTitle: "test")
        #expect(throws: DeepSeekNavigationError.missingIdentity) { try DeepSeekNavigationClient().dispatch(target: target) }
        let missing = JumpTarget(terminalApp: "DeepSeek Harness.app", workspaceName: "test", paneTitle: "test",
            appConversationID: "s", runtimeProfileID: "desktop", runtimeNavigationSocketPath: BridgeSocketLocation.uniqueTestURL().path)
        #expect(throws: DeepSeekNavigationError.unavailable) { try DeepSeekNavigationClient().dispatch(target: missing) }
    }
}
