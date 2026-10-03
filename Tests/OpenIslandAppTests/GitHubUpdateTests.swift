import Foundation
import Sparkle
import Testing
@testable import OpenIslandApp

struct GitHubUpdateTests {
    func release(version: String = "v0.1.1", prerelease: Bool = false) -> GitHubUpdateRelease {
        let base = "https://github.com/SeanLiew523/aisland/releases/"
        return GitHubUpdateRelease(tagName: version, draft: false, prerelease: prerelease,
            htmlURL: URL(string: base + "tag/" + version)!, assets: [
                .init(name: "appcast.xml", size: 10, state: "uploaded", browserDownloadURL: URL(string: base + "download/" + version + "/appcast.xml")!),
                .init(name: "AIsland.zip", size: 100, state: "uploaded", browserDownloadURL: URL(string: base + "download/" + version + "/AIsland.zip")!)])
    }
    @Test func numericVersionsDoNotMisorderStableTags() {
        #expect(UpdateVersion("0.1.10")! > UpdateVersion("0.1.9")!)
        #expect(UpdateVersion("0.1.1") == UpdateVersion("0.1.1.0"))
        for invalid in ["0.1.1-beta", "0..1", "", "１.２", "0.1.18446744073709551616"] { #expect(UpdateVersion(invalid) == nil) }
    }
    @Test func onlyExactStableReleaseAssetsAreAdmitted() throws {
        let r = release()
        try r.validate()
        #expect(throws: GitHubUpdateError.self) { try release(prerelease: true).validate() }
        #expect(throws: GitHubUpdateError.self) { try release(version: "v0.1.1-beta").validate() }
        #expect(r.feedURL?.lastPathComponent == "appcast.xml")
        #expect(r.archive(matching: r.assets[1].browserDownloadURL, length: 100) != nil)
        #expect(r.archive(matching: r.assets[1].browserDownloadURL, length: 99) == nil)
        #expect(r.archive(matching: URL(string: "https://github.com/other/project/releases/download/v0.1.1/AIsland.zip")!, length: 100) == nil)
        #expect(!r.accepts(.init(name: "AIsland.zip", size: 100, state: "uploaded", browserDownloadURL: URL(string: "http://github.com/SeanLiew523/aisland/releases/download/v0.1.1/AIsland.zip")!)))
    }
    @Test func oldOrIncompleteTrustConfigurationCannotEnableInstallation() {
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        let ready: [String: Any] = ["SUPublicEDKey": key, "AIslandUpdateSigningIdentity": "aisland-ed25519-v1", "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true, "OpenIslandDisableUpdates": false]
        #expect(UpdateInstallationConfiguration.isReady(ready))
        for (field, value) in [("SUPublicEDKey", UpdateInstallationConfiguration.legacyPublicKey as Any), ("SUPublicEDKey", "invalid"), ("OpenIslandDisableUpdates", true), ("SURequireSignedFeed", false), ("SUVerifyUpdateBeforeExtraction", false)] {
            var changed = ready; changed[field] = value
            #expect(!UpdateInstallationConfiguration.isReady(changed))
        }
        #expect(!UpdateInstallationConfiguration.isReady([:]))
    }
    @Test func publicGitHubRequestAndRateLimitAreHandled() async throws {
        let client = GitHubUpdateClient { request in
            #expect(request.url?.absoluteString == "https://api.github.com/repos/SeanLiew523/aisland/releases/latest")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!)
        }
        do { _ = try await client.latestRelease(); Issue.record("Expected rate limit") }
        catch let error as GitHubUpdateError { #expect(error.messageKey == "settings.update.rateLimited") }
    }
    @MainActor @Test func progressDoesNotClaimInstallationAndCancellationClearsCallbacks() {
        let checker = UpdateChecker()
        var cancelled = 0
        checker.showDownloadInitiated { cancelled += 1 }
        #expect(checker.downloadProgress == nil)
        checker.showDownloadDidReceiveExpectedContentLength(100)
        checker.showDownloadDidReceiveData(ofLength: 40)
        #expect(checker.downloadProgress == 0.4)
        checker.showDownloadDidReceiveData(ofLength: 80)
        #expect(checker.downloadProgress == 1)
        #expect(checker.phase == .downloading)
        checker.cancel(); checker.cancel()
        #expect(cancelled == 1)
        #expect(checker.phase == .idle)
    }
    @MainActor @Test func noConsentDoesNotAutomaticallyRelaunchARecoveredUpdate() {
        let checker = UpdateChecker()
        var choices: [SPUUserUpdateChoice] = []
        checker.showReady(toInstallAndRelaunch: { choices.append($0) })
        #expect(choices.isEmpty)
        #expect(checker.hasUpdate)
        checker.downloadAndInstall()
        #expect(choices == [.install])
        checker.showReady(toInstallAndRelaunch: { choices.append($0) })
        #expect(choices == [.install, .install])
        checker.showInstallingUpdate(withApplicationTerminated: false, retryTerminatingApplication: {})
        #expect(checker.phase == .installing)
        checker.showUpdaterError(NSError(domain: "fixture", code: 1), acknowledgement: {})
        #expect(checker.phase == .failed)
        checker.dismissUpdateInstallation()
        #expect(checker.phase == .failed)
    }
    @MainActor @Test func disabledBundleStillChecksGitHubButCannotOfferInstallation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aisland-update-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("Fixture.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "dev.aisland.updater.unittest", "CFBundleVersion": "1", "CFBundleShortVersionString": "0.1.0", "OpenIslandDisableUpdates": true]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let bundle = try #require(Bundle(path: root.appendingPathComponent("Fixture.app").path))
        let payload = Data("""
        {"tag_name":"v0.1.1","draft":false,"prerelease":false,"html_url":"https://github.com/SeanLiew523/aisland/releases/tag/v0.1.1","assets":[]}
        """.utf8)
        let client = GitHubUpdateClient { request in
            (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let checker = UpdateChecker(client: client, bundle: bundle)
        checker.checkForUpdates()
        for _ in 0..<100 where checker.phase == .checking { try await Task.sleep(for: .milliseconds(10)) }
        #expect(checker.phase == .blocked)
        #expect(checker.latestVersion == "0.1.1")
        #expect(checker.messageKey == "settings.update.signingNotConfigured")
        #expect(!checker.hasUpdate)
        #expect(checker.canCheckForUpdates)
        #expect(!checker.canCancel)
    }

}
