import Foundation
import Testing
import Darwin
@testable import OpenIslandCore

struct DesktopConnectionInstallationTests {
    @Test func configurationTimeoutStopsOnlyItsOwnSpawnedFamily() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aisland-process-fixture-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appendingPathComponent("fixture")
        let pidFile = root.appendingPathComponent("child.pid")
        try Data("#!/bin/sh\n/bin/sleep 30 &\necho $! > \"$1\"\nwait\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        do {
            _ = try ConnectionProcessRunner.run(URL(fileURLWithPath: "/bin/sh"), arguments: [script.path, pidFile.path], environment: ["PATH": "/usr/bin:/bin"], timeout: 1)
            Issue.record("Synthetic configuration process unexpectedly completed")
        } catch ConnectionProcessRunner.Failure.timedOut {
            // A genuine timeout, rather than an executable startup failure.
        }
        let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        while MiniMaxCodeActiveDataDirectory.snapshot(pid) != nil && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.01) }
        #expect(MiniMaxCodeActiveDataDirectory.snapshot(pid) == nil)
        #expect(MiniMaxCodeActiveDataDirectory.snapshot(ProcessInfo.processInfo.processIdentifier) != nil)
    }
    @Test func activeDirectoryRequiresOneExactOpenDatabasePath() {
        #expect(MiniMaxCodeActiveDataDirectory.uniqueDirectory(lsofMetadata: "p42\nn/ignored/auth.json\nn/source/v2/sqlite/runtime-state.sqlite\nn/source/v2/sqlite/runtime-state.sqlite")?.path == "/source")
        #expect(MiniMaxCodeActiveDataDirectory.uniqueDirectory(lsofMetadata: "n/a/v2/sqlite/runtime-state.sqlite\nn/b/v2/sqlite/runtime-state.sqlite") == nil)
        #expect(MiniMaxCodeActiveDataDirectory.uniqueDirectory(lsofMetadata: "n/a/v2/sqlite/runtime-state.sqlite-wal\nn/a/v2/sqlite/runtime-state.sqlite (deleted)") == nil)
        #expect(MiniMaxCodeActiveDataDirectory.uniqueDirectory(lsofMetadata: "n/a/../b/v2/sqlite/runtime-state.sqlite") == nil)
    }
    @Test func descendantIdentityExcludesSiblingsAndEarlierProcesses() {
        typealias P = MiniMaxCodeActiveDataDirectory.ProcessIdentity
        let root = P(pid: 30, parentPID: 1, executablePath: "/App/Contents/main", startedAt: 100)
        let child = P(pid: 31, parentPID: 30, executablePath: "/App/Contents/helper", startedAt: 101)
        let nested = P(pid: 32, parentPID: 31, executablePath: "/App/Contents/utility", startedAt: 102)
        let sibling = P(pid: 33, parentPID: 1, executablePath: "/App/Contents/main", startedAt: 103)
        let reused = P(pid: 34, parentPID: 30, executablePath: "/App/Contents/main", startedAt: 99)
        #expect(MiniMaxCodeActiveDataDirectory.descendantProcesses(root: root, candidates: [root, child, nested, sibling, reused]) == [root, child, nested])
    }
    @Test func deepSeekWaitsWithoutMutationThenUsesFixedOfficialCommandAndIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aisland-desktop-fixture-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let packages = root.appendingPathComponent("packages")
        let profile = root.appendingPathComponent(".dsh/profiles/desktop")
        let source = root.appendingPathComponent("Source.app")
        let cli = source.appendingPathComponent("Contents/Resources/runtime/cli/bin/dsh")
        let executable = source.appendingPathComponent("Contents/MacOS/Fixture")
        try FileManager.default.createDirectory(at: cli.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        try FileManager.default.createDirectory(at: packages.appendingPathComponent("DeepSeek/scripts"), withIntermediateDirectories: true)
        for name in ["package.json", "core.mjs", "index.mjs", "client.js", "cordis.patch.yml", "scripts/connection-patch.cjs"] {
            try Data((name == "package.json" ? "{\"name\":\"@aisland/deepseek-harness-plugin\"}" : "fixture public plugin").utf8).write(to: packages.appendingPathComponent("DeepSeek/" + name))
        }
        let box = Calls()
        let manager = DesktopConnectionInstallationManager(home: root, supportDirectory: root.appendingPathComponent("support"), packagesDirectory: packages, nodeURL: nil) { url, arguments, environment in
            box.record(url: url, arguments: arguments)
            #expect(environment["DSH_HOME"] == root.appendingPathComponent(".dsh").path)
            if url == cli {
                #expect(arguments.prefix(4) == ["plugin", "--profile", "desktop", "add"])
                try JSONSerialization.data(withJSONObject: ["dependencies": ["unrelated": "keep", "@aisland/deepseek-harness-plugin": "link:" + arguments[4]]]).write(to: profile.appendingPathComponent("package.json"))
                return Data()
            }
            #expect(url == executable)
            #expect(arguments[0] == "--expose-internals")
            #expect(environment["ELECTRON_RUN_AS_NODE"] == "1")
            return Data("{\"isCurrent\":true}".utf8)
        }
        let evidence = AgentInstallationDetector.Evidence(executableURL: executable, bundleURL: source, version: "0.2.0-rc.2")
        #expect(try manager.configureDeepSeek(evidence: evidence, sourceRunning: false) == .waitingForProfile)
        #expect(box.count == 0)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let original = Data("{\"dependencies\":{\"unrelated\":\"keep\"}}".utf8)
        try original.write(to: profile.appendingPathComponent("package.json"))
        #expect(try manager.configureDeepSeek(evidence: evidence, sourceRunning: true) == .waitingForSourceExit)
        #expect(box.count == 0)
        #expect(try Data(contentsOf: profile.appendingPathComponent("package.json")) == original)
        #expect(try manager.configureDeepSeek(evidence: evidence, sourceRunning: false) == .waitingForActivation)
        #expect(box.count == 2)
        #expect(try manager.configureDeepSeek(evidence: evidence, sourceRunning: true) == .waitingForActivation)
        #expect(box.count == 3) // only read-only exact owned patch status, never plugin add
        let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: profile.appendingPathComponent("package.json"))) as? [String: Any])
        #expect((manifest["dependencies"] as? [String: String])?["unrelated"] == "keep")
        try Data("foreign change".utf8).write(to: root.appendingPathComponent("support/deepseek-passive/package/core.mjs"))
        #expect(throws: DesktopConnectionInstallationManager.Failure.unownedInstallation) { try manager.configureDeepSeek(evidence: evidence, sourceRunning: false) }
    }
    @Test func unsupportedVersionAndUnknownActiveDirectoryNeverInvokeInstaller() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("unused-\(UUID())")
        let box = Calls()
        let manager = DesktopConnectionInstallationManager(home: root, packagesDirectory: root, nodeURL: nil) { url, args, _ in box.record(url: url, arguments: args); return Data() }
        var evidence = AgentInstallationDetector.Evidence(executableURL: root, bundleURL: root.appendingPathComponent("Source.app"), version: "3.1.0")
        #expect(try manager.configureMiniMax(evidence: evidence, activeDataDirectory: nil) == .waitingForProfile)
        evidence.version = "3.2.0"
        #expect(throws: DesktopConnectionInstallationManager.Failure.unsupportedVersion) { try manager.configureMiniMax(evidence: evidence, activeDataDirectory: root) }
        #expect(box.count == 0)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [(URL, [String])] = []
        var count: Int { lock.withLock { values.count } }
        func record(url: URL, arguments: [String]) { lock.withLock { values.append((url, arguments)) } }
    }
}
