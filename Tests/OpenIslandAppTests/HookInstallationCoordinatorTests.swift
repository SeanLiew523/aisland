import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
struct HookInstallationCoordinatorTests {
    @Test
    func setupExplainsWhyHooksAreBlockedButBundledExtensionsAreAvailable() {
        let coordinator = HookInstallationCoordinator()
        #expect(coordinator.setupBlockReason(requiresBinary: true) == .missingHooksBinary)
        #expect(coordinator.setupBlockReason(requiresBinary: false) == nil)
        coordinator.hooksBinaryURL = URL(fileURLWithPath: "/synthetic/OpenIslandHooks")
        #expect(coordinator.setupBlockReason(requiresBinary: true) == nil)
    }

    @Test
    func acceptanceSetupBlocksBothKindsEvenWhenHelperIsLocated() {
        let coordinator = HookInstallationCoordinator(isRuntimeAcceptance: true)
        coordinator.hooksBinaryURL = URL(fileURLWithPath: "/synthetic/OpenIslandHooks")
        #expect(coordinator.setupBlockReason(requiresBinary: true) == .isolatedAcceptance)
        #expect(coordinator.setupBlockReason(requiresBinary: false) == .isolatedAcceptance)
    }

    @Test
    func acceptanceDoesNotDetectConfigureOrSuppressFreshWelcome() async throws {
        let suite = "aisland-acceptance-auto-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let intent = AgentIntentStore(defaults: defaults)
        let coordinator = HookInstallationCoordinator(intentStore: intent, isRuntimeAcceptance: true)
        await coordinator.detectInstalledSources()
        await coordinator.configureDetectedSources()
        coordinator.migrateIntentStoreIfNeeded()
        #expect(coordinator.detectedInstallations.isEmpty)
        #expect(coordinator.hermesHookStatus == nil)
        #expect(!coordinator.isAutomaticConnectionBusy)
        #expect(intent.migrationVersion == 1)
        #expect(!intent.firstLaunchCompleted)
        let welcome = OnboardingPresentationStore(defaults: defaults)
        #expect(welcome.claimAutomaticPresentation(migrationReady: intent.migrationVersion > 0, firstLaunchCompleted: intent.firstLaunchCompleted))
        intent.firstLaunchCompleted = true
        let secondLaunch = OnboardingPresentationStore(defaults: defaults)
        #expect(!secondLaunch.claimAutomaticPresentation(migrationReady: intent.migrationVersion > 0, firstLaunchCompleted: intent.firstLaunchCompleted))
        #expect(intent.intent(for: .hermes) == .untouched)
    }

    @Test
    func detectedStaleHooksAreRepairableButExplicitRemovalWins() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aisland-coordinator-current-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["claude", "codex"] {
            let file = root.appendingPathComponent(name)
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        let suite = "aisland-coordinator-current-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let intent = AgentIntentStore(defaults: defaults)
        let detector = AgentInstallationDetector(executableDirectories: [root], applicationDirectories: [], home: root)
        let coordinator = HookInstallationCoordinator(intentStore: intent, installationDetector: detector)
        let helper = root.appendingPathComponent("managed/OpenIslandHooks")
        let claude = ClaudeHookInstallationManager(claudeDirectory: root.appendingPathComponent(".claude"), managedHooksBinaryURL: helper)
        let codex = CodexHookInstallationManager(codexDirectory: root.appendingPathComponent(".codex"), managedHooksBinaryURL: helper, featureKeyProvider: { .legacy })
        _ = try claude.install(hooksBinaryURL: root.appendingPathComponent("claude"))
        _ = try codex.install(hooksBinaryURL: root.appendingPathComponent("codex"))
        try FileManager.default.removeItem(at: helper)
        coordinator.claudeHookStatus = try claude.status()
        coordinator.codexHookStatus = try codex.status()
        await coordinator.detectInstalledSources()
        #expect(coordinator.shouldAutoInstall(.claudeCode))
        #expect(coordinator.shouldAutoInstall(.codex))
        intent.setIntent(.uninstalled, for: .claudeCode)
        intent.setIntent(.uninstalled, for: .codex)
        #expect(!coordinator.shouldAutoInstall(.claudeCode))
        #expect(!coordinator.shouldAutoInstall(.codex))
        intent.setIntent(.untouched, for: .claudeCode)
        coordinator.detectedInstallations = [:]
        #expect(!coordinator.shouldAutoInstall(.claudeCode))
    }

    @Test
    func loadPiExtensionStatusesIsolatesCorruptedPiManifest() throws {
        let roots = try makeIsolatedRoots()
        defer { roots.cleanup() }

        let piManager = PiExtensionInstallationManager(agent: .pi, agentDirectory: roots.pi)
        let ompManager = PiExtensionInstallationManager(agent: .ohMyPi, agentDirectory: roots.omp)
        try installValidExtension(on: ompManager)
        try writeCorruptedManifest(at: piManager.manifestURL)

        let messages = StatusMessageBox()
        let coordinator = HookInstallationCoordinator(
            piExtensionInstallationManager: piManager,
            ohMyPiExtensionInstallationManager: ompManager
        )
        coordinator.onStatusMessage = { messages.append($0) }

        coordinator.loadPiExtensionStatuses()

        #expect(coordinator.piExtensionStatus == nil)
        #expect(coordinator.ohMyPiExtensionStatus?.isInstalled == true)
        #expect(messages.values.count == 1)
        #expect(messages.values[0].contains("Failed to read Pi extension status:"))
        #expect(!messages.values[0].contains("Oh My Pi"))
    }

    @Test
    func loadPiExtensionStatusesIsolatesCorruptedOhMyPiManifest() throws {
        let roots = try makeIsolatedRoots()
        defer { roots.cleanup() }

        let piManager = PiExtensionInstallationManager(agent: .pi, agentDirectory: roots.pi)
        let ompManager = PiExtensionInstallationManager(agent: .ohMyPi, agentDirectory: roots.omp)
        try installValidExtension(on: piManager)
        try writeCorruptedManifest(at: ompManager.manifestURL)

        let messages = StatusMessageBox()
        let coordinator = HookInstallationCoordinator(
            piExtensionInstallationManager: piManager,
            ohMyPiExtensionInstallationManager: ompManager
        )
        coordinator.onStatusMessage = { messages.append($0) }

        coordinator.loadPiExtensionStatuses()

        #expect(coordinator.piExtensionStatus?.isInstalled == true)
        #expect(coordinator.ohMyPiExtensionStatus == nil)
        #expect(messages.values.count == 1)
        #expect(messages.values[0].contains("Failed to read Oh My Pi extension status:"))
        #expect(!messages.values[0].hasPrefix("Failed to read Pi extension status:"))
    }

    @Test
    func loadPiExtensionStatusesUpdatesBothWhenHealthy() throws {
        let roots = try makeIsolatedRoots()
        defer { roots.cleanup() }

        let piManager = PiExtensionInstallationManager(agent: .pi, agentDirectory: roots.pi)
        let ompManager = PiExtensionInstallationManager(agent: .ohMyPi, agentDirectory: roots.omp)
        try installValidExtension(on: piManager)
        try installValidExtension(on: ompManager)

        let messages = StatusMessageBox()
        let coordinator = HookInstallationCoordinator(
            piExtensionInstallationManager: piManager,
            ohMyPiExtensionInstallationManager: ompManager
        )
        coordinator.onStatusMessage = { messages.append($0) }

        coordinator.loadPiExtensionStatuses()

        #expect(coordinator.piExtensionStatus?.isInstalled == true)
        #expect(coordinator.ohMyPiExtensionStatus?.isInstalled == true)
        #expect(messages.values.isEmpty)
    }

    @Test
    func loadPiExtensionStatusesReportsBothFailuresIndependently() throws {
        let roots = try makeIsolatedRoots()
        defer { roots.cleanup() }

        let piManager = PiExtensionInstallationManager(agent: .pi, agentDirectory: roots.pi)
        let ompManager = PiExtensionInstallationManager(agent: .ohMyPi, agentDirectory: roots.omp)
        try writeCorruptedManifest(at: piManager.manifestURL)
        try writeCorruptedManifest(at: ompManager.manifestURL)

        let messages = StatusMessageBox()
        let coordinator = HookInstallationCoordinator(
            piExtensionInstallationManager: piManager,
            ohMyPiExtensionInstallationManager: ompManager
        )
        coordinator.onStatusMessage = { messages.append($0) }

        coordinator.loadPiExtensionStatuses()

        #expect(coordinator.piExtensionStatus == nil)
        #expect(coordinator.ohMyPiExtensionStatus == nil)
        #expect(messages.values.count == 2)
        #expect(messages.values.contains(where: { $0.contains("Failed to read Pi extension status:") }))
        #expect(messages.values.contains(where: { $0.contains("Failed to read Oh My Pi extension status:") }))
    }

    private func makeIsolatedRoots() throws -> (pi: URL, omp: URL, cleanup: () -> Void) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-hook-coord-\(UUID().uuidString)", isDirectory: true)
        let pi = root.appendingPathComponent("pi", isDirectory: true)
        let omp = root.appendingPathComponent("omp", isDirectory: true)
        try FileManager.default.createDirectory(at: pi, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: omp, withIntermediateDirectories: true)
        return (pi, omp, { try? FileManager.default.removeItem(at: root) })
    }

    private func installValidExtension(on manager: PiExtensionInstallationManager) throws {
        let source = "const source = \"__OPEN_ISLAND_PI_SOURCE__\";\n"
        _ = try manager.install(extensionSourceData: Data(source.utf8))
    }

    private func writeCorruptedManifest(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{ not-json".utf8).write(to: url, options: .atomic)
    }
}

@MainActor
private final class StatusMessageBox {
    private(set) var values: [String] = []

    func append(_ message: String) {
        values.append(message)
    }
}
