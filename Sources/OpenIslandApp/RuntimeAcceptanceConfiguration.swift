import Darwin
import Foundation
import CryptoKit
import OpenIslandCore

/// An explicit, signed-bundle opt-in. Environment variables never enable this
/// mode, redirect its paths or choose the welcome language.
struct RuntimeAcceptanceConfiguration: Sendable {
    static let bundlePrefix = "dev.aisland.v011.acceptance."
    static let approvedV6Commit = "32c94f2fb0282242d17ef4db63f6c169a874e25f"

    enum ConfigurationError: Error { case invalidMetadata, unsafePath, preferencesUnavailable, receiptWriteFailed }
    enum WelcomeEvent: String, Codable { case claimed, shown, exited }
    enum WelcomeExit: String, Codable { case completed, skipped, closed, termination }
    struct WelcomeReceipt: Codable, Equatable {
        let event: WelcomeEvent
        let exit: WelcomeExit?
        let language: String
        let bundleIdentifier: String
        let sourceCommit: String
        let approvedV6Commit: String
        let alreadyPresented: Bool
        let firstLaunchCompleted: Bool
        let preferredLanguages: [String]
    }

    let bundleIdentifier: String
    let caseName: String
    let sourceCommit: String
    let buildNumber: Int
    let socketURL: URL
    let runtimeLifecycleRegistryURL: URL
    let receiptURL: URL
    let sourceSetup: SourceSetup?
    var skipsRuntimeDiscovery: Bool { true }
    var skipsHookStatusReadsAndInstallation: Bool { sourceSetup == nil }

    /// This intentionally bounded acceptance case uses the production detector
    /// and installer path, but only the explicitly listed sources.
    struct SourceSetup: Sendable {
        let agents: Set<AgentIdentifier>
        let supportURL: URL
        let bundleURL: URL
        let socketURL: URL
        var hooksBinaryURL: URL { supportURL.appendingPathComponent("bin/OpenIslandHooks") }
        var bundledHooksURL: URL { bundleURL.appendingPathComponent("Contents/Helpers/OpenIslandHooks") }

        enum ConnectionState: String, Codable { case absent, installed, configured, waitingForConsent, waitingForProfile, waitingForSourceExit, waitingForActivation, eventReceived, cancelled, error }
        func record(agent: AgentIdentifier, state: ConnectionState) throws {
            guard agents.contains(agent), try RuntimeAcceptanceConfiguration.canonical(supportURL).path == supportURL.path else { throw ConfigurationError.unsafePath }
            try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var data = try JSONSerialization.data(withJSONObject: ["agent": agent.rawValue, "state": state.rawValue, "timestamp": Date().timeIntervalSince1970], options: [.sortedKeys]); data.append(10)
            let fd = open(supportURL.appendingPathComponent("source-setup-receipts.jsonl").path, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw ConfigurationError.receiptWriteFailed }
            defer { close(fd) }
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw ConfigurationError.receiptWriteFailed }; offset += count
                }
            }
            guard fsync(fd) == 0 else { throw ConfigurationError.receiptWriteFailed }
        }

        func backupHermesConfiguration(profileURL: URL) throws {
            guard try RuntimeAcceptanceConfiguration.canonical(supportURL).path == supportURL.path else { throw ConfigurationError.unsafePath }
            let directory = supportURL.appendingPathComponent("connection-backups/hermes-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for name in ["config.yaml", "aisland-hooks.json"] {
                let source = profileURL.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      let count = attributes[.size] as? NSNumber, count.intValue <= 8 * 1024 * 1024 else { throw ConfigurationError.unsafePath }
                try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name))
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: directory.appendingPathComponent(name).path)
            }
        }

        /// Own callback entry point, not a task launcher. Existing source or
        /// production wrapper files are never rewritten by this operation.
        func prepareHooksWrapper() throws -> URL {
            guard try RuntimeAcceptanceConfiguration.canonical(supportURL).path == supportURL.path,
                  try RuntimeAcceptanceConfiguration.canonical(bundledHooksURL).path == bundledHooksURL.path,
                  (try FileManager.default.attributesOfItem(atPath: bundledHooksURL.path)[.type]) as? FileAttributeType == .typeRegular,
                  FileManager.default.isExecutableFile(atPath: bundledHooksURL.path) else { throw ConfigurationError.unsafePath }
            func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
            let bytes = Data(("#!/bin/sh\n# AIsland isolated source-setup callback; owned by this case.\n" +
                "export OPEN_ISLAND_SOCKET_PATH=" + quote(socketURL.path) + "\nexec " + quote(bundledHooksURL.path) + " \"$@\"\n").utf8)
            let directory = hooksBinaryURL.deletingLastPathComponent()
            guard try RuntimeAcceptanceConfiguration.canonical(directory).path == directory.path else { throw ConfigurationError.unsafePath }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let receipt = directory.appendingPathComponent("source-setup-wrapper.json")
            let proof = try JSONSerialization.data(withJSONObject: ["owner": "aisland.source-setup.acceptance", "wrapperSHA256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), "bundle": bundleURL.path], options: [.sortedKeys])
            if FileManager.default.fileExists(atPath: hooksBinaryURL.path) || FileManager.default.fileExists(atPath: receipt.path) {
                guard (try FileManager.default.attributesOfItem(atPath: hooksBinaryURL.path)[.type]) as? FileAttributeType == .typeRegular,
                      (try FileManager.default.attributesOfItem(atPath: receipt.path)[.type]) as? FileAttributeType == .typeRegular,
                      try Data(contentsOf: hooksBinaryURL) == bytes, try Data(contentsOf: receipt) == proof else { throw ConfigurationError.unsafePath }
            } else {
                // Exclusive creation rejects a foreign file or racing writer.
                try Self.writeExclusive(bytes, to: hooksBinaryURL, mode: 0o700)
                try Self.writeExclusive(proof, to: receipt, mode: 0o600)
            }
            guard FileManager.default.isExecutableFile(atPath: hooksBinaryURL.path) else { throw ConfigurationError.unsafePath }
            return hooksBinaryURL
        }
        private static func writeExclusive(_ data: Data, to url: URL, mode: mode_t) throws {
            let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode)
            guard fd >= 0 else { throw ConfigurationError.unsafePath }
            defer { close(fd) }
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw ConfigurationError.receiptWriteFailed }
                    offset += count
                }
            }
            guard fsync(fd) == 0 else { throw ConfigurationError.receiptWriteFailed }
        }
    }

    /// Nil means an ordinary bundle. A malformed opted-in acceptance bundle
    /// throws; callers must stop startup, never fall back to production IO.
    static func current(bundle: Bundle = .main) throws -> Self? {
        let fixture = try UpdaterFixtureConfiguration.current(bundle: bundle)
        return try Self(infoDictionary: bundle.infoDictionary ?? [:], bundleIdentifier: bundle.bundleIdentifier,
            bundleURL: bundle.bundleURL, updaterFixture: fixture)
    }

    init?(infoDictionary: [String: Any], bundleIdentifier: String?, bundleURL: URL? = nil, updaterFixture: UpdaterFixtureConfiguration? = nil) throws {
        guard let marker = infoDictionary["OpenIslandRuntimeAcceptance"] as? NSNumber,
              CFGetTypeID(marker) == CFBooleanGetTypeID(), marker.boolValue,
              let bundleIdentifier, bundleIdentifier.hasPrefix(Self.bundlePrefix) else {
            if infoDictionary["AIslandSourceSetupAcceptance"] != nil { throw ConfigurationError.invalidMetadata }
            return nil
        }
        let caseName = String(bundleIdentifier.dropFirst(Self.bundlePrefix.count))
        guard Self.isValidCase(caseName),
              (infoDictionary["CFBundleShortVersionString"] as? String == "0.1.1"
                || (updaterFixture != nil && infoDictionary["CFBundleShortVersionString"] as? String == "0.1.2")),
              let version = infoDictionary["CFBundleVersion"] as? String,
              let buildNumber = Int(version), buildNumber >= 6,
              let commit = infoDictionary["AIslandSourceCommit"] as? String,
              commit.range(of: "^[0-9a-f]{40}$",options: .regularExpression) != nil,
              infoDictionary["AIslandApprovedV6Commit"] as? String == Self.approvedV6Commit,
              let socket = infoDictionary["OpenIslandAcceptanceSocketPath"] as? String,
              let registry = infoDictionary["OpenIslandAcceptanceRegistryPath"] as? String else {
            throw ConfigurationError.invalidMetadata
        }
        if infoDictionary["AIslandUpdaterFixture"] != nil {
            guard let updaterFixture, updaterFixture.bundleIdentifier == bundleIdentifier, let bundleURL,
                  try Self.canonical(bundleURL).path == updaterFixture.rootURL.appendingPathComponent("installed/AIsland.app").path,
                  infoDictionary["AIslandSourceSetupAcceptance"] == nil else { throw ConfigurationError.invalidMetadata }
        } else if updaterFixture != nil { throw ConfigurationError.invalidMetadata }
        let directory = Self.directoryURL(for: caseName)
        let socketURL = URL(fileURLWithPath: socket)
        let registryURL = URL(fileURLWithPath: registry)
        guard socket.hasPrefix("/"), registry.hasPrefix("/"),
              try Self.canonical(socketURL).path == directory.appendingPathComponent("bridge.sock").path,
              try Self.canonical(registryURL).path == directory.appendingPathComponent("runtime-lifecycle.json").path,
              socketURL.path.utf8.count < 104 else { throw ConfigurationError.unsafePath }
        let sourceSetup: SourceSetup?
        if let value = infoDictionary["AIslandSourceSetupAcceptance"] {
            guard let marker = value as? NSNumber, CFGetTypeID(marker) == CFBooleanGetTypeID(), marker.boolValue,
                  (caseName.hasPrefix("setup-") || caseName == "runtime-live"), let bundleURL,
                  try Self.canonical(bundleURL).path == directory.appendingPathComponent("app/AIsland.app").path,
                  let names = infoDictionary["AIslandSourceSetupAgents"] as? [String], !names.isEmpty,
                  Set(names).count == names.count,
                  let support = infoDictionary["AIslandSourceSetupSupportPath"] as? String,
                  support.hasPrefix("/"), try Self.canonical(URL(fileURLWithPath: support)).path == directory.appendingPathComponent("support").path else { throw ConfigurationError.unsafePath }
            let allowed: Set<AgentIdentifier> = [.hermes, .deepSeekDesktop, .miniMaxCodeDesktop, .ohMyPi]
            let agents = Set(names.compactMap(AgentIdentifier.init(rawValue:)))
            guard agents.count == names.count, agents.isSubset(of: allowed) else { throw ConfigurationError.invalidMetadata }
            sourceSetup = SourceSetup(agents: agents, supportURL: directory.appendingPathComponent("support"),
                bundleURL: try Self.canonical(bundleURL), socketURL: try Self.canonical(socketURL))
        } else { sourceSetup = nil }
        self.sourceSetup = sourceSetup
        self.bundleIdentifier = bundleIdentifier; self.caseName = caseName
        self.sourceCommit = commit; self.buildNumber = buildNumber
        self.socketURL = try Self.canonical(socketURL)
        self.runtimeLifecycleRegistryURL = try Self.canonical(registryURL)
        self.receiptURL = directory.appendingPathComponent("welcome-receipts.jsonl")
    }

    func isolatedPreferences() throws -> UserDefaults {
        // Foundation rejects suiteName == the running app's own identifier.
        // In that validated acceptance bundle, .standard already belongs to
        // its distinct case domain, never to dev.aisland.app. External probes
        // and isolated tests still need an explicit suite for this case.
        if Bundle.main.bundleIdentifier == bundleIdentifier { return .standard }
        guard let defaults = UserDefaults(suiteName: bundleIdentifier) else {
            throw ConfigurationError.preferencesUnavailable
        }
        return defaults
    }

    /// Narrow receipt API deliberately has no payload/message/session fields.
    /// The caller uses Locale.preferredLanguages and the ordinary language
    /// resolver, then passes its concrete result; this API never forces locale.
    func recordWelcome(event: WelcomeEvent, exit: WelcomeExit? = nil, language: String,
                       alreadyPresented: Bool, firstLaunchCompleted: Bool,
                       preferredLanguages: [String] = Locale.preferredLanguages) throws {
        guard ["en","zh","zh-Hans","zh-Hant"].contains(language),
              (event == .exited) == (exit != nil),
              preferredLanguages.allSatisfy({ $0.count <= 128 && $0.range(of: "^[A-Za-z0-9_-]+$",options: .regularExpression) != nil }) else {
            throw ConfigurationError.invalidMetadata
        }
        let receipt = WelcomeReceipt(event: event,exit: exit,language: language,
            bundleIdentifier: bundleIdentifier,sourceCommit: sourceCommit,approvedV6Commit: Self.approvedV6Commit,
            alreadyPresented: alreadyPresented,firstLaunchCompleted: firstLaunchCompleted,
            preferredLanguages: preferredLanguages)
        let directory = Self.directoryURL(for: caseName)
        guard try Self.canonical(directory).path == directory.path else { throw ConfigurationError.unsafePath }
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        guard try Self.canonical(receiptURL).path == directory.appendingPathComponent("welcome-receipts.jsonl").path else {
            throw ConfigurationError.unsafePath
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(receipt); data.append(0x0a)
        let fd = open(receiptURL.path,O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW,0o600)
        guard fd >= 0 else { throw ConfigurationError.receiptWriteFailed }
        defer { close(fd) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd,buffer.baseAddress!.advanced(by: offset),buffer.count-offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw ConfigurationError.receiptWriteFailed }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw ConfigurationError.receiptWriteFailed }
    }

    private static func isValidCase(_ value: String) -> Bool {
        value.range(of: "^[a-z0-9][a-z0-9-]{0,31}$",options: .regularExpression) != nil
    }
    private static func canonical(_ url: URL) throws -> URL {
        // Foundation may preserve unresolved tail components or abbreviate
        // /private/tmp differently for existing/missing files. Resolve the
        // nearest existing ancestor with POSIX realpath, then append the tail.
        var ancestor = url.standardizedFileURL
        var tail: [String] = []
        while (try? FileManager.default.attributesOfItem(atPath: ancestor.path)) == nil {
            let parent = ancestor.deletingLastPathComponent()
            guard parent.path != ancestor.path else { throw ConfigurationError.unsafePath }
            tail.insert(ancestor.lastPathComponent,at: 0); ancestor = parent
        }
        guard let resolved = realpath(ancestor.path,nil) else { throw ConfigurationError.unsafePath }
        defer { free(resolved) }
        var result = URL(fileURLWithPath: String(cString: resolved))
        for component in tail { result.appendPathComponent(component) }
        return result
    }
    private static func directoryURL(for caseName: String) -> URL {
        // Fixed dedicated tree; production ~/Library/Application Support/OpenIsland
        // and /tmp/open-island-<uid>.sock cannot pass this admission.
        URL(fileURLWithPath: "/private/tmp/aisland-v011-acceptance",isDirectory: true)
            .appendingPathComponent(caseName,isDirectory: true)
    }
}
