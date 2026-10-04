import Foundation
import Testing
@testable import OpenIslandApp

struct UpdaterFixtureConfigurationTests {
    func makeFixture() throws -> (URL, URL, [String: Any], String) {
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let root = URL(fileURLWithPath: "/private/tmp/aisland-updater-app-fixture-" + token)
        let app = root.appendingPathComponent("installed/AIsland.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let id = "dev.aisland.v011.acceptance.upd-" + token.suffix(16)
        let info: [String: Any] = ["AIslandUpdaterFixture": true, "OpenIslandRuntimeAcceptance": true,
            "AIslandUpdaterFixtureSupported": true, "AIslandUpdaterFixtureRoot": root.path,
            "AIslandUpdaterFixtureOrigin": "http://127.0.0.1:51234", "CFBundleShortVersionString": "0.1.1",
            "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString(),
            "AIslandUpdateSigningIdentity": "aisland-ed25519-v1", "SURequireSignedFeed": true,
            "SUVerifyUpdateBeforeExtraction": true, "OpenIslandDisableUpdates": false]
        return (root, app, info, id)
    }
    @Test func ordinaryBundleHasNoOverride() throws {
        #expect(try UpdaterFixtureConfiguration(infoDictionary: [:], bundleURL: URL(fileURLWithPath: "/Applications/AIsland.app"), bundleIdentifier: "dev.aisland.app") == nil)
    }
    @Test func onlyDedicatedLocationBothMarkersAndStrongTrustAreAdmitted() throws {
        let (root, app, info, id) = try makeFixture(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(try UpdaterFixtureConfiguration(infoDictionary: info, bundleURL: app, bundleIdentifier: id) != nil)
        var next = info; next["CFBundleShortVersionString"] = "0.1.2"
        #expect(try UpdaterFixtureConfiguration(infoDictionary: next, bundleURL: app, bundleIdentifier: id) != nil)
        for (key, value) in [("OpenIslandRuntimeAcceptance", false as Any), ("AIslandUpdaterFixtureSupported", false),
                             ("SURequireSignedFeed", false), ("SUVerifyUpdateBeforeExtraction", false),
                             ("SUPublicEDKey", UpdateInstallationConfiguration.legacyPublicKey),
                             ("CFBundleShortVersionString", "0.1.3")] {
            var changed = info; changed[key] = value
            #expect(throws: UpdaterFixtureConfiguration.InvalidFixture.self) {
                try UpdaterFixtureConfiguration(infoDictionary: changed, bundleURL: app, bundleIdentifier: id)
            }
        }
        #expect(throws: UpdaterFixtureConfiguration.InvalidFixture.self) {
            try UpdaterFixtureConfiguration(infoDictionary: info, bundleURL: URL(fileURLWithPath: "/Applications/AIsland.app"), bundleIdentifier: id)
        }
        #expect(throws: UpdaterFixtureConfiguration.InvalidFixture.self) {
            try UpdaterFixtureConfiguration(infoDictionary: info, bundleURL: app, bundleIdentifier: "dev.aisland.app")
        }
    }
    @Test func originAndReleaseAssetRemainExact() throws {
        let (root, app, info, id) = try makeFixture(); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try #require(try UpdaterFixtureConfiguration(infoDictionary: info, bundleURL: app, bundleIdentifier: id))
        let good = "http://127.0.0.1:51234/SeanLiew523/aisland/releases/download/v0.1.2/AIsland.zip"
        #expect(fixture.accepts(URL(string: good)!, releaseTag: "v0.1.2"))
        for value in [good + "?secret=1", good + "#fragment", good.replacingOccurrences(of: "51234", with: "51235"), good.replacingOccurrences(of: "127.0.0.1", with: "localhost"), good.replacingOccurrences(of: "v0.1.2", with: "v0.1.3")] {
            #expect(!fixture.accepts(URL(string: value)!, releaseTag: "v0.1.2"))
        }
        for endpoint in ["http://localhost:51234", "http://user@127.0.0.1:51234", "http://127.0.0.1:80", "http://127.0.0.1:51234/", "http://127.0.0.1:51234?test=1", "https://example.com:51234"] {
            var changed = info; changed["AIslandUpdaterFixtureOrigin"] = endpoint
            #expect(throws: UpdaterFixtureConfiguration.InvalidFixture.self) {
                try UpdaterFixtureConfiguration(infoDictionary: changed, bundleURL: app, bundleIdentifier: id)
            }
        }
    }
    @Test func remoteJSONCannotEnableFixtureAssetPolicy() throws {
        let data = Data("""
        {"tag_name":"v0.1.2","draft":false,"prerelease":false,"html_url":"https://github.com/SeanLiew523/aisland/releases/tag/v0.1.2","fixture":{"origin":"http://127.0.0.1:51234"},"assets":[{"name":"appcast.xml","size":10,"state":"uploaded","browser_download_url":"http://127.0.0.1:51234/SeanLiew523/aisland/releases/download/v0.1.2/appcast.xml"}]}
        """.utf8)
        let release = try JSONDecoder().decode(GitHubUpdateRelease.self, from: data)
        try release.validate(); #expect(release.fixture == nil); #expect(release.feedURL == nil)
    }
    @Test func localMetadataIsDeliveredOnlyByValidatedFixtureClient() async throws {
        let (root, app, info, id) = try makeFixture(); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try #require(try UpdaterFixtureConfiguration(infoDictionary: info, bundleURL: app, bundleIdentifier: id))
        let payload = Data("""
        {"tag_name":"v0.1.2","draft":false,"prerelease":false,"html_url":"https://github.com/SeanLiew523/aisland/releases/tag/v0.1.2","assets":[{"name":"appcast.xml","size":10,"state":"uploaded","browser_download_url":"http://127.0.0.1:51234/SeanLiew523/aisland/releases/download/v0.1.2/appcast.xml"}]}
        """.utf8)
        let client = GitHubUpdateClient(fixture: fixture) { request in
            #expect(request.url == fixture.latestURL)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            return (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let candidate = try await client.latestRelease()
        #expect(candidate.fixture == fixture); #expect(candidate.feedURL?.host == "127.0.0.1")
        let redirect = GitHubUpdateClient(fixture: fixture) { _ in
            (payload, HTTPURLResponse(url: URL(string: "https://example.com/latest.json")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        await #expect(throws: GitHubUpdateError.self) { try await redirect.latestRelease() }
    }
}
