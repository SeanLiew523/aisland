import Foundation
import Testing
@testable import OpenIslandCore

struct HookConfigurationCurrentTests {
    @Test func claudeCompleteHelperPathAndFormattingDetermineCurrent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aisland-current-claude-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("managed/OpenIslandHooks")
        let source = root.appendingPathComponent("source-helper")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        let manager = ClaudeHookInstallationManager(claudeDirectory: root.appendingPathComponent(".claude"), managedHooksBinaryURL: helper)
        #expect(try manager.install(hooksBinaryURL: source).isCurrent)
        let complete = try Data(contentsOf: manager.status().settingsURL)
        let object = try JSONSerialization.jsonObject(with: complete)
        try JSONSerialization.data(withJSONObject: object).write(to: manager.status().settingsURL)
        #expect(try manager.status().isCurrent, "JSON formatting alone must not cause rewrites")
        try FileManager.default.removeItem(at: helper)
        #expect(try manager.status().managedHooksPresent)
        #expect(try !manager.status().isCurrent, "missing helper is not a current connection")
        _ = try manager.install(hooksBinaryURL: source)
        var partial = try #require(object as? [String: Any])
        let hooks = try #require(partial["hooks"] as? [String: Any])
        partial["hooks"] = ["SessionStart": hooks["SessionStart"]!]
        try JSONSerialization.data(withJSONObject: partial).write(to: manager.status().settingsURL)
        #expect(try manager.status().managedHooksPresent)
        #expect(try !manager.status().isCurrent, "one owned hook does not prove the complete lifecycle set")
        _ = try manager.install(hooksBinaryURL: source)
        let old = root.appendingPathComponent("missing-VibeIslandHooks")
        let command = ClaudeHookInstaller.hookCommand(for: old.path)
        try ClaudeHookInstaller.installSettingsJSON(existingData: nil, hookCommand: command).contents!.write(to: manager.status().settingsURL)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(ClaudeHookInstallerManifest(hookCommand: command)).write(to: manager.status().manifestURL)
        #expect(try manager.status().managedHooksPresent)
        #expect(try !manager.status().isCurrent)
    }
    @Test func codexDisabledFeatureAndMissingHelperRemainRepairableWithoutOverridingRemoval() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aisland-current-codex-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("managed/OpenIslandHooks")
        let source = root.appendingPathComponent("source-helper")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        let manager = CodexHookInstallationManager(codexDirectory: root.appendingPathComponent(".codex"), managedHooksBinaryURL: helper, featureKeyProvider: { .legacy })
        #expect(try manager.install(hooksBinaryURL: source).isCurrent)
        let config = try manager.status().configURL
        try Data("[features]\ncodex_hooks = false\n".utf8).write(to: config)
        var status = try manager.status()
        #expect(status.managedHooksPresent && !status.isCurrent)
        let suite = "aisland-current-intent-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let intent = AgentIntentStore(defaults: defaults)
        #expect(intent.shouldAutomaticallyConfigure(.codex, installationDetected: true, configurationCurrent: status.isCurrent))
        intent.setIntent(.uninstalled, for: .codex)
        #expect(!intent.shouldAutomaticallyConfigure(.codex, installationDetected: true, configurationCurrent: status.isCurrent))
        #expect(!intent.shouldAutomaticallyConfigure(.codex, installationDetected: false, configurationCurrent: false))
        _ = try manager.install(hooksBinaryURL: source)
        try FileManager.default.removeItem(at: helper)
        status = try manager.status()
        #expect(status.managedHooksPresent && !status.isCurrent)
    }
}
