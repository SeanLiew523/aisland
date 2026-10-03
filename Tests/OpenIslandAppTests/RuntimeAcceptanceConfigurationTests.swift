import Foundation
import Testing
@testable import OpenIslandApp

struct RuntimeAcceptanceConfigurationTests {
    @Test func bothBundleOptInsAreRequired() throws {
        let value = metadata(caseName: "gate")
        #expect(try RuntimeAcceptanceConfiguration(infoDictionary: [:],bundleIdentifier: "dev.aisland.v011.acceptance.gate") == nil)
        #expect(try RuntimeAcceptanceConfiguration(infoDictionary: value,bundleIdentifier: "dev.aisland.app") == nil)
        #expect(try RuntimeAcceptanceConfiguration(infoDictionary: value,bundleIdentifier: "com.openisland.app") == nil)
        for marker: Any in ["true",1,false] {
            var info = value; info["OpenIslandRuntimeAcceptance"] = marker
            #expect(try RuntimeAcceptanceConfiguration(infoDictionary: info,bundleIdentifier: "dev.aisland.v011.acceptance.gate") == nil)
        }
    }

    @Test func enabledConfigurationOnlyUsesCaseScopedPathsAndPreferences() throws {
        let name = newCase()
        let config = try #require(try RuntimeAcceptanceConfiguration(infoDictionary: metadata(caseName: name),bundleIdentifier: "dev.aisland.v011.acceptance.\(name)"))
        #expect(config.socketURL.path == "/private/tmp/aisland-v011-acceptance/\(name)/bridge.sock")
        #expect(config.runtimeLifecycleRegistryURL.path == "/private/tmp/aisland-v011-acceptance/\(name)/runtime-lifecycle.json")
        #expect(config.skipsRuntimeDiscovery && config.skipsHookStatusReadsAndInstallation)
        let defaults = try config.isolatedPreferences()
        defer { defaults.removePersistentDomain(forName: config.bundleIdentifier) }
        defaults.set("system",forKey: "appLanguage")
        defaults.set(true,forKey: "onboardingPresentedV1")
        let reopened = try config.isolatedPreferences()
        #expect(reopened.string(forKey: "appLanguage") == "system")
        #expect(reopened.bool(forKey: "onboardingPresentedV1"))
    }

    @Test func productionLegacyRelativeAndRedirectedPathsAreRejected() throws {
        for socket in ["/tmp/open-island-501.sock",NSHomeDirectory()+"/Library/Application Support/OpenIsland/bridge.sock", "bridge.sock", "/tmp/other.sock"] {
            var info = metadata(caseName: "unsafe"); info["OpenIslandAcceptanceSocketPath"] = socket
            #expect(throws: RuntimeAcceptanceConfiguration.ConfigurationError.self) {
                try RuntimeAcceptanceConfiguration(infoDictionary: info,bundleIdentifier: "dev.aisland.v011.acceptance.unsafe")
            }
        }
        var info = metadata(caseName: "unsafe")
        info["OpenIslandAcceptanceRegistryPath"] = NSHomeDirectory()+"/Library/Application Support/OpenIsland/runtime-lifecycle.json"
        #expect(throws: RuntimeAcceptanceConfiguration.ConfigurationError.self) {
            try RuntimeAcceptanceConfiguration(infoDictionary: info,bundleIdentifier: "dev.aisland.v011.acceptance.unsafe")
        }
        let name = newCase(), directory = URL(fileURLWithPath: "/private/tmp/aisland-v011-acceptance/\(name)")
        try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(),withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: directory,withDestinationURL: URL(fileURLWithPath: "/private/tmp"))
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: RuntimeAcceptanceConfiguration.ConfigurationError.self) {
            try RuntimeAcceptanceConfiguration(infoDictionary: metadata(caseName: name),bundleIdentifier: "dev.aisland.v011.acceptance.\(name)")
        }
    }

    @Test func malformedAcceptanceMetadataThrowsRatherThanEnablingProductionFallback() {
        for (key,value): (String,Any) in [
            ("CFBundleVersion","5"), ("CFBundleShortVersionString","0.1.0"),
            ("AIslandSourceCommit","uncommitted"), ("AIslandApprovedV6Commit","old")
        ] {
            var info = metadata(caseName: "bad"); info[key] = value
            #expect(throws: RuntimeAcceptanceConfiguration.ConfigurationError.self) {
                try RuntimeAcceptanceConfiguration(infoDictionary: info,bundleIdentifier: "dev.aisland.v011.acceptance.bad")
            }
        }
        #expect(throws: RuntimeAcceptanceConfiguration.ConfigurationError.self) {
            try RuntimeAcceptanceConfiguration(infoDictionary: metadata(caseName: "bad"),bundleIdentifier: "dev.aisland.v011.acceptance.../other")
        }
    }

    @Test func receiptsAreLimitedToWelcomeFlagsAndRealPreferredLanguages() throws {
        let name = newCase()
        let config = try #require(try RuntimeAcceptanceConfiguration(infoDictionary: metadata(caseName: name),bundleIdentifier: "dev.aisland.v011.acceptance.\(name)"))
        defer { try? FileManager.default.removeItem(at: config.receiptURL.deletingLastPathComponent()) }
        try config.recordWelcome(event: .claimed,language: "zh",alreadyPresented: true,firstLaunchCompleted: false,preferredLanguages: ["zh-Hans-CN","en-US"])
        try config.recordWelcome(event: .shown,language: "zh",alreadyPresented: true,firstLaunchCompleted: false,preferredLanguages: ["zh-Hans-CN"])
        try config.recordWelcome(event: .exited,exit: .skipped,language: "zh",alreadyPresented: true,firstLaunchCompleted: true,preferredLanguages: ["zh-Hans-CN"])
        let lines = try String(contentsOf: config.receiptURL,encoding: .utf8).split(separator: "\n")
        let records = try lines.map { try JSONDecoder().decode(RuntimeAcceptanceConfiguration.WelcomeReceipt.self,from: Data($0.utf8)) }
        #expect(records.map(\.event) == [.claimed,.shown,.exited])
        #expect(records.last?.exit == .skipped)
        #expect(records.first?.preferredLanguages == ["zh-Hans-CN","en-US"])
        #expect(records.last?.firstLaunchCompleted == true)
        #expect(throws: RuntimeAcceptanceConfiguration.ConfigurationError.self) {
            try config.recordWelcome(event: .shown,language: "private task body",alreadyPresented: false,firstLaunchCompleted: false)
        }
        #expect(throws: RuntimeAcceptanceConfiguration.ConfigurationError.self) {
            try config.recordWelcome(event: .shown,exit: .closed,language: "en",alreadyPresented: true,firstLaunchCompleted: false)
        }
    }

    private func newCase() -> String { "test-"+UUID().uuidString.replacingOccurrences(of: "-",with: "").lowercased().prefix(20) }
    private func metadata(caseName: String) -> [String: Any] {
        ["OpenIslandRuntimeAcceptance": true, "CFBundleShortVersionString": "0.1.1", "CFBundleVersion": "6",
         "AIslandSourceCommit": String(repeating: "a",count: 40),
         "AIslandApprovedV6Commit": RuntimeAcceptanceConfiguration.approvedV6Commit,
         "OpenIslandAcceptanceSocketPath": "/tmp/aisland-v011-acceptance/\(caseName)/bridge.sock",
         "OpenIslandAcceptanceRegistryPath": "/tmp/aisland-v011-acceptance/\(caseName)/runtime-lifecycle.json"]
    }
}
