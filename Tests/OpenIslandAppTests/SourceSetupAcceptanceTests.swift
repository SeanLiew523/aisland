import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

private struct SourceSetupFixture {
    let root: URL, bundle: URL, identifier: String
    var info: [String: Any]
    init(agents: [String] = ["hermes"]) throws {
        let name = "setup-test-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16)
        root = URL(fileURLWithPath: "/private/tmp/aisland-v011-acceptance/" + name)
        bundle = root.appendingPathComponent("app/AIsland.app")
        identifier = RuntimeAcceptanceConfiguration.bundlePrefix + name
        info = ["OpenIslandRuntimeAcceptance": true, "AIslandSourceSetupAcceptance": true,
            "AIslandSourceSetupAgents": agents, "AIslandSourceSetupSupportPath": root.appendingPathComponent("support").path,
            "CFBundleShortVersionString": "0.1.1", "CFBundleVersion": "39",
            "AIslandSourceCommit": String(repeating: "a", count: 40),
            "AIslandApprovedV6Commit": RuntimeAcceptanceConfiguration.approvedV6Commit,
            "OpenIslandAcceptanceSocketPath": root.appendingPathComponent("bridge.sock").path,
            "OpenIslandAcceptanceRegistryPath": root.appendingPathComponent("runtime-lifecycle.json").path]
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents/Helpers"), withIntermediateDirectories: true)
    }
    func configuration() throws -> RuntimeAcceptanceConfiguration {
        try #require(try RuntimeAcceptanceConfiguration(infoDictionary: info, bundleIdentifier: identifier, bundleURL: bundle))
    }
    func helper(real: Bool = false) throws {
        let url = bundle.appendingPathComponent("Contents/Helpers/OpenIslandHooks")
        if real {
            let path = try #require(ProcessInfo.processInfo.environment["AISLAND_TEST_HOOKS_BINARY"])
            try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: url)
        } else { try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
    func cleanup() { try? FileManager.default.removeItem(at: root); UserDefaults(suiteName: identifier)?.removePersistentDomain(forName: identifier) }
}

struct SourceSetupAdmissionTests {
    @Test func sourceSetupRequiresTypedBooleanActualBundleLocationAndExplicitSourceList() throws {
        let fixture = try SourceSetupFixture(); defer { fixture.cleanup() }
        let config = try fixture.configuration()
        #expect(config.skipsRuntimeDiscovery && !config.skipsHookStatusReadsAndInstallation)
        #expect(config.sourceSetup?.agents == [.hermes])
        for primary: Any in [false, "true", 1] {
            var changed = fixture.info; changed["OpenIslandRuntimeAcceptance"] = primary
            #expect(throws: (any Error).self) { try RuntimeAcceptanceConfiguration(infoDictionary: changed, bundleIdentifier: fixture.identifier, bundleURL: fixture.bundle) }
        }
        #expect(throws: (any Error).self) { try RuntimeAcceptanceConfiguration(infoDictionary: fixture.info, bundleIdentifier: fixture.identifier) }
        #expect(throws: (any Error).self) { try RuntimeAcceptanceConfiguration(infoDictionary: fixture.info, bundleIdentifier: fixture.identifier, bundleURL: URL(fileURLWithPath: "/Applications/AIsland.app")) }
        for (key, value): (String, Any) in [("AIslandSourceSetupAcceptance", "true"), ("AIslandSourceSetupAcceptance", 1),
            ("AIslandSourceSetupAcceptance", false), ("AIslandSourceSetupAgents", ["codex"]), ("AIslandSourceSetupAgents", ["miniMaxCodeCLI"]),
            ("AIslandSourceSetupAgents", ["hermes", "hermes"]), ("AIslandSourceSetupSupportPath", NSHomeDirectory() + "/Library/Application Support/OpenIsland")] {
            var changed = fixture.info; changed[key] = value
            #expect(throws: (any Error).self) { try RuntimeAcceptanceConfiguration(infoDictionary: changed, bundleIdentifier: fixture.identifier, bundleURL: fixture.bundle) }
        }
        var ordinary = fixture.info; ordinary.removeValue(forKey: "AIslandSourceSetupAcceptance")
        #expect(try RuntimeAcceptanceConfiguration(infoDictionary: ordinary, bundleIdentifier: fixture.identifier, bundleURL: fixture.bundle)?.skipsHookStatusReadsAndInstallation == true)
    }
    @Test func redirectedBundleOrSupportCannotCreateAWrapper() throws {
        let f = try SourceSetupFixture(); defer { f.cleanup() }
        let redirect = f.root.appendingPathComponent("redirect")
        try FileManager.default.createDirectory(at: redirect, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: f.root.appendingPathComponent("support"), withDestinationURL: redirect)
        #expect(throws: (any Error).self) { try f.configuration() }
    }
    @Test func wrapperCreationIsIdempotentAndRejectsForeignFilesWithoutOverwriting() throws {
        let f = try SourceSetupFixture(); defer { f.cleanup() }; try f.helper()
        let setup = try #require(try f.configuration().sourceSetup)
        let wrapper = try setup.prepareHooksWrapper(), before = try Data(contentsOf: wrapper)
        #expect(try setup.prepareHooksWrapper() == wrapper)
        #expect(try Data(contentsOf: wrapper) == before)
        #expect(String(decoding: before, as: UTF8.self).contains("export OPEN_ISLAND_SOCKET_PATH='" + setup.socketURL.path + "'"))
        let changed = Data("user wrapper".utf8); try changed.write(to: wrapper)
        #expect(throws: (any Error).self) { try setup.prepareHooksWrapper() }
        #expect(try Data(contentsOf: wrapper) == changed)
    }
    @Test func updaterVersionRequiresAValidatedFixtureAtItsActualLocation() throws {
        let f = try SourceSetupFixture(); defer { f.cleanup() }
        var rejected = f.info; rejected["CFBundleShortVersionString"] = "0.1.2"
        #expect(throws: (any Error).self) { try RuntimeAcceptanceConfiguration(infoDictionary: rejected, bundleIdentifier: f.identifier, bundleURL: f.bundle) }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let root = URL(fileURLWithPath: "/private/tmp/aisland-updater-app-fixture-" + token)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("installed/AIsland.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let name = "upd-" + token.suffix(16), id = RuntimeAcceptanceConfiguration.bundlePrefix + name
        var info = f.info
        for key in info.keys.filter({ $0.hasPrefix("AIslandSourceSetup") }) { info.removeValue(forKey: key) }
        info["CFBundleShortVersionString"] = "0.1.2"
        info["OpenIslandAcceptanceSocketPath"] = "/private/tmp/aisland-v011-acceptance/\(name)/bridge.sock"
        info["OpenIslandAcceptanceRegistryPath"] = "/private/tmp/aisland-v011-acceptance/\(name)/runtime-lifecycle.json"
        info["AIslandUpdaterFixture"] = true; info["AIslandUpdaterFixtureSupported"] = true
        info["AIslandUpdaterFixtureRoot"] = root.path; info["AIslandUpdaterFixtureOrigin"] = "http://127.0.0.1:51234"
        info["SUPublicEDKey"] = Data(repeating: 1, count: 32).base64EncodedString()
        info["AIslandUpdateSigningIdentity"] = "aisland-ed25519-v1"
        info["SURequireSignedFeed"] = true; info["SUVerifyUpdateBeforeExtraction"] = true; info["OpenIslandDisableUpdates"] = false
        let fixture = try #require(try UpdaterFixtureConfiguration(infoDictionary: info, bundleURL: app, bundleIdentifier: id))
        #expect(throws: (any Error).self) { try RuntimeAcceptanceConfiguration(infoDictionary: info, bundleIdentifier: id, bundleURL: app) }
        let accepted = try #require(try RuntimeAcceptanceConfiguration(infoDictionary: info, bundleIdentifier: id, bundleURL: app, updaterFixture: fixture))
        #expect(accepted.sourceSetup == nil && accepted.skipsHookStatusReadsAndInstallation)
    }
}

@MainActor struct SourceSetupStartupTests {
    @Test func actualDetectionConfigurationAndCallbackStayIsolatedAndPreserveConsent() async throws {
        let f = try SourceSetupFixture(); defer { f.cleanup() }; try f.helper(real: true)
        let config = try f.configuration(), setup = try #require(config.sourceSetup)
        let home = f.root.appendingPathComponent("source-home"), executables = home.appendingPathComponent("bin"), profile = home.appendingPathComponent(".hermes")
        for directory in [executables, profile] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        for name in ["hermes", "codex"] {
            let file = executables.appendingPathComponent(name); try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        let originalWrapper = profile.appendingPathComponent("original-wrapper")
        let originalWrapperData = Data("#!/bin/sh\nexit 0 # KEEP ORIGINAL\n".utf8)
        try originalWrapperData.write(to: originalWrapper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: originalWrapper.path)
        let manager = HermesHookInstallationManager(profileDirectory: profile)
        try Data("# KEEP CONFIG\nmodel: custom\nhooks:\n  pre_llm_call:\n    - command: user-hook\n      timeout: 7\n".utf8).write(to: manager.configURL)
        _ = try manager.install(hooksBinaryURL: originalWrapper)
        let originalManifest = try Data(contentsOf: manager.manifestURL)
        let consent = Data("{\"approvals\":[{\"event\":\"pre_llm_call\",\"command\":\"user-hook\"}]}".utf8)
        try consent.write(to: profile.appendingPathComponent("shell-hooks-allowlist.json"))
        let intent = AgentIntentStore(defaults: try config.isolatedPreferences())
        let detector = AgentInstallationDetector(executableDirectories: [executables], applicationDirectories: [], home: home)
        let coordinator = HookInstallationCoordinator(intentStore: intent, isRuntimeAcceptance: true, sourceSetupAcceptance: setup,
            installationDetector: detector, hermesInstallationManager: manager)
        var claimed = false
        await coordinator.runStartupSetup {
            claimed = OnboardingPresentationStore(defaults: try! config.isolatedPreferences()).claimAutomaticPresentation(migrationReady: intent.migrationVersion > 0, firstLaunchCompleted: intent.firstLaunchCompleted)
        }
        #expect(claimed && !intent.firstLaunchCompleted)
        #expect(coordinator.setupBlockReason(requiresBinary: true) == .sourceSetupScope)
        #expect(coordinator.detectedInstallations[.hermes] != nil && coordinator.detectedInstallations[.codex] != nil)
        #expect(!coordinator.shouldAutoInstall(.codex))
        #expect(coordinator.hermesHookStatus?.isCurrent == true && coordinator.hermesHookStatus?.hasConsent == false)
        #expect(try Data(contentsOf: originalWrapper) == originalWrapperData)
        #expect(try Data(contentsOf: profile.appendingPathComponent("shell-hooks-allowlist.json")) == consent)
        let current = try String(contentsOf: manager.configURL, encoding: .utf8)
        #expect(current.contains("# KEEP CONFIG\nmodel: custom\n") && current.contains("user-hook"))
        #expect(current.contains(setup.hooksBinaryURL.path) && !current.contains(originalWrapper.path))
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex").path))
        let backups = try FileManager.default.contentsOfDirectory(at: setup.supportURL.appendingPathComponent("connection-backups"), includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: backups[0].appendingPathComponent("aisland-hooks.json")) == originalManifest)
        let receipt = setup.supportURL.appendingPathComponent("source-setup-receipts.jsonl")
        #expect(try String(contentsOf: receipt, encoding: .utf8).contains("waitingForConsent"))
        // Actual CLI helper callback -> production bridge reducer -> observer;
        // only synthetic metadata, no real source process or user session.
        let server = BridgeServer(socketURL: config.socketURL, runtimeLifecycleRegistryURL: config.runtimeLifecycleRegistryURL, monitorMiniMaxCode: false)
        try server.start(); defer { server.stop() }
        let observer = LocalBridgeClient(socketURL: config.socketURL)
        let stream = try observer.connect(); defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))
        let consumer = Task { () -> AgentEvent? in
            try await withThrowingTaskGroup(of: AgentEvent?.self) { group in
                group.addTask { for try await event in stream { if case .sessionStarted = event { return event } }; return nil }
                group.addTask { try await Task.sleep(for: .seconds(3)); return nil }
                let result = try await group.next() ?? nil; group.cancelAll(); return result
            }
        }
        let binary = setup.hooksBinaryURL
        try await Task.detached {
            let process = Process(); process.executableURL = binary; process.arguments = ["--source", "hermes", "--profile-id", profile.path]
            // A conflicting inherited override cannot redirect the owned wrapper.
            process.environment = ["PATH": "/usr/bin:/bin", "OPEN_ISLAND_SOCKET_PATH": "/tmp/never-use-production.sock"]
            let pipe = Pipe(); process.standardInput = pipe; process.standardOutput = Pipe(); process.standardError = Pipe()
            try process.run()
            try pipe.fileHandleForWriting.write(contentsOf: Data(#"{"hook_event_name":"pre_llm_call","session_id":"fixture-session","cwd":"/tmp","extra":{"turn_id":"fixture-turn"}}"#.utf8))
            try pipe.fileHandleForWriting.close(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
        }.value
        let event = try #require(try await consumer.value)
        coordinator.observeDesktopConnectionEvent(event)
        #expect(try String(contentsOf: receipt, encoding: .utf8).contains("eventReceived"))
        intent.firstLaunchCompleted = true
        await coordinator.runStartupSetup {
            #expect(!OnboardingPresentationStore(defaults: try! config.isolatedPreferences()).claimAutomaticPresentation(migrationReady: intent.migrationVersion > 0, firstLaunchCompleted: intent.firstLaunchCompleted))
        }
        #expect(try String(contentsOf: manager.configURL, encoding: .utf8) == current)
        #expect(try FileManager.default.contentsOfDirectory(at: setup.supportURL.appendingPathComponent("connection-backups"), includingPropertiesForKeys: nil).count == 1)
        coordinator.cancelSourceSetupHermes()
        #expect(intent.intent(for: .hermes) == .uninstalled && !coordinator.shouldAutoInstall(.hermes))
    }
    @Test func missingSourceAndCancelledIntentNeverConfigureOrBorrowLegacyWelcome() async throws {
        let f = try SourceSetupFixture(); defer { f.cleanup() }; try f.helper()
        let config = try f.configuration(), setup = try #require(config.sourceSetup), intent = AgentIntentStore(defaults: try config.isolatedPreferences())
        intent.setIntent(.uninstalled, for: .hermes)
        let coordinator = HookInstallationCoordinator(intentStore: intent, isRuntimeAcceptance: true, sourceSetupAcceptance: setup,
            installationDetector: AgentInstallationDetector(executableDirectories: [], applicationDirectories: [], home: f.root),
            hermesInstallationManager: HermesHookInstallationManager(profileDirectory: f.root.appendingPathComponent("absent")))
        await coordinator.runStartupSetup { #expect(intent.migrationVersion > 0 && !intent.firstLaunchCompleted) }
        #expect(coordinator.hermesHookStatus == nil && coordinator.automaticConnectionErrors.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("absent").path))
        #expect(intent.intent(for: .hermes) == .uninstalled)
        let executables = f.root.appendingPathComponent("later-installed")
        try FileManager.default.createDirectory(at: executables, withIntermediateDirectories: true)
        let executable = executables.appendingPathComponent("hermes")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let second = HookInstallationCoordinator(intentStore: intent, isRuntimeAcceptance: true, sourceSetupAcceptance: setup,
            installationDetector: AgentInstallationDetector(executableDirectories: [executables], applicationDirectories: [], home: f.root),
            hermesInstallationManager: HermesHookInstallationManager(profileDirectory: f.root.appendingPathComponent("absent")))
        await second.runStartupSetup {}
        #expect(second.detectedInstallations[.hermes] != nil && !second.shouldAutoInstall(.hermes))
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("absent").path))
        #expect(try String(contentsOf: setup.supportURL.appendingPathComponent("source-setup-receipts.jsonl"), encoding: .utf8).contains("cancelled"))
    }
}
