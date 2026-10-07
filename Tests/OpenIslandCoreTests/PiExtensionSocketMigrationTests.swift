import Darwin
import Foundation
import Testing
@testable import OpenIslandCore

struct PiExtensionSocketMigrationTests {
    @Test func existingPrivateTmpDestinationRetainsItsAdmittedLiteral() throws {
        let root = URL(fileURLWithPath: "/private/tmp/aisland-pi-existing-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let socket = root.appendingPathComponent("bridge.sock")
        try Data().write(to: socket)
        let manager = PiExtensionInstallationManager(agent: .ohMyPi, agentDirectory: root.appendingPathComponent("agent"))
        let status = try manager.install(extensionSourceData: Data(source.utf8), targetSocketURL: socket)
        #expect(status.isCurrent && status.manifest?.targetSocketPath == socket.path)
        #expect(try manager.status(targetSocketURL: socket).isCurrent)
        #expect(throws: PiExtensionInstallationError.invalidSocketPath) {
            try manager.status(targetSocketURL: URL(fileURLWithPath: root.path + "/../bridge.sock"))
        }
    }

    private let source = """
    const AGENT_SOURCE = "__OPEN_ISLAND_PI_SOURCE__";
    const SOCKET_PATH =
      process.env.OPEN_ISLAND_SOCKET_PATH ||
      `${process.env.HOME || homedir()}/Library/Application Support/OpenIsland/bridge.sock`;
    // Preserve the reviewed extension's other code.
    """
    private func fixture(_ agent: PiAgentVariant = .ohMyPi) -> PiExtensionInstallationManager {
        PiExtensionInstallationManager(agent: agent, agentDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("aisland-pi-migration-" + UUID().uuidString))
    }
    private func legacy(_ manager: PiExtensionInstallationManager, bytes: Data? = nil) throws {
        try FileManager.default.createDirectory(at: manager.extensionsDirectory, withIntermediateDirectories: true)
        let data = bytes ?? Data(source.replacingOccurrences(of: PiExtensionInstallationManager.agentPlaceholder, with: manager.agent.rawValue).utf8)
        try data.write(to: manager.extensionURL)
        let manifest = PiExtensionInstallerManifest(agent: manager.agent, extensionPath: manager.extensionURL.path, version: 3)
        try JSONEncoder().encode(manifest).write(to: manager.manifestURL)
    }
    private func backups(_ manager: PiExtensionInstallationManager) throws -> [URL] {
        let root = manager.agentDirectory.appendingPathComponent("connection-backups")
        return FileManager.default.fileExists(atPath: root.path)
            ? try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) : []
    }

    @Test(arguments: PiAgentVariant.allCases)
    func explicitSocketOverridesInheritedEnvironmentAndDefaultRemainsUnchanged(agent: PiAgentVariant) throws {
        let manager = fixture(agent)
        defer { try? FileManager.default.removeItem(at: manager.agentDirectory) }
        let original = Data(source.utf8)
        let normal = try manager.install(extensionSourceData: original)
        #expect(normal.isCurrent && normal.manifest?.targetSocketPath == nil)
        #expect(try String(contentsOf: manager.extensionURL, encoding: .utf8).contains("process.env.OPEN_ISLAND_SOCKET_PATH"))
        let socket = URL(fileURLWithPath: "/private/tmp/aisland-fixture/bridge.sock")
        let routed = try manager.install(extensionSourceData: original, targetSocketURL: socket)
        #expect(routed.isCurrent && routed.manifest?.targetSocketPath == socket.path)
        let rendered = try String(contentsOf: manager.extensionURL, encoding: .utf8)
        let expression = try #require(rendered.components(separatedBy: "const SOCKET_PATH = ").last?.components(separatedBy: ";").first)
        #expect(try JSONDecoder().decode(String.self, from: Data(expression.utf8)) == socket.path)
        #expect(!rendered.contains("process.env.OPEN_ISLAND_SOCKET_PATH"))
        #expect(rendered.contains("Preserve the reviewed extension's other code."))
        #expect(try !manager.status().isCurrent)
        #expect(try manager.status(targetSocketURL: socket).isCurrent)
        #expect(try !manager.status(targetSocketURL: URL(fileURLWithPath: "/private/tmp/another/bridge.sock")).isCurrent)
    }

    @Test func exactLegacyTemplateMigrationBacksUpBothFilesAndRepeatIsIdempotent() throws {
        let manager = fixture()
        defer { try? FileManager.default.removeItem(at: manager.agentDirectory) }
        try legacy(manager)
        let original = try Data(contentsOf: manager.extensionURL)
        let manifest = try Data(contentsOf: manager.manifestURL)
        let sibling = manager.extensionsDirectory.appendingPathComponent("user-owned.ts")
        try Data("untouched".utf8).write(to: sibling)
        let socket = URL(fileURLWithPath: "/private/tmp/fixture/bridge.sock")
        #expect(try manager.status().isInstalled && !manager.status().isCurrent)
        #expect(try manager.install(extensionSourceData: Data(source.utf8), targetSocketURL: socket).isCurrent)
        let saved = try #require(try backups(manager).first)
        #expect(try Data(contentsOf: saved.appendingPathComponent("open-island.ts")) == original)
        #expect(try Data(contentsOf: saved.appendingPathComponent(PiExtensionInstallerManifest.fileName)) == manifest)
        #expect(try Data(contentsOf: sibling) == Data("untouched".utf8))
        let updated = try Data(contentsOf: manager.extensionURL)
        #expect(try manager.install(extensionSourceData: Data(source.utf8), targetSocketURL: socket).isCurrent)
        #expect(try backups(manager).count == 1)
        #expect(try Data(contentsOf: manager.extensionURL) == updated)
    }

    @Test func receiptVerifiedRelocationCanReturnToProductionWithoutDeletingBackups() throws {
        let manager = fixture(.pi)
        defer { try? FileManager.default.removeItem(at: manager.agentDirectory) }
        let bytes = Data(source.utf8)
        _ = try manager.install(extensionSourceData: bytes, targetSocketURL: URL(fileURLWithPath: "/private/tmp/one/bridge.sock"))
        _ = try manager.install(extensionSourceData: bytes, targetSocketURL: URL(fileURLWithPath: "/private/tmp/two/bridge.sock"))
        #expect(try manager.install(extensionSourceData: bytes).isCurrent)
        #expect(try backups(manager).count == 2)
        #expect(try String(contentsOf: manager.extensionURL, encoding: .utf8).contains("process.env.OPEN_ISLAND_SOCKET_PATH"))
    }

    @Test func foreignSameNameAndModifiedLegacyAreNotOverwritten() throws {
        for hasManifest in [false, true] {
            let manager = fixture()
            defer { try? FileManager.default.removeItem(at: manager.agentDirectory) }
            let foreign = Data("foreign or user modified source".utf8)
            try legacy(manager, bytes: foreign)
            if !hasManifest { try FileManager.default.removeItem(at: manager.manifestURL) }
            #expect(throws: PiExtensionInstallationError.unverifiedOwnedExtension) {
                try manager.install(extensionSourceData: Data(source.utf8), targetSocketURL: URL(fileURLWithPath: "/tmp/test.sock"))
            }
            #expect(try Data(contentsOf: manager.extensionURL) == foreign)
            #expect(try backups(manager).isEmpty)
        }
    }

    @Test func modifiedReceiptFileIsNotCurrentAndCannotBeMigratedOrRemoved() throws {
        let manager = fixture()
        defer { try? FileManager.default.removeItem(at: manager.agentDirectory) }
        _ = try manager.install(extensionSourceData: Data(source.utf8))
        let originalManifest = try Data(contentsOf: manager.manifestURL)
        let modified = Data("user change".utf8)
        try modified.write(to: manager.extensionURL)
        #expect(try !manager.status().isCurrent)
        #expect(throws: PiExtensionInstallationError.unverifiedOwnedExtension) {
            try manager.install(extensionSourceData: Data(source.utf8), targetSocketURL: URL(fileURLWithPath: "/tmp/test.sock"))
        }
        #expect(throws: PiExtensionInstallationError.unverifiedOwnedExtension) { try manager.uninstall() }
        #expect(try Data(contentsOf: manager.extensionURL) == modified)
        #expect(try Data(contentsOf: manager.manifestURL) == originalManifest)
    }

    @Test func symlinkExtensionAndManifestAreRejected() throws {
        for name in ["open-island.ts", PiExtensionInstallerManifest.fileName] {
            let manager = fixture()
            defer { try? FileManager.default.removeItem(at: manager.agentDirectory) }
            try legacy(manager)
            let selected = name == "open-island.ts" ? manager.extensionURL : manager.manifestURL
            let other = manager.agentDirectory.appendingPathComponent("unrelated")
            let bytes = try Data(contentsOf: selected)
            try bytes.write(to: other)
            try FileManager.default.removeItem(at: selected)
            try FileManager.default.createSymbolicLink(at: selected, withDestinationURL: other)
            #expect(throws: PiExtensionInstallationError.unsafePath) { try manager.install(extensionSourceData: Data(source.utf8)) }
            #expect(try Data(contentsOf: other) == bytes)
        }
    }

    @Test func missingSocketContractAndUnsafeSocketDoNotCreateConfiguration() throws {
        let manager = fixture()
        defer { try? FileManager.default.removeItem(at: manager.agentDirectory) }
        #expect(throws: PiExtensionInstallationError.missingSocketDeclaration) {
            try manager.install(extensionSourceData: Data("__OPEN_ISLAND_PI_SOURCE__".utf8), targetSocketURL: URL(fileURLWithPath: "/tmp/test.sock"))
        }
        #expect(throws: PiExtensionInstallationError.invalidSocketPath) {
            try manager.install(extensionSourceData: Data(source.utf8), targetSocketURL: URL(string: "https://example.com/test.sock")!)
        }
        #expect(throws: PiExtensionInstallationError.invalidSocketPath) {
            try manager.install(extensionSourceData: Data(source.utf8), targetSocketURL: URL(fileURLWithPath: "/" + String(repeating: "x", count: 104)))
        }
        #expect(!FileManager.default.fileExists(atPath: manager.agentDirectory.path))
    }

    @Test func legacyRemovalRequiresExactBundledSource() throws {
        let manager = fixture()
        defer { try? FileManager.default.removeItem(at: manager.agentDirectory) }
        try legacy(manager)
        #expect(throws: PiExtensionInstallationError.unverifiedOwnedExtension) { try manager.uninstall() }
        #expect(try !manager.uninstall(extensionSourceData: Data(source.utf8)).isInstalled)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AISLAND_TEST_PI_SOURCE"] != nil
                   && ProcessInfo.processInfo.environment["AISLAND_TEST_BUN"] != nil))
    func actualBundledExtensionSendsToExplicitSocketDespiteWrongInheritedSocket() throws {
        let environment = ProcessInfo.processInfo.environment
        let sourcePath = try #require(environment["AISLAND_TEST_PI_SOURCE"])
        let bunPath = try #require(environment["AISLAND_TEST_BUN"])
        let manager = fixture()
        defer { try? FileManager.default.removeItem(at: manager.agentDirectory) }
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL, monitorMiniMaxCode: false)
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: socketURL) }
        _ = try manager.install(extensionSourceData: Data(contentsOf: URL(fileURLWithPath: sourcePath)), targetSocketURL: socketURL)
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
        let importLiteral = String(decoding: try JSONEncoder().encode(manager.extensionURL.path), as: UTF8.self)
        // Import the owned callback module, not the source CLI. A mock API emits
        // only a synthetic session-start, without a prompt or any agent task.
        let harness = """
        import callback from \(importLiteral);
        const handlers = new Map();
        callback({ on: (name, handler) => handlers.set(name, handler) });
        const ctx = { cwd: "/tmp", sessionManager: { getSessionId: () => "omp-socket-fixture" } };
        handlers.get("session_start")({}, ctx);
        await new Promise(resolve => setTimeout(resolve, 400));
        handlers.get("session_shutdown")({ reason: "reload" }, ctx);
        """
        let script = manager.agentDirectory.appendingPathComponent("mock-extension-api.ts")
        try Data(harness.utf8).write(to: script)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bunPath)
        process.arguments = [script.path]
        process.environment = ["PATH": "/usr/bin:/bin", "TERM_PROGRAM": "ghostty",
                               "OPEN_ISLAND_SOCKET_PATH": manager.agentDirectory.appendingPathComponent("wrong.sock").path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        var started: SessionStarted?
        while started == nil {
            started = try readEnvelopes().compactMap { envelope in
                if case let .event(.sessionStarted(value)) = envelope { return value }
                return nil
            }.first
        }
        #expect(started?.tool == .ohMyPi)
        #expect(started?.jumpTarget?.terminalApp == "Ghostty")
    }
}
