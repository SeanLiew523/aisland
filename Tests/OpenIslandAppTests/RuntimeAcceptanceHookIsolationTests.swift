import Foundation
import Testing
import OpenIslandCore
@testable import OpenIslandApp

struct RuntimeAcceptanceHookIsolationTests {
    @Test @MainActor func settingsRefreshRepairAndInstallStayIsolated() async throws {
        let name = "acceptance-hook-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let intent = AgentIntentStore(defaults: defaults)
        intent.setIntent(.installed,for: .codex)
        intent.setIntent(.uninstalled,for: .claudeCode)
        let hooks = HookInstallationCoordinator(intentStore: intent,isRuntimeAcceptance: true)
        hooks.hooksBinaryURL = URL(fileURLWithPath: "/tmp/acceptance-binary-must-not-be-installed")
        try await hooks.updateHooksBinaryIfNeeded()
        hooks.updateClaudeConfigDirectory(to: URL(fileURLWithPath: "/tmp/acceptance-directory-must-not-be-used"))
        hooks.refreshCodexHookStatus(); hooks.refreshClaudeHookStatus()
        hooks.refreshCCForkHookStatuses(); hooks.refreshOpenCodePluginStatus()
        hooks.refreshCursorHookStatus(); hooks.refreshGeminiHookStatus()
        hooks.refreshKimiHookStatus(); hooks.refreshGrokHookStatus()
        hooks.refreshPiExtensionStatuses(); hooks.loadPiExtensionStatuses()
        hooks.refreshClaudeUsageState(); hooks.refreshCodexUsageState()
        hooks.startClaudeUsageMonitoringIfNeeded(); hooks.startCodexUsageMonitoringIfNeeded()
        await hooks.refreshAllHookStatusAndWait()
        hooks.runHealthChecks()
        #expect(await hooks.repairHooksIfNeeded() == false)
        hooks.installCodexHooks(); hooks.uninstallCodexHooks()
        hooks.installClaudeHooks(); hooks.uninstallClaudeHooks()
        hooks.installQoderHooks(); hooks.uninstallQoderHooks()
        hooks.installQwenCodeHooks(); hooks.uninstallQwenCodeHooks()
        hooks.installFactoryHooks(); hooks.uninstallFactoryHooks()
        hooks.installCodebuddyHooks(); hooks.uninstallCodebuddyHooks()
        hooks.installZcodeHooks(); hooks.uninstallZcodeHooks()
        hooks.installWorkbuddyHooks(); hooks.uninstallWorkbuddyHooks()
        hooks.installOpenCodePlugin(); hooks.uninstallOpenCodePlugin()
        hooks.installCursorHooks(); hooks.uninstallCursorHooks()
        hooks.installGeminiHooks(); hooks.uninstallGeminiHooks()
        hooks.installKimiHooks(); hooks.uninstallKimiHooks()
        hooks.installGrokHooks(); hooks.uninstallGrokHooks()
        hooks.installPiExtension(); hooks.uninstallPiExtension()
        hooks.installOhMyPiExtension(); hooks.uninstallOhMyPiExtension()
        hooks.installClaudeUsageBridge(); hooks.uninstallClaudeUsageBridge()
        #expect(intent.intent(for: .codex) == .installed)
        #expect(intent.intent(for: .claudeCode) == .uninstalled)
        #expect(!hooks.shouldAutoInstall(.codex))
        #expect(hooks.codexHookStatus == nil && hooks.claudeHookStatus == nil)
        #expect(hooks.piExtensionStatus == nil && hooks.ohMyPiExtensionStatus == nil)
        #expect(hooks.claudeUsageSnapshot == nil && hooks.codexUsageSnapshot == nil)
        #expect(hooks.healthReports.isEmpty)
        #expect(hooks.codexHookStatusSummary.contains("disabled") || hooks.codexHookStatusSummary.contains("停用"))
        #expect(throws: RuntimeAcceptanceConfiguration.ConfigurationError.self) {
            try hooks.readClaudeUsageState(repairManagedBridgeIfNeeded: true)
        }
    }

    @Test @MainActor func isolatedMigrationUsesNoInstalledDetectionAndPreservesUpgradeCompletion() throws {
        let name = "acceptance-hook-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("zh-Hant",forKey: "appLanguage")
        let intent = AgentIntentStore(defaults: defaults)
        intent.firstLaunchCompleted = true
        let hooks = HookInstallationCoordinator(intentStore: intent,isRuntimeAcceptance: true)
        hooks.migrateIntentStoreIfNeeded()
        #expect(intent.migrationVersion == 1)
        #expect(intent.firstLaunchCompleted)
        #expect(defaults.string(forKey: "appLanguage") == "zh-Hant")
        #expect(AgentIdentifier.allCases.allSatisfy { intent.intent(for: $0) == .untouched })
    }
}
