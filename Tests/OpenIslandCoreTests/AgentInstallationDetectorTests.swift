import Foundation
import Testing
@testable import OpenIslandCore

struct AgentInstallationDetectorTests {
    @Test func executableEvidenceRejectsDirectoriesNonexecutablesAndDeferredCLI() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aisland-detection-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("claude"), withIntermediateDirectories: true)
        try Data("not executable".utf8).write(to: root.appendingPathComponent("qwen"))
        for name in ["hermes", "omp", "mcode"] { try executable(root.appendingPathComponent(name)) }
        let detector = AgentInstallationDetector(executableDirectories: [root], applicationDirectories: [], home: root)
        #expect(Set(detector.detect().keys) == [.hermes, .ohMyPi])
        // A missing binary discovered later is admitted on the next scan.
        try executable(root.appendingPathComponent("codex"))
        #expect(detector.detect()[.codex] != nil)
    }

    @Test func appRequiresExactIdentityAndExecutableNotLeftoverProfileDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aisland-app-detection-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("MiniMax Code.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".minimax/plugins"), withIntermediateDirectories: true)
        let detector = AgentInstallationDetector(executableDirectories: [], applicationDirectories: [root], home: root)
        func plist(_ identity: String, _ name: String = "MiniMax Code") throws {
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": identity, "CFBundleExecutable": name, "CFBundleShortVersionString": "3.1.0"], format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        }
        try plist("com.minimax.agent")
        #expect(detector.detect().isEmpty)
        try executable(contents.appendingPathComponent("MacOS/MiniMax Code"))
        try plist("foreign.bundle")
        #expect(detector.detect().isEmpty)
        try plist("com.minimax.agent", "../MacOS/MiniMax Code")
        #expect(detector.detect().isEmpty)
        try plist("com.minimax.agent")
        #expect(detector.detect()[.miniMaxCodeDesktop]?.version == "3.1.0")
    }

    @Test func detectedHermesConfiguresNormalProfileWithoutConsentAndReceivesMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aisland-auto-hermes-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try executable(bin.appendingPathComponent("hermes"))
        let detector = AgentInstallationDetector(executableDirectories: [bin], applicationDirectories: [], home: root)
        let suite = "aisland-auto-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AgentIntentStore(defaults: defaults)
        let manager = HermesHookInstallationManager(profileDirectory: root.appendingPathComponent(".hermes"))
        let hook = bin.appendingPathComponent("OpenIslandHooks")
        try executable(hook)
        if store.shouldAutomaticallyConfigure(.hermes, installationDetected: detector.detect()[.hermes] != nil, configurationCurrent: false) {
            #expect(try manager.install(hooksBinaryURL: hook).isCurrent)
            store.setIntent(.installed, for: .hermes)
        }
        let bytes = try Data(contentsOf: manager.configURL)
        #expect(!FileManager.default.fileExists(atPath: manager.profileDirectory.appendingPathComponent("shell-hooks-allowlist.json").path))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("auto_accept"))
        #expect(!store.shouldAutomaticallyConfigure(.hermes, installationDetected: true, configurationCurrent: try manager.status(hooksBinaryURL: hook).isCurrent))
        let raw = #"{"hook_event_name":"pre_llm_call","session_id":"fixture-session","cwd":"/fixture","extra":{"turn_id":"fixture-turn"}}"#
        let start = try #require(try HermesHookAdapter.decode(Data(raw.utf8), profileID: manager.profileDirectory.path, ttyProvider: { nil }))
        var receiver = RuntimeLifecycleReducer()
        #expect(!receiver.receive(start).isEmpty)
        #expect(receiver.receive(start).isEmpty)
        store.setIntent(.uninstalled, for: .hermes)
        _ = try manager.uninstall()
        #expect(!store.shouldAutomaticallyConfigure(.hermes, installationDetected: true, configurationCurrent: false))
        #expect(!store.shouldAutomaticallyConfigure(.codex, installationDetected: false, configurationCurrent: false))
        #expect(!store.shouldAutomaticallyConfigure(.claudeUsageBridge, installationDetected: true, configurationCurrent: false))
    }

    private func executable(_ url: URL) throws {
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
