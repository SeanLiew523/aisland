import Darwin
import Foundation
import CryptoKit
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
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ds-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let socketURL = directory.appendingPathComponent("nav.sock")
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw DeepSeekNavigationError.unavailable }
            defer { close(fd); try? FileManager.default.removeItem(at: directory) }
            try withUnixSocketAddress(path: socketURL.path) { address, length in
                #expect(bind(fd, address, length) == 0)
            }
            #expect(listen(fd, 1) == 0)
            try writeProof(socketURL: socketURL)
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
            if reply { try fixtureClient.dispatch(target: target, timeout: 0.5) }
            else { #expect(throws: DeepSeekNavigationError.timedOut) { try fixtureClient.dispatch(target: target, timeout: 0.02) } }
            #expect(done.wait(timeout: .now() + 1) == .success)
        }
    }
    private var fixtureClient: DeepSeekNavigationClient {
        DeepSeekNavigationClient(sourceVerifier: { pid, executable in pid == getpid() && executable == "/test/deepseek-host" })
    }
    private func writeProof(socketURL: URL, requestedURL: URL? = nil, peerPID: Int32 = getpid()) throws {
        let requested = requestedURL ?? socketURL
        let directory = socketURL.deletingLastPathComponent().appendingPathComponent(".ds-fixture")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        #expect(chmod(socketURL.path, 0o600) == 0)
        #expect(link(socketURL.path, directory.appendingPathComponent("s").path) == 0)
        var socketStat = stat(); var directoryStat = stat()
        #expect(lstat(socketURL.path, &socketStat) == 0); #expect(lstat(directory.path, &directoryStat) == 0)
        let proof: [String: Any] = ["version": 1, "source": "@aisland/deepseek-harness-plugin", "path": socketURL.path,
            "requested_path": requested.path, "profile_sha256": SHA256.hash(data: Data("desktop".utf8)).map { String(format: "%02x", $0) }.joined(),
            "uid": getuid(), "dev": socketStat.st_dev, "ino": socketStat.st_ino,
            "bind_directory": directory.path, "directory_dev": directoryStat.st_dev, "directory_ino": directoryStat.st_ino,
            "source_pid": peerPID, "executable_path": "/test/deepseek-host"]
        let data = try JSONSerialization.data(withJSONObject: proof)
        for filename in [socketURL.path + ".aisland-owner.json", requested.path + ".aisland-current.json"] {
            try data.write(to: URL(fileURLWithPath: filename)); #expect(chmod(filename, 0o600) == 0)
        }
    }

    @Test func cachedLegacyTargetUsesCurrentOwnedEndpointAndExactIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ds-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = directory.appendingPathComponent("legacy.sock"); let current = directory.appendingPathComponent("current.sock")
        let oldFD = socket(AF_UNIX, SOCK_STREAM, 0)
        try withUnixSocketAddress(path: legacy.path) { #expect(bind(oldFD, $0, $1) == 0) }; close(oldFD)
        var oldStat = stat(); #expect(lstat(legacy.path, &oldStat) == 0)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0); defer { close(fd) }
        try withUnixSocketAddress(path: current.path) { #expect(bind(fd, $0, $1) == 0) }; #expect(listen(fd, 1) == 0)
        try writeProof(socketURL: current, requestedURL: legacy)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            defer { done.signal() }
            let client = accept(fd, nil, nil); guard client >= 0 else { return }; defer { close(client) }
            var bytes = [UInt8](repeating: 0, count: 4096); let count = read(client, &bytes, bytes.count)
            guard count > 0, var object = try? JSONSerialization.jsonObject(with: Data(bytes.prefix(count))) as? [String: Any] else { return }
            #expect(object["session_id"] as? String == "cached-exact-session"); #expect(object["profile_id"] as? String == "desktop")
            object.removeValue(forKey: "action"); object["status"] = "dispatched"
            guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
            data.append(10); try? writeAll(data, to: client)
        }
        let target = JumpTarget(terminalApp: "DeepSeek Harness.app", workspaceName: "test", paneTitle: "test",
            appConversationID: "cached-exact-session", runtimeProfileID: "desktop", runtimeNavigationSocketPath: legacy.path)
        try fixtureClient.dispatch(target: target, timeout: 0.5)
        #expect(done.wait(timeout: .now() + 1) == .success)
        var after = stat(); #expect(lstat(legacy.path, &after) == 0); #expect(oldStat.st_ino == after.st_ino)
    }

    @Test func unknownConnectableEndpointNeverReceivesNavigation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ds-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("unknown.sock").path
        let fd = socket(AF_UNIX, SOCK_STREAM, 0); defer { close(fd) }
        try withUnixSocketAddress(path: path) { #expect(bind(fd, $0, $1) == 0) }; #expect(listen(fd, 1) == 0); try makeSocketNonBlocking(fd)
        let target = JumpTarget(terminalApp: "DeepSeek Harness.app", workspaceName: "test", paneTitle: "test",
            appConversationID: "exact-session", runtimeProfileID: "desktop", runtimeNavigationSocketPath: path)
        #expect(throws: DeepSeekNavigationError.unavailable) { try fixtureClient.dispatch(target: target, timeout: 0.1) }
        #expect(accept(fd, nil, nil) == -1); #expect(errno == EAGAIN || errno == EWOULDBLOCK)
    }

    @Test func connectedPeerPIDMustMatchProofBeforeAnyRequest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ds-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let socketURL = directory.appendingPathComponent("nav.sock"); let fd = socket(AF_UNIX, SOCK_STREAM, 0); defer { close(fd) }
        try withUnixSocketAddress(path: socketURL.path) { #expect(bind(fd, $0, $1) == 0) }; #expect(listen(fd, 1) == 0)
        try writeProof(socketURL: socketURL, peerPID: getpid() + 1)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            defer { done.signal() }
            let client = accept(fd, nil, nil); guard client >= 0 else { return }; defer { close(client) }
            var bytes = [UInt8](repeating: 0, count: 1024)
            #expect(read(client, &bytes, bytes.count) == 0)
        }
        let target = JumpTarget(terminalApp: "DeepSeek Harness.app", workspaceName: "test", paneTitle: "test",
            appConversationID: "exact-session", runtimeProfileID: "desktop", runtimeNavigationSocketPath: socketURL.path)
        let client = DeepSeekNavigationClient(sourceVerifier: { _, _ in true })
        #expect(throws: DeepSeekNavigationError.unavailable) { try client.dispatch(target: target, timeout: 0.1) }
        #expect(done.wait(timeout: .now() + 1) == .success)
    }

    @Test func locatorRequiresProfileSourceIdentityAndSafeFiles() throws {
        for invalid in ["profile", "socket", "directory", "source", "symlink", "host"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ds-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            let socketURL = directory.appendingPathComponent("nav.sock"); let fd = socket(AF_UNIX, SOCK_STREAM, 0); defer { close(fd) }
            try withUnixSocketAddress(path: socketURL.path) { #expect(bind(fd, $0, $1) == 0) }; #expect(listen(fd, 1) == 0)
            try writeProof(socketURL: socketURL)
            let locator = URL(fileURLWithPath: socketURL.path + ".aisland-current.json")
            var proof = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: locator)) as? [String: Any])
            switch invalid {
            case "profile": proof["profile_sha256"] = "other"
            case "socket": proof["ino"] = 0
            case "directory": proof["directory_ino"] = 0
            case "source": proof["source"] = "other-plugin"
            case "symlink":
                let other = directory.appendingPathComponent("foreign.json"); try FileManager.default.moveItem(at: locator, to: other)
                try FileManager.default.createSymbolicLink(at: locator, withDestinationURL: other)
            default: break
            }
            if invalid != "symlink" { try JSONSerialization.data(withJSONObject: proof).write(to: locator) }
            let target = JumpTarget(terminalApp: "DeepSeek Harness.app", workspaceName: "test", paneTitle: "test",
                appConversationID: "exact-session", runtimeProfileID: "desktop", runtimeNavigationSocketPath: socketURL.path)
            let client = invalid == "host" ? DeepSeekNavigationClient() : fixtureClient
            #expect(throws: DeepSeekNavigationError.unavailable) { try client.dispatch(target: target, timeout: 0.1) }
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
