import Foundation
import Darwin

/// A delivery override only for a dedicated, locally signed full-app fixture.
/// Environment variables and ordinary/production bundle metadata cannot opt in.
struct UpdaterFixtureConfiguration: Sendable, Equatable {
    enum InvalidFixture: Error { case metadata, location, origin }
    let rootURL: URL
    let origin: URL
    let bundleIdentifier: String
    static func current(bundle: Bundle = .main) throws -> Self? {
        try Self(infoDictionary: bundle.infoDictionary ?? [:], bundleURL: bundle.bundleURL,
                 bundleIdentifier: bundle.bundleIdentifier)
    }
    init?(infoDictionary info: [String: Any], bundleURL: URL, bundleIdentifier: String?) throws {
        guard info["AIslandUpdaterFixture"] != nil else { return nil }
        func trueBoolean(_ key: String) -> Bool {
            guard let value = info[key] as? NSNumber else { return false }
            return CFGetTypeID(value) == CFBooleanGetTypeID() && value.boolValue
        }
        guard trueBoolean("AIslandUpdaterFixture"), trueBoolean("OpenIslandRuntimeAcceptance"), trueBoolean("AIslandUpdaterFixtureSupported"),
              let root = info["AIslandUpdaterFixtureRoot"] as? String,
              let endpoint = info["AIslandUpdaterFixtureOrigin"] as? String,
              let bundleIdentifier,
              ["0.1.1", "0.1.2"].contains(info["CFBundleShortVersionString"] as? String ?? ""),
              UpdateInstallationConfiguration.isReady(info) else { throw InvalidFixture.metadata }
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        let name = rootURL.lastPathComponent
        let prefix = "aisland-updater-app-fixture-"
        guard root.hasPrefix("/private/tmp/"), rootURL.deletingLastPathComponent().path == "/private/tmp",
              name.hasPrefix(prefix), name.dropFirst(prefix.count).range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil,
              bundleIdentifier == "dev.aisland.v011.acceptance.upd-" + name.suffix(16),
              Self.canonicalPath(rootURL) == rootURL.path,
              Self.canonicalPath(bundleURL) == rootURL.appendingPathComponent("installed/AIsland.app").path else {
            throw InvalidFixture.location
        }
        guard let components = URLComponents(string: endpoint), components.scheme == "http",
              components.host == "127.0.0.1", let port = components.port, (1024...65535).contains(port),
              components.path.isEmpty, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil, let origin = components.url,
              origin.absoluteString == endpoint else { throw InvalidFixture.origin }
        self.rootURL = rootURL; self.origin = origin; self.bundleIdentifier = bundleIdentifier
    }
    private static func canonicalPath(_ url: URL) -> String? {
        // Foundation rewrites /private/tmp to /tmp even after symlink resolution;
        // realpath supplies the actual filesystem spelling used by admission.
        guard let path = url.path.withCString({ realpath($0, nil) }) else { return nil }
        defer { free(path) }
        return String(cString: path)
    }
    func accepts(_ url: URL, releaseTag: String) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              url.scheme == origin.scheme, url.host == origin.host, url.port == origin.port,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else { return false }
        return url.path.hasPrefix("/SeanLiew523/aisland/releases/download/\(releaseTag)/")
    }
    var latestURL: URL { origin.appendingPathComponent("latest.json") }
    /// Receipts contain fixture callbacks only, never session or user content.
    func record(_ event: String, phase: String? = nil, bytes: UInt64? = nil, expected: UInt64? = nil) {
        var object: [String: Any] = ["event": event, "pid": ProcessInfo.processInfo.processIdentifier,
            "bundleID": bundleIdentifier, "time": Date().timeIntervalSince1970]
        object["phase"] = phase; object["bytes"] = bytes; object["expected"] = expected
        object["version"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        data.append(10)
        let url = rootURL.appendingPathComponent("updater-events.jsonl")
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }; _ = try? handle.seekToEnd(); try? handle.write(contentsOf: data)
        } else { try? data.write(to: url, options: [.atomic]) }
    }
}
