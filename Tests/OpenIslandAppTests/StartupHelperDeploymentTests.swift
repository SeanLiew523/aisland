import Foundation
import Testing
import OpenIslandCore
@testable import OpenIslandApp

private actor StartupPause {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var entries = 0

    func wait() async {
        entries += 1
        guard !isOpen else { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func release() {
        isOpen = true
        let pending = continuations
        continuations.removeAll()
        for continuation in pending { continuation.resume() }
    }
}

@MainActor private final class StartupTrace {
    var events: [String] = []
    func record(_ event: String) { events.append(event) }
}

private struct StartupFixture {
    let root: URL
    let defaults: UserDefaults
    let domain: String

    init() throws {
        domain = "startup-helper-tests-\(UUID())"
        defaults = try #require(UserDefaults(suiteName: domain))
        root = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: domain)
        try? FileManager.default.removeItem(at: root)
    }

    func executable(_ path: String, bytes: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}

@MainActor private func waitForStartup(_ condition: @MainActor () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while !(await condition()), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(await condition())
}

@MainActor struct StartupHelperDeploymentTests {
    @Test func pausedHistoryDoesNotDelayDeploymentAndSetupWaitsForNewHelper() async throws {
        let fixture = try StartupFixture(); defer { fixture.cleanup() }
        let source = try fixture.executable("Current.app/Contents/Helpers/OpenIslandHooks", bytes: "new callback")
        let managed = try fixture.executable("managed/OpenIslandHooks", bytes: "old callback")
        let history = StartupPause(), deployment = StartupPause()
        defer { Task { await history.release(); await deployment.release() } }
        let trace = StartupTrace(), intent = AgentIntentStore(defaults: fixture.defaults)
        let hooks = HookInstallationCoordinator(intentStore: intent,
            startupHookBinaryLocator: { source },
            startupHookBinaryDeployer: { source in
                await trace.record("deployment-start")
                await deployment.wait()
                _ = try ManagedHooksBinary.install(from: source, to: managed)
                await trace.record("deployment-done")
                return true
            }, startupStages: .init(
                detect: { trace.record("detect") },
                refresh: { trace.record("refresh") },
                configure: { trace.record("configure") }))
        // A previously located helper must not stay available during deployment.
        hooks.hooksBinaryURL = managed
        let workflows = StartupWorkflows()
        workflows.start(history: {
            await history.wait()
            await trace.record("history-done")
        }, connections: {
            await hooks.runStartupSetup {
                #expect(intent.migrationVersion == 1 && !intent.firstLaunchCompleted)
                trace.record("ready")
            }
        })
        workflows.start(history: { await trace.record("duplicate-history") },
            connections: { trace.record("duplicate-connections") })

        try await waitForStartup {
            let deploymentEntries = await deployment.entries
            let historyEntries = await history.entries
            return deploymentEntries == 1 && historyEntries == 1
        }
        #expect(hooks.hooksBinaryURL == nil)
        #expect(trace.events == ["deployment-start"])
        #expect(try Data(contentsOf: managed) == Data("old callback".utf8))
        await deployment.release()
        try await waitForStartup { trace.events.contains("configure") }
        #expect(trace.events == ["deployment-start", "deployment-done", "detect", "refresh", "ready", "configure"])
        #expect(hooks.hooksBinaryURL == source)
        #expect(try Data(contentsOf: managed) == Data("new callback".utf8))
        #expect(!intent.firstLaunchCompleted)

        await history.release()
        try await waitForStartup { trace.events.contains("history-done") }
        #expect(hooks.hooksBinaryURL == source)
        #expect(trace.events.filter { $0 == "ready" }.count == 1)
        #expect(!trace.events.contains(where: { $0.hasPrefix("duplicate") }))
    }

    @Test func bundledHelperIsRequiredEvenWhenOtherExecutableExists() throws {
        let fixture = try StartupFixture(); defer { fixture.cleanup() }
        let bundle = fixture.root.appendingPathComponent("Current.app")
        let executableDirectory = fixture.root.appendingPathComponent("fallback")
        _ = try fixture.executable("fallback/OpenIslandHooks", bytes: "stale callback")
        #expect(HookInstallationCoordinator.startupHookBinary(bundleURL: bundle,
            executableDirectory: executableDirectory) == nil)
        let source = try fixture.executable("Current.app/Contents/Helpers/OpenIslandHooks", bytes: "current callback")
        #expect(HookInstallationCoordinator.startupHookBinary(bundleURL: bundle,
            executableDirectory: executableDirectory) == source)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: source.path)
        #expect(HookInstallationCoordinator.startupHookBinary(bundleURL: bundle,
            executableDirectory: executableDirectory) == nil)
    }

    @Test func failedDeploymentDoesNotConfigureOrPublishHelperAndReadyIsOnce() async throws {
        let fixture = try StartupFixture(); defer { fixture.cleanup() }
        let source = fixture.root.appendingPathComponent("helper")
        let trace = StartupTrace(), intent = AgentIntentStore(defaults: fixture.defaults)
        let hooks = HookInstallationCoordinator(intentStore: intent,
            startupHookBinaryLocator: { source },
            startupHookBinaryDeployer: { _ in throw CocoaError(.fileWriteNoPermission) },
            startupStages: .init(detect: { trace.record("detect") },
                refresh: { trace.record("refresh") }, configure: { trace.record("configure") }))
        hooks.onStatusMessage = { _ in trace.record("error") }
        await hooks.runStartupSetup { trace.record("ready") }
        await hooks.runStartupSetup { trace.record("duplicate-ready") }
        #expect(hooks.hooksBinaryURL == nil)
        #expect(!trace.events.contains("configure"))
        #expect(!trace.events.contains("duplicate-ready"))
        #expect(trace.events.filter { $0 == "ready" }.count == 1)
        #expect(intent.migrationVersion == 1 && !intent.firstLaunchCompleted)
    }

    @Test func missingHelperSkipsDeploymentAndSourceConfiguration() async throws {
        let fixture = try StartupFixture(); defer { fixture.cleanup() }
        let trace = StartupTrace()
        let hooks = HookInstallationCoordinator(intentStore: AgentIntentStore(defaults: fixture.defaults),
            startupHookBinaryLocator: { nil },
            startupHookBinaryDeployer: { _ in Issue.record("No helper was located"); return true },
            startupStages: .init(detect: { trace.record("detect") },
                refresh: { trace.record("refresh") }, configure: { trace.record("configure") }))
        await hooks.runStartupSetup { trace.record("ready") }
        #expect(trace.events == ["detect", "refresh", "ready"])
        #expect(hooks.hooksBinaryURL == nil)
    }

    @Test func runtimeAcceptanceCallsNoOrdinaryStartupStage() async throws {
        let fixture = try StartupFixture(); defer { fixture.cleanup() }
        let intent = AgentIntentStore(defaults: fixture.defaults), trace = StartupTrace()
        let hooks = HookInstallationCoordinator(intentStore: intent, isRuntimeAcceptance: true,
            startupHookBinaryLocator: { Issue.record("Acceptance must not locate a normal helper"); return nil },
            startupHookBinaryDeployer: { _ in Issue.record("Acceptance must not deploy a normal helper"); return true },
            startupStages: .init(detect: { Issue.record("Acceptance must not detect ordinary sources") },
                refresh: { Issue.record("Acceptance must not inspect ordinary config") },
                configure: { Issue.record("Acceptance must not configure ordinary sources") }))
        hooks.hooksBinaryURL = fixture.root.appendingPathComponent("must-not-be-deployed")
        try await hooks.updateHooksBinaryIfNeeded()
        await hooks.runStartupSetup { trace.record("ready") }
        await hooks.runStartupSetup { trace.record("duplicate-ready") }
        #expect(trace.events == ["ready"])
        #expect(intent.migrationVersion == 1 && !intent.firstLaunchCompleted)
        #expect(hooks.detectedInstallations.isEmpty)
    }
}
