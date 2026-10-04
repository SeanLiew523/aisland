import Foundation
import CryptoKit

/// Reviewed local plugin deployment; source startup, tasks and permission grants
/// are never part of this service. A deployed plugin is not a verified live connection.
public struct DesktopConnectionInstallationManager: Sendable {
    public enum State: String, Codable, Sendable {
        case waitingForSourceExit, waitingForProfile, waitingForActivation, configuredFiles, eventReceived
    }
    public enum Failure: Error, LocalizedError, Equatable {
        case unsupportedVersion, missingRuntime, unownedInstallation, invalidMetadata, changedConfiguration
        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion: "This Desktop version has not been reviewed for automatic connection setup."
            case .missingRuntime: "The bundled event adapter or its local runtime is unavailable."
            case .unownedInstallation: "Existing plugin files do not match AIsland's ownership receipt. They were preserved."
            case .invalidMetadata: "The source profile or active data directory could not be identified uniquely."
            case .changedConfiguration: "Source configuration changed during setup. Check again."
            }
        }
    }
    public typealias Runner = @Sendable (URL, [String], [String: String]) throws -> Data
    public let home: URL
    public let supportDirectory: URL
    public let packagesDirectory: URL
    public let nodeURL: URL?
    public let bundledProbeURL: URL?
    public let bridgeSocketURL: URL
    public let preservesPreviousHelper: Bool
    private let runner: Runner
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                supportDirectory: URL? = nil, packagesDirectory: URL, nodeURL: URL?, bundledProbeURL: URL? = nil, bridgeSocketURL: URL = BridgeSocketLocation.defaultURL,
                preservesPreviousHelper: Bool = false,
                runner: @escaping Runner = { try ConnectionProcessRunner.run($0, arguments: $1, environment: $2, timeout: 45) }) {
        self.home = home; self.supportDirectory = supportDirectory ?? home.appendingPathComponent("Library/Application Support/AIsland")
        self.packagesDirectory = packagesDirectory; self.nodeURL = nodeURL; self.bundledProbeURL = bundledProbeURL; self.bridgeSocketURL = bridgeSocketURL
        self.preservesPreviousHelper = preservesPreviousHelper; self.runner = runner
    }
    private var environment: [String: String] {
        ["HOME": home.path, "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "LC_ALL": "C", "DSH_HOME": home.appendingPathComponent(".dsh").path]
    }
    public func configureMiniMax(evidence: AgentInstallationDetector.Evidence, activeDataDirectory: URL?) throws -> State {
        guard evidence.version == "3.1.0", let app = evidence.bundleURL else { throw Failure.unsupportedVersion }
        guard let dataDir = activeDataDirectory else { return .waitingForProfile }
        try directory(dataDir)
        // The shipped helper is mandatory for native setup. Never invoke swiftc
        // or ask a normal App user to install a development toolchain.
        guard let bundledProbeURL, FileManager.default.isExecutableFile(atPath: bundledProbeURL.path) else { throw Failure.missingRuntime }
        let probeHash = digest(try regular(bundledProbeURL, maximum: 4 * 1024 * 1024))
        let externalNode = nodeURL.flatMap { value -> URL? in
            FileManager.default.isExecutableFile(atPath: value.path)
                && (try? value.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true ? value : nil
        }
        let runtime = externalNode ?? evidence.executableURL
        guard FileManager.default.isExecutableFile(atPath: runtime.path),
              (try runtime.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { throw Failure.missingRuntime }
        let kind = externalNode == nil ? "minimaxDesktopElectron" : "node"
        var runtimeEnvironment = environment
        if externalNode == nil { runtimeEnvironment["ELECTRON_RUN_AS_NODE"] = "1" }
        let installer = packagesDirectory.appendingPathComponent("MiniMaxCode/scripts/install.mjs")
        _ = try regular(installer)
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        var support = supportDirectory
        var previousHelperDirectory: String?
        let configURL = dataDir.appendingPathComponent("plugins/aisland-minimaxcode-passive/config.json")
        if FileManager.default.fileExists(atPath: configURL.path) {
            // Read only this exact plugin's ownership metadata; installer performs
            // full path/inventory/hash validation again before any mutation.
            let config = try json(configURL)
            guard let discovery = config["sourceDiscovery"] as? [String: Any], let path = discovery["probePath"] as? String,
                  path.hasPrefix("/"), URL(fileURLWithPath: path).lastPathComponent == "source-probe" else { throw Failure.unownedInstallation }
            let helper = URL(fileURLWithPath: path).deletingLastPathComponent()
            guard helper.lastPathComponent == "minimaxcode-passive" else { throw Failure.unownedInstallation }
            let receipt = try json(helper.appendingPathComponent("receipt.json"))
            guard receipt["owner"] as? String == "aisland.minimaxcode-passive.installer",
                  receipt["dataDir"] as? String == dataDir.resolvingSymlinksInPath().path,
                  receipt["helperDirectory"] as? String == helper.path else { throw Failure.unownedInstallation }
            if preservesPreviousHelper && helper.path != supportDirectory.appendingPathComponent("minimaxcode-passive").path {
                previousHelperDirectory = helper.path
            } else { support = helper.deletingLastPathComponent() }
        }
        var request: [String: Any] = ["operation": "install", "dataDirConfirmed": true,
            "dataDir": dataDir.resolvingSymlinksInPath().path, "supportDir": support.path,
            "bridgeSocketPath": bridgeSocketURL.path, "nodePath": runtime.path,
            "hookRuntimeKind": kind, "bundledProbePath": bundledProbeURL.path, "bundledProbeHash": probeHash,
            "desktopAppPath": app.path, "cliPrefix": home.appendingPathComponent(".minimax-code").path,
            "profileID": "desktop", "enableCLI": false]
        if let previousHelperDirectory { request["previousHelperDirectory"] = previousHelperDirectory }
        let plan = try jsonData(runner(runtime, [installer.path, try jsonString(request)], runtimeEnvironment))
        guard let action = plan["action"] as? String else { throw Failure.invalidMetadata }
        if action == "already-installed" { return .waitingForActivation }
        if action == "replace-owned" {
            guard let destination = plan["destination"] as? String,
                  let existingReceipt = plan["existingReceipt"] as? [String: Any],
                  let previousHelper = existingReceipt["helperDirectory"] as? String,
                  let helperPath = existingReceipt["helperPath"] as? String,
                  let files = plan["copyFiles"] as? [String] else { throw Failure.invalidMetadata }
            let receiptPath = URL(fileURLWithPath: previousHelper).appendingPathComponent("receipt.json").path
            let backup = try backupDirectory("minimax")
            for relative in files + ["config.json"] {
                guard !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else { throw Failure.invalidMetadata }
                let source = URL(fileURLWithPath: destination).appendingPathComponent(relative)
                _ = try regular(source)
                let target = backup.appendingPathComponent("plugin/" + relative)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: target)
            }
            _ = try regular(URL(fileURLWithPath: receiptPath))
            try FileManager.default.copyItem(at: URL(fileURLWithPath: receiptPath), to: backup.appendingPathComponent("receipt.json"))
            _ = try regular(URL(fileURLWithPath: helperPath), maximum: 4 * 1024 * 1024)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: helperPath), to: backup.appendingPathComponent("source-probe"))
        }
        request["apply"] = true
        let result = try jsonData(runner(runtime, [installer.path, try jsonString(request)], runtimeEnvironment))
        guard result["mode"] as? String == "applied", ["installed", "already-installed"].contains(result["result"] as? String ?? "") else { throw Failure.invalidMetadata }
        return .waitingForActivation
    }

    public func configureDeepSeek(evidence: AgentInstallationDetector.Evidence, sourceRunning: Bool) throws -> State {
        guard evidence.version == "0.2.0-rc.2", let app = evidence.bundleURL else { throw Failure.unsupportedVersion }
        let profile = home.appendingPathComponent(".dsh/profiles/desktop")
        let manifestURL = profile.appendingPathComponent("package.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return .waitingForProfile }
        let manifest = try json(manifestURL)
        let dependency = (manifest["dependencies"] as? [String: Any])?["@aisland/deepseek-harness-plugin"] as? String
        let resource = packagesDirectory.appendingPathComponent("DeepSeek")
        let files = ["package.json", "index.mjs", "core.mjs", "client.js", "cordis.patch.yml"]
        let bytes = try files.map { try regular(resource.appendingPathComponent($0)) }
        let hashes = zip(files, bytes).reduce(into: [String: String]()) { $0[$1.0] = digest($1.1) }
        let destination = supportDirectory.appendingPathComponent("deepseek-passive/package")
        let receiptURL = destination.deletingLastPathComponent().appendingPathComponent("receipt.json")
        if let dependency {
            guard dependency.hasPrefix("link:/") || dependency.hasPrefix("file:/") else { throw Failure.unownedInstallation }
            let previous = URL(fileURLWithPath: String(dependency.dropFirst(5)))
            // Existing linked plugin must be byte-identical to reviewed source;
            // sharing an npm name alone is never an ownership proof.
            if previous != destination {
                for name in files { guard digest(try regular(previous.appendingPathComponent(name))) == hashes[name] else { throw Failure.unownedInstallation } }
            }
        }
        var ownedCurrent = false
        if FileManager.default.fileExists(atPath: destination.path) {
            let inventory = try FileManager.default.contentsOfDirectory(atPath: destination.path)
            guard Set(inventory) == Set(files) else { throw Failure.unownedInstallation }
            let receipt = try json(receiptURL)
            guard receipt["owner"] as? String == "aisland.deepseek-passive", let previous = receipt["hashes"] as? [String: String], Set(previous.keys) == Set(files) else { throw Failure.unownedInstallation }
            for name in files { guard digest(try regular(destination.appendingPathComponent(name))) == previous[name] else { throw Failure.unownedInstallation } }
            ownedCurrent = previous == hashes
        }
        if ownedCurrent, dependency == "link:" + destination.path || dependency == "file:" + destination.path {
            let result = try deepSeekPatch(evidence: evidence, profile: profile, mode: "status")
            if result["isCurrent"] as? Bool == true { return .waitingForActivation }
        }
        if sourceRunning { return .waitingForSourceExit }
        let backup = try backupDirectory("deepseek")
        for name in ["package.json", "cordis.patch.yml", "pnpm-lock.yaml", "pnpm-workspace.yaml"] {
            let path = profile.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: path.path) {
                _ = try regular(path, maximum: 8 * 1024 * 1024)
                try FileManager.default.copyItem(at: path, to: backup.appendingPathComponent(name))
            }
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.copyItem(at: destination, to: backup.appendingPathComponent("previous-owned-package"))
            try FileManager.default.copyItem(at: receiptURL, to: backup.appendingPathComponent("previous-owned-receipt.json"))
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for (name, data) in zip(files, bytes) { try data.write(to: destination.appendingPathComponent(name), options: .atomic) }
        try JSONSerialization.data(withJSONObject: ["owner": "aisland.deepseek-passive", "hashes": hashes], options: [.sortedKeys]).write(to: receiptURL, options: .atomic)
        let cli = app.appendingPathComponent("Contents/Resources/runtime/cli/bin/dsh")
        guard FileManager.default.isExecutableFile(atPath: cli.path) else { throw Failure.missingRuntime }
        _ = try regular(cli)
        _ = try runner(cli, ["plugin", "--profile", "desktop", "add", destination.path], environment)
        let patch = try deepSeekPatch(evidence: evidence, profile: profile, mode: "update")
        guard patch["isCurrent"] as? Bool == true else { throw Failure.invalidMetadata }
        let current = try json(manifestURL)
        guard (current["dependencies"] as? [String: Any])?["@aisland/deepseek-harness-plugin"] as? String == "link:" + destination.path
            || (current["dependencies"] as? [String: Any])?["@aisland/deepseek-harness-plugin"] as? String == "file:" + destination.path else { throw Failure.invalidMetadata }
        return .waitingForActivation
    }
    private func deepSeekPatch(evidence: AgentInstallationDetector.Evidence, profile: URL, mode: String) throws -> [String: Any] {
        guard let app = evidence.bundleURL else { throw Failure.invalidMetadata }
        let helper = packagesDirectory.appendingPathComponent("DeepSeek/scripts/connection-patch.cjs")
        _ = try regular(helper)
        let anchor = app.appendingPathComponent("Contents/Resources/app.asar/dsh/node_modules/@deepseek-ai/dsh-plugin-manager/package.json")
        var env = environment; env["ELECTRON_RUN_AS_NODE"] = "1"
        let navigation = bridgeSocketURL.deletingLastPathComponent().appendingPathComponent("deepseek-navigation.sock")
        return try jsonData(runner(evidence.executableURL, ["--expose-internals", helper.path, anchor.path,
            profile.appendingPathComponent("cordis.patch.yml").path, bridgeSocketURL.path, navigation.path, mode], env))
    }
    private func backupDirectory(_ name: String) throws -> URL {
        let value = supportDirectory.appendingPathComponent("connection-backups/\(name)-\(UUID())")
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return value
    }
    private func directory(_ url: URL) throws {
        guard (try FileManager.default.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType == .typeDirectory else { throw Failure.invalidMetadata }
    }
    private func regular(_ url: URL, maximum: Int = 1_048_576) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular, let size = attributes[.size] as? NSNumber,
              size.intValue >= 0, size.intValue <= maximum else { throw Failure.unownedInstallation }
        return try Data(contentsOf: url)
    }
    private func json(_ url: URL) throws -> [String: Any] { try jsonData(regular(url)) }
    private func jsonData(_ data: Data) throws -> [String: Any] {
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.invalidMetadata }
        return result
    }
    private func jsonString(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]), as: UTF8.self)
    }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
