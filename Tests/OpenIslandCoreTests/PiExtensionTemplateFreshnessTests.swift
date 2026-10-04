import Foundation
import Testing
@testable import OpenIslandCore

struct PiExtensionTemplateFreshnessTests {
    private var repository: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private var latestSource: Data { get throws { try Data(contentsOf: repository.appendingPathComponent("Sources/OpenIslandApp/Resources/open-island-pi.ts")) } }
    private var legacySource: Data { get throws { try Data(contentsOf: repository.appendingPathComponent("Tests/Fixtures/PiExtension/open-island-v3-7b2107d.ts")) } }
    private func fixture(_ agent: PiAgentVariant) -> PiExtensionInstallationManager {
        .init(agent: agent, agentDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("pi-template-fixture-" + UUID().uuidString))
    }
    @Test(arguments: PiAgentVariant.allCases)
    func oldV4SameSocketIsOutdatedUntilLatestTemplateIsInstalled(_ agent: PiAgentVariant) throws {
        let manager = fixture(agent); defer { try? FileManager.default.removeItem(at: manager.agentDirectory) }
        let socket = URL(fileURLWithPath: "/private/tmp/pi-template-fixture/bridge.sock")
        let old = try legacySource, latest = try latestSource
        #expect(try manager.install(extensionSourceData: old, targetSocketURL: socket).isCurrent)
        #expect(try !manager.status(targetSocketURL: socket, extensionSourceData: latest).isCurrent)
        let updated = try manager.install(extensionSourceData: latest, targetSocketURL: socket)
        #expect(updated.isCurrent)
        #expect(try manager.status(targetSocketURL: socket, extensionSourceData: latest).isCurrent)
        #expect(try !manager.status(targetSocketURL: URL(fileURLWithPath: "/private/tmp/other.sock"), extensionSourceData: latest).isCurrent)
        #expect(try manager.status(targetSocketURL: socket, extensionSourceData: latest).actualExtensionSHA256 != manager.status(targetSocketURL: socket, extensionSourceData: old).expectedExtensionSHA256)
    }
    @Test(arguments: PiAgentVariant.allCases)
    func reviewedV3MigratesWithExactBackupAndForeignReceiptOrChangedBytesFailClosed(_ agent: PiAgentVariant) throws {
        for mutation in ["none", "bytes", "agent", "path"] {
            let manager = fixture(agent); defer { try? FileManager.default.removeItem(at: manager.agentDirectory) }
            try FileManager.default.createDirectory(at: manager.extensionsDirectory, withIntermediateDirectories: true)
            let template = try #require(String(data: legacySource, encoding: .utf8))
            let bytes = Data((template.replacingOccurrences(of: PiExtensionInstallationManager.agentPlaceholder, with: agent.rawValue) + (mutation == "bytes" ? "\n// foreign modification" : "")).utf8)
            try bytes.write(to: manager.extensionURL)
            let manifest = PiExtensionInstallerManifest(agent: mutation == "agent" ? (agent == .pi ? .ohMyPi : .pi) : agent,
                extensionPath: mutation == "path" ? "/foreign/open-island.ts" : manager.extensionURL.path, version: 3)
            let receipt = try JSONEncoder().encode(manifest); try receipt.write(to: manager.manifestURL)
            if mutation == "none" {
                #expect(try manager.install(extensionSourceData: latestSource).isCurrent)
                let backups = try FileManager.default.contentsOfDirectory(at: manager.agentDirectory.appendingPathComponent("connection-backups"), includingPropertiesForKeys: nil)
                let backup = try #require(backups.first)
                #expect(backups.count == 1)
                #expect(try Data(contentsOf: backup.appendingPathComponent("open-island.ts")) == bytes)
                #expect(try Data(contentsOf: backup.appendingPathComponent(PiExtensionInstallerManifest.fileName)) == receipt)
            } else {
                #expect(throws: PiExtensionInstallationError.unverifiedOwnedExtension) { try manager.install(extensionSourceData: latestSource) }
                #expect(try Data(contentsOf: manager.extensionURL) == bytes)
                #expect(try Data(contentsOf: manager.manifestURL) == receipt)
            }
        }
    }
}
