import Foundation
import CryptoKit

public struct PiExtensionInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-pi-extension-install.json"
    public static let currentVersion = 4

    public var agent: PiAgentVariant
    public var extensionPath: String
    public var version: Int?
    public var extensionSHA256: String?
    public var targetSocketPath: String?

    public init(
        agent: PiAgentVariant,
        extensionPath: String,
        version: Int? = Self.currentVersion,
        extensionSHA256: String? = nil,
        targetSocketPath: String? = nil
    ) {
        self.agent = agent
        self.extensionPath = extensionPath
        self.version = version
        self.extensionSHA256 = extensionSHA256
        self.targetSocketPath = targetSocketPath
    }
}

public struct PiExtensionInstallationStatus: Equatable, Codable, Sendable {
    public var agent: PiAgentVariant
    public var agentDirectory: URL
    public var extensionsDirectory: URL
    public var extensionURL: URL
    public var manifestURL: URL
    public var extensionFilePresent: Bool
    public var manifest: PiExtensionInstallerManifest?
    public var actualExtensionSHA256: String?
    public var requestedSocketPath: String?

    public var isInstalled: Bool {
        extensionFilePresent
            && manifest?.agent == agent
            && manifest?.extensionPath == extensionURL.path
    }

    public var isCurrent: Bool {
        isInstalled && manifest?.version == PiExtensionInstallerManifest.currentVersion
            && manifest?.extensionSHA256 != nil && manifest?.extensionSHA256 == actualExtensionSHA256
            && manifest?.targetSocketPath == requestedSocketPath
    }

    public init(
        agent: PiAgentVariant,
        agentDirectory: URL,
        extensionsDirectory: URL,
        extensionURL: URL,
        manifestURL: URL,
        extensionFilePresent: Bool,
        manifest: PiExtensionInstallerManifest?,
        actualExtensionSHA256: String? = nil,
        requestedSocketPath: String? = nil
    ) {
        self.agent = agent
        self.agentDirectory = agentDirectory
        self.extensionsDirectory = extensionsDirectory
        self.extensionURL = extensionURL
        self.manifestURL = manifestURL
        self.extensionFilePresent = extensionFilePresent
        self.manifest = manifest
        self.actualExtensionSHA256 = actualExtensionSHA256
        self.requestedSocketPath = requestedSocketPath
    }
}

public enum PiExtensionInstallationError: LocalizedError, Equatable {
    case invalidSourceEncoding
    case missingAgentPlaceholder
    case invalidSocketPath, missingSocketDeclaration, unverifiedOwnedExtension, configurationChanged, unsafePath

    public var errorDescription: String? {
        switch self {
        case .invalidSourceEncoding:
            "The bundled Pi extension is not valid UTF-8."
        case .missingAgentPlaceholder:
            "The bundled Pi extension is missing its agent placeholder."
        case .invalidSocketPath:
            "The AIsland callback socket path is invalid."
        case .missingSocketDeclaration:
            "The bundled Pi extension does not have the reviewed callback socket declaration."
        case .unverifiedOwnedExtension:
            "The existing extension does not match a verified AIsland-owned file. It was left unchanged."
        case .configurationChanged:
            "The extension changed during setup. Refresh and retry."
        case .unsafePath:
            "The extension path is not a regular owned file or directory."
        }
    }
}

public final class PiExtensionInstallationManager: @unchecked Sendable {
    public static let extensionFileName = "open-island.ts"
    public static let agentPlaceholder = "__OPEN_ISLAND_PI_SOURCE__"
    /// Exact reviewed declaration; an explicit case socket takes precedence
    /// over inherited environment without changing the source's global env.
    private static let socketDeclaration = """
    const SOCKET_PATH =
      process.env.OPEN_ISLAND_SOCKET_PATH ||
      `${process.env.HOME || homedir()}/Library/Application Support/OpenIsland/bridge.sock`;
    """

    public let agent: PiAgentVariant
    public let agentDirectory: URL
    private let fileManager: FileManager

    public init(
        agent: PiAgentVariant,
        agentDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.agent = agent
        self.agentDirectory = agentDirectory ?? Self.defaultAgentDirectory(for: agent)
        self.fileManager = fileManager
    }

    public static func defaultAgentDirectory(for agent: PiAgentVariant) -> URL {
        let directoryName = agent == .pi ? ".pi" : ".omp"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
    }

    public var extensionsDirectory: URL {
        agentDirectory.appendingPathComponent("extensions", isDirectory: true)
    }

    public var extensionURL: URL {
        extensionsDirectory.appendingPathComponent(Self.extensionFileName)
    }

    public var manifestURL: URL {
        agentDirectory.appendingPathComponent(PiExtensionInstallerManifest.fileName)
    }

    public func status(targetSocketURL: URL? = nil) throws -> PiExtensionInstallationStatus {
        let target = try validatedSocketPath(targetSocketURL)
        let extensionData = try regularFileData(at: extensionURL)
        return PiExtensionInstallationStatus(
            agent: agent,
            agentDirectory: agentDirectory,
            extensionsDirectory: extensionsDirectory,
            extensionURL: extensionURL,
            manifestURL: manifestURL,
            extensionFilePresent: extensionData != nil,
            manifest: try loadManifest(),
            actualExtensionSHA256: extensionData.map(Self.sha256), requestedSocketPath: target
        )
    }

    @discardableResult
    public func install(extensionSourceData: Data, targetSocketURL: URL? = nil) throws -> PiExtensionInstallationStatus {
        let target = try validatedSocketPath(targetSocketURL)
        guard var source = String(data: extensionSourceData, encoding: .utf8) else {
            throw PiExtensionInstallationError.invalidSourceEncoding
        }
        guard source.contains(Self.agentPlaceholder) else {
            throw PiExtensionInstallationError.missingAgentPlaceholder
        }

        source = source.replacingOccurrences(of: Self.agentPlaceholder, with: agent.rawValue)
        let productionData = Data(source.utf8)
        if let target {
            guard source.components(separatedBy: Self.socketDeclaration).count == 2 else {
                throw PiExtensionInstallationError.missingSocketDeclaration
            }
            let literal = String(decoding: try JSONEncoder().encode(target), as: UTF8.self)
            source = source.replacingOccurrences(of: Self.socketDeclaration, with: "const SOCKET_PATH = \(literal);")
        }
        let desired = Data(source.utf8)
        let oldExtension = try regularFileData(at: extensionURL)
        let oldManifestData = try regularFileData(at: manifestURL)
        if oldExtension != nil || oldManifestData != nil {
            guard let oldExtension, let oldManifestData,
                  let old = try? JSONDecoder().decode(PiExtensionInstallerManifest.self, from: oldManifestData),
                  old.agent == agent, old.extensionPath == extensionURL.path,
                  old.version == 3 || old.version == PiExtensionInstallerManifest.currentVersion else {
                throw PiExtensionInstallationError.unverifiedOwnedExtension
            }
            // The old version 3 receipt has no hash. Admit it only when the
            // installed bytes exactly match the reviewed production template.
            if old.version == PiExtensionInstallerManifest.currentVersion {
                guard let hash = old.extensionSHA256, hash == Self.sha256(oldExtension) else { throw PiExtensionInstallationError.unverifiedOwnedExtension }
            } else {
                guard old.extensionSHA256 == nil, old.targetSocketPath == nil, oldExtension == productionData else {
                    throw PiExtensionInstallationError.unverifiedOwnedExtension
                }
            }
        }

        let manifest = PiExtensionInstallerManifest(agent: agent, extensionPath: extensionURL.path,
            extensionSHA256: Self.sha256(desired), targetSocketPath: target)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        if oldExtension == desired && oldManifestData == manifestData { return try status(targetSocketURL: targetSocketURL) }
        try ensureDirectory(agentDirectory)
        try ensureDirectory(extensionsDirectory)
        if let oldExtension, let oldManifestData { try backup(extensionData: oldExtension, manifestData: oldManifestData) }
        guard try regularFileData(at: extensionURL) == oldExtension,
              try regularFileData(at: manifestURL) == oldManifestData else { throw PiExtensionInstallationError.configurationChanged }
        try desired.write(to: extensionURL, options: .atomic)
        do { try manifestData.write(to: manifestURL, options: .atomic) }
        catch {
            // Restore only our just-written bytes; never overwrite a third producer.
            if (try? regularFileData(at: extensionURL)) == desired {
                if let oldExtension { try? oldExtension.write(to: extensionURL, options: .atomic) }
                else { try? fileManager.removeItem(at: extensionURL) }
            }
            throw error
        }
        return try status(targetSocketURL: targetSocketURL)
    }

    @discardableResult
    public func uninstall(extensionSourceData: Data? = nil) throws -> PiExtensionInstallationStatus {
        let data = try regularFileData(at: extensionURL)
        let manifest = try loadManifest()
        if data != nil || manifest != nil {
            guard let data, let manifest, manifest.agent == agent, manifest.extensionPath == extensionURL.path,
                  manifest.version == 3 || manifest.version == PiExtensionInstallerManifest.currentVersion else {
                throw PiExtensionInstallationError.unverifiedOwnedExtension
            }
            if let hash = manifest.extensionSHA256 {
                guard manifest.version == PiExtensionInstallerManifest.currentVersion, hash == Self.sha256(data) else {
                    throw PiExtensionInstallationError.unverifiedOwnedExtension
                }
            } else {
                guard manifest.version == 3, manifest.targetSocketPath == nil, let extensionSourceData,
                      let source = String(data: extensionSourceData, encoding: .utf8), source.contains(Self.agentPlaceholder),
                      data == Data(source.replacingOccurrences(of: Self.agentPlaceholder, with: agent.rawValue).utf8) else {
                    throw PiExtensionInstallationError.unverifiedOwnedExtension
                }
            }
        }
        if fileManager.fileExists(atPath: extensionURL.path) {
            try fileManager.removeItem(at: extensionURL)
        }
        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }
        return try status()
    }

    private func loadManifest() throws -> PiExtensionInstallerManifest? {
        guard let data = try regularFileData(at: manifestURL) else { return nil }
        return try JSONDecoder().decode(
            PiExtensionInstallerManifest.self,
            from: data
        )
    }

    private func validatedSocketPath(_ url: URL?) throws -> String? {
        guard let url else { return nil }
        let path = url.path
        guard url.isFileURL, path.hasPrefix("/"), path.utf8.count < 104,
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !url.pathComponents.contains("."), !url.pathComponents.contains("..") else { throw PiExtensionInstallationError.invalidSocketPath }
        // Foundation rewrites an existing /private/tmp entry to /tmp during
        // standardization. A live Unix socket must keep its admitted literal;
        // lexical traversal is rejected without filesystem-dependent rewriting.
        return path
    }

    private func regularFileData(at url: URL) throws -> Data? {
        for directory in [agentDirectory, extensionsDirectory] {
            if let type = try? fileManager.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType,
               type != .typeDirectory { throw PiExtensionInstallationError.unsafePath }
        }
        let attributes: [FileAttributeKey: Any]
        do { attributes = try fileManager.attributesOfItem(atPath: url.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= 8 * 1024 * 1024 else {
            throw PiExtensionInstallationError.unsafePath
        }
        return try Data(contentsOf: url)
    }

    private func ensureDirectory(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            guard try fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeDirectory else {
                throw PiExtensionInstallationError.unsafePath
            }
        } else { try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
    }

    private func backup(extensionData: Data, manifestData: Data) throws {
        let parent = agentDirectory.appendingPathComponent("connection-backups")
        try ensureDirectory(parent)
        let directory = parent.appendingPathComponent("aisland-pi-" + UUID().uuidString)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        for (name, data) in [(Self.extensionFileName, extensionData), (PiExtensionInstallerManifest.fileName, manifestData)] {
            let url = directory.appendingPathComponent(name)
            try data.write(to: url, options: .withoutOverwriting)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
