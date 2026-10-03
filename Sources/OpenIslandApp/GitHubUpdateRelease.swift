import Foundation

/// GitHub describes the stable release; Sparkle remains the only installer.
struct GitHubUpdateRelease: Decodable, Equatable, Sendable {
    struct Asset: Decodable, Equatable, Sendable {
        let name: String
        let size: UInt64
        let state: String
        let browserDownloadURL: URL
        enum CodingKeys: String, CodingKey {
            case name, size, state
            case browserDownloadURL = "browser_download_url"
        }
    }
    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let htmlURL: URL
    let assets: [Asset]
    enum CodingKeys: String, CodingKey {
        case draft, prerelease, assets
        case tagName = "tag_name", htmlURL = "html_url"
    }
    var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }
    var feedURL: URL? { assets.first { $0.name == "appcast.xml" && accepts($0) }?.browserDownloadURL }
    func accepts(_ asset: Asset) -> Bool {
        asset.state == "uploaded" && asset.size > 0 && asset.browserDownloadURL.scheme == "https"
            && asset.browserDownloadURL.host == "github.com"
            && asset.browserDownloadURL.path.hasPrefix("/SeanLiew523/aisland/releases/download/\(tagName)/")
            && asset.browserDownloadURL.query == nil && asset.browserDownloadURL.fragment == nil
    }
    func archive(matching url: URL, length: UInt64) -> Asset? {
        assets.first { accepts($0) && $0.browserDownloadURL == url && $0.size == length
            && ["zip", "dmg"].contains(url.pathExtension.lowercased()) }
    }
    func validate() throws {
        guard !draft, !prerelease, UpdateVersion(version) != nil,
              htmlURL.scheme == "https", htmlURL.host == "github.com",
              htmlURL.path == "/SeanLiew523/aisland/releases/tag/\(tagName)" else {
            throw GitHubUpdateError.invalidRelease
        }
    }
}

/// Stable numeric releases only; build ordering is separately enforced by Sparkle.
struct UpdateVersion: Comparable, Sendable {
    let components: [UInt64]
    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }) else { return nil }
        let numbers = parts.compactMap { UInt64($0) }
        guard numbers.count == parts.count else { return nil }
        components = numbers + Array(repeating: 0, count: 4 - numbers.count)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}

enum GitHubUpdateError: Error {
    case unavailable(Int), invalidRelease, invalidResponse
    var messageKey: String {
        switch self {
        case .unavailable(404): "settings.update.noRelease"
        case .unavailable(403), .unavailable(429): "settings.update.rateLimited"
        case .invalidRelease, .invalidResponse: "settings.update.invalidRelease"
        default: "settings.update.networkFailed"
        }
    }
}

struct GitHubUpdateClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    var transport: Transport = { try await URLSession.shared.data(for: $0) }
    func latestRelease() async throws -> GitHubUpdateRelease {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/SeanLiew523/aisland/releases/latest")!)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("AIsland-Updater", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport(request)
        guard let response = response as? HTTPURLResponse else { throw GitHubUpdateError.invalidResponse }
        guard response.statusCode == 200 else { throw GitHubUpdateError.unavailable(response.statusCode) }
        guard data.count <= 2_000_000, let release = try? JSONDecoder().decode(GitHubUpdateRelease.self, from: data) else {
            throw GitHubUpdateError.invalidRelease
        }
        try release.validate()
        return release
    }
}

struct UpdateInstallationConfiguration {
    // This belongs to the upstream product; it must never establish AIsland trust.
    static let legacyPublicKey = "3IF8txq9RRNanzE2FNhyGRcwhslTucCcJHpTkpxcgBQ="
    static func isReady(_ info: [String: Any]) -> Bool {
        guard info["OpenIslandDisableUpdates"] as? Bool != true,
              info["AIslandUpdateSigningIdentity"] as? String == "aisland-ed25519-v1",
              info["SURequireSignedFeed"] as? Bool == true,
              info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
              let key = info["SUPublicEDKey"] as? String, key != legacyPublicKey,
              Data(base64Encoded: key)?.count == 32 else { return false }
        return true
    }
}
