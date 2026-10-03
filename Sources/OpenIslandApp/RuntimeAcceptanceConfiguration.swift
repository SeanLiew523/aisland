import Darwin
import Foundation

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
    var skipsRuntimeDiscovery: Bool { true }
    var skipsHookStatusReadsAndInstallation: Bool { true }

    /// Nil means an ordinary bundle. A malformed opted-in acceptance bundle
    /// throws; callers must stop startup, never fall back to production IO.
    static func current(bundle: Bundle = .main) throws -> Self? {
        try Self(infoDictionary: bundle.infoDictionary ?? [:],bundleIdentifier: bundle.bundleIdentifier)
    }

    init?(infoDictionary: [String: Any], bundleIdentifier: String?) throws {
        guard let marker = infoDictionary["OpenIslandRuntimeAcceptance"] as? NSNumber,
              CFGetTypeID(marker) == CFBooleanGetTypeID(), marker.boolValue,
              let bundleIdentifier, bundleIdentifier.hasPrefix(Self.bundlePrefix) else { return nil }
        let caseName = String(bundleIdentifier.dropFirst(Self.bundlePrefix.count))
        guard Self.isValidCase(caseName),
              infoDictionary["CFBundleShortVersionString"] as? String == "0.1.1",
              let version = infoDictionary["CFBundleVersion"] as? String,
              let buildNumber = Int(version), buildNumber >= 6,
              let commit = infoDictionary["AIslandSourceCommit"] as? String,
              commit.range(of: "^[0-9a-f]{40}$",options: .regularExpression) != nil,
              infoDictionary["AIslandApprovedV6Commit"] as? String == Self.approvedV6Commit,
              let socket = infoDictionary["OpenIslandAcceptanceSocketPath"] as? String,
              let registry = infoDictionary["OpenIslandAcceptanceRegistryPath"] as? String else {
            throw ConfigurationError.invalidMetadata
        }
        let directory = Self.directoryURL(for: caseName)
        let socketURL = URL(fileURLWithPath: socket)
        let registryURL = URL(fileURLWithPath: registry)
        guard socket.hasPrefix("/"), registry.hasPrefix("/"),
              try Self.canonical(socketURL).path == directory.appendingPathComponent("bridge.sock").path,
              try Self.canonical(registryURL).path == directory.appendingPathComponent("runtime-lifecycle.json").path,
              socketURL.path.utf8.count < 104 else { throw ConfigurationError.unsafePath }
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
