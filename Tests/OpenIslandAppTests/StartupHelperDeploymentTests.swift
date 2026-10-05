import Foundation
import Testing
import OpenIslandCore
@testable import OpenIslandApp

private actor StartupPause {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var entries = 0
    private let entered = StartupFixtureSignal()
    func waitUntilEntered() async throws { try await entered.wait() }

    func wait() async {
        entries += 1
        entered.signal()
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
    private var signals: [String: StartupFixtureSignal] = [:]
    private func signal(for event: String) -> StartupFixtureSignal {
        if let signal = signals[event] { return signal }
        let signal = StartupFixtureSignal()
        signals[event] = signal
        return signal
    }
    func record(_ event: String) {
        events.append(event)
        signal(for: event).signal()
    }
    func waitFor(_ event: String) async throws {
        try await signal(for: event).wait()
    }
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

// The guard detects missing callbacks, rather than asserting a startup latency
// contract based on unrelated main-actor work in other parallel suites.
@Suite(.timeLimit(.minutes(1)))
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
                return managed
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

        try await deployment.waitUntilEntered()
        try await history.waitUntilEntered()
        let deploymentEntries = await deployment.entries
        let historyEntries = await history.entries
        #expect(deploymentEntries == 1 && historyEntries == 1)
        #expect(hooks.hooksBinaryURL == nil)
        #expect(trace.events == ["deployment-start"])
        #expect(try Data(contentsOf: managed) == Data("old callback".utf8))
        await deployment.release()
        try await trace.waitFor("configure")
        #expect(trace.events == ["deployment-start", "deployment-done", "detect", "refresh", "ready", "configure"])
        #expect(hooks.hooksBinaryURL == managed)
        #expect(try Data(contentsOf: managed) == Data("new callback".utf8))
        #expect(!intent.firstLaunchCompleted)

        await history.release()
        try await trace.waitFor("history-done")
        #expect(hooks.hooksBinaryURL == managed)
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
            startupHookBinaryDeployer: { source in Issue.record("No helper was located"); return source },
            startupStages: .init(detect: { trace.record("detect") },
                refresh: { trace.record("refresh") }, configure: { trace.record("configure") }))
        await hooks.runStartupSetup { trace.record("ready") }
        #expect(trace.events == ["detect", "refresh", "ready"])
        #expect(hooks.hooksBinaryURL == nil)
    }

    @Test(arguments: ["missing", "stale", "nonExecutable"])
    func unverifiedDeploymentCannotPublishOrConfigure(_ failure: String) async throws {
        let fixture = try StartupFixture(); defer { fixture.cleanup() }
        let source = try fixture.executable("Current.app/Contents/Helpers/OpenIslandHooks", bytes: "current callback")
        let destination = fixture.root.appendingPathComponent("managed/OpenIslandHooks")
        if failure != "missing" {
            _ = try fixture.executable("managed/OpenIslandHooks",
                bytes: failure == "stale" ? "previous callback" : "current callback")
            if failure == "nonExecutable" {
                try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destination.path)
            }
        }
        let trace = StartupTrace()
        let hooks = HookInstallationCoordinator(intentStore: AgentIntentStore(defaults: fixture.defaults),
            startupHookBinaryLocator: { source }, startupHookBinaryDeployer: { _ in destination },
            startupStages: .init(detect: {}, refresh: {}, configure: { trace.record("configure") }))
        await hooks.runStartupSetup { trace.record("ready") }
        #expect(hooks.hooksBinaryURL == nil)
        #expect(trace.events == ["ready"])
    }

    @Test func hermesCommandsAndConsentKeepDurableIdentityAcrossBundleMoves() async throws {
        let fixture = try StartupFixture(); defer { fixture.cleanup() }
        let destination = fixture.root.appendingPathComponent("managed/OpenIslandHooks")
        let profile = fixture.root.appendingPathComponent("hermes-profile")
        let manager = HermesHookInstallationManager(profileDirectory: profile)
        let intent = AgentIntentStore(defaults: fixture.defaults)

        for version in ["First", "Second"] {
            let bundle = fixture.root.appendingPathComponent("\(version).app")
            let source = try fixture.executable("\(version).app/Contents/Helpers/OpenIslandHooks", bytes: version)
            let hooks = HookInstallationCoordinator(intentStore: intent,
                startupHookBinaryLocator: {
                    HookInstallationCoordinator.startupHookBinary(bundleURL: bundle, executableDirectory: nil)
                }, startupHookBinaryDeployer: { source in
                    try ManagedHooksBinary.install(from: source, to: destination)
                }, startupStages: .init(detect: {}, refresh: {}, configure: {}))
            await hooks.runStartupSetup {}
            let published = try #require(hooks.hooksBinaryURL)
            #expect(published == destination && published != source)
            #expect(try Data(contentsOf: published) == Data(version.utf8))
            let status = try manager.install(hooksBinaryURL: published)
            #expect(status.isCurrent)
            let manifest = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: manager.manifestURL)) as? [String: Any])
            let command = try #require(manifest["command"] as? String)
            #expect(command.contains(destination.path) && !command.contains(bundle.path))
            let config = try String(contentsOf: manager.configURL, encoding: .utf8)
            #expect(config.components(separatedBy: destination.path).count == 3)
            #expect(!config.contains(bundle.path))
            if version == "First" {
                let approvals = ["pre_llm_call", "on_session_end"].map { ["event": $0, "command": command] }
                try JSONSerialization.data(withJSONObject: ["approvals": approvals])
                    .write(to: profile.appendingPathComponent("shell-hooks-allowlist.json"))
            }
            // Removing the fixture bundle must not invalidate the normal command.
            try FileManager.default.removeItem(at: bundle)
            let movedStatus = try manager.status(hooksBinaryURL: published)
            #expect(movedStatus.isCurrent && movedStatus.hasConsent)
            #expect(FileManager.default.isExecutableFile(atPath: published.path))
        }
    }

    @Test func runtimeAcceptanceCallsNoOrdinaryStartupStage() async throws {
        let fixture = try StartupFixture(); defer { fixture.cleanup() }
        let intent = AgentIntentStore(defaults: fixture.defaults), trace = StartupTrace()
        let hooks = HookInstallationCoordinator(intentStore: intent, isRuntimeAcceptance: true,
            startupHookBinaryLocator: { Issue.record("Acceptance must not locate a normal helper"); return nil },
            startupHookBinaryDeployer: { source in Issue.record("Acceptance must not deploy a normal helper"); return source },
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
