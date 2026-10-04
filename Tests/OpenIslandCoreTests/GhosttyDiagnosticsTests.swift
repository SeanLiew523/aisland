import Darwin
import Foundation
import Testing
@testable import OpenIslandCore

struct GhosttyDiagnosticsTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ghostty-diagnostic-fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return url
    }
    private func enable(_ directory: URL, mode: Int = 0o600, data: Data = Data()) throws {
        let marker = directory.appendingPathComponent(GhosttyDiagnostics.markerName)
        try data.write(to: marker)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: marker.path)
    }
    @Test func markerAndLogAdmissionArePrivateBoundedAndFailClosed() throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent(GhosttyDiagnostics.logName)
        let event = GhosttyDiagnosticEvent(stage: "binding", agent: "claude", event: "startup", reason: "missingTTY", nativeID: "private-native", flags: ["hasRealTTY": false])
        GhosttyDiagnostics.write(event, directory: directory)
        #expect(!FileManager.default.fileExists(atPath: log.path))
        try enable(directory, mode: 0o644)
        GhosttyDiagnostics.write(event, directory: directory)
        #expect(!FileManager.default.fileExists(atPath: log.path))
        try enable(directory, data: Data([1]))
        GhosttyDiagnostics.write(event, directory: directory)
        #expect(!FileManager.default.fileExists(atPath: log.path))
        try enable(directory)
        GhosttyDiagnostics.write(event, directory: directory)
        let text = try String(contentsOf: log, encoding: .utf8)
        #expect(text.contains("missingTTY")); #expect(!text.contains("private-native"))
        #expect((try FileManager.default.attributesOfItem(atPath: log.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try Data(repeating: 32, count: GhosttyDiagnostics.maximumBytes).write(to: log)
        GhosttyDiagnostics.write(event, directory: directory)
        #expect(try Data(contentsOf: log).count == GhosttyDiagnostics.maximumBytes)
    }
    @Test func symlinksAndBusyLocksNeverWriteThrough() throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("fixture")
        try Data().write(to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        let marker = directory.appendingPathComponent(GhosttyDiagnostics.markerName)
        try FileManager.default.createSymbolicLink(at: marker, withDestinationURL: destination)
        let event = GhosttyDiagnosticEvent(stage: "locator", reason: "timeout")
        GhosttyDiagnostics.write(event, directory: directory)
        let log = directory.appendingPathComponent(GhosttyDiagnostics.logName)
        #expect(!FileManager.default.fileExists(atPath: log.path))
        try FileManager.default.removeItem(at: marker); try enable(directory)
        try FileManager.default.createSymbolicLink(at: log, withDestinationURL: destination)
        GhosttyDiagnostics.write(event, directory: directory)
        #expect(try Data(contentsOf: destination).isEmpty)
        try FileManager.default.removeItem(at: log)
        try Data().write(to: directory.appendingPathComponent(".ghostty-diagnostics.lock"))
        GhosttyDiagnostics.write(event, directory: directory)
        #expect(!FileManager.default.fileExists(atPath: log.path))
    }
    @Test func foreignOwnerAndNonRegularMetadataAreRejected() {
        var info = stat(); info.st_uid = getuid(); info.st_mode = mode_t(S_IFREG | 0o600); info.st_nlink = 1
        #expect(GhosttyDiagnostics.isSafeFile(info, empty: true))
        #expect(!GhosttyDiagnostics.isSafeFile(info, empty: true, userID: getuid() + 1))
        info.st_mode = mode_t(S_IFIFO | 0o600)
        #expect(!GhosttyDiagnostics.isSafeFile(info, empty: true))
    }
    @Test func fieldsAndHashHaveAClosedSchema() {
        let event = GhosttyDiagnosticEvent(stage: "private stage", agent: "private agent", event: "private prompt", reason: "private stderr", nativeID: "abc", surfaceID: "abc", flags: ["hasUI": true, "prompt": true], counts: ["surfaceCount": 500, "argv": 1])
        #expect(event.values["reason"] == "other")
        #expect(event.values["nativeIDHash"] == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(event.values["surfaceIDHash"] == event.values["nativeIDHash"])
        #expect(event.flags == ["hasUI": true]); #expect(event.counts == ["surfaceCount": 256])
        #expect(!String(describing: event).contains("private"))
    }
    @Test func bindingReasonsDistinguishMissingTTYAmbiguityAndReceiptReuse() throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        var events: [GhosttyDiagnosticEvent] = []; var reads = 0
        let store = GhosttySourceBindingStore(directory: directory, snapshotProvider: {
            reads += 1
            return .init(frontmostBefore: true, frontmostAfter: true, focusedBefore: "owned", focusedAfter: "owned", surfaces: [.init(id: "owned", cwd: "/tmp/shared", title: "private"), .init(id: "other", cwd: "/tmp/shared", title: "private")])
        }, diagnostic: { events.append($0) })
        #expect(store.resolve(agent: "claude", sessionID: "source", tty: nil, cwd: "/tmp/shared", event: .startup) == nil)
        #expect(events.last?.values["reason"] == "missingTTY"); #expect(reads == 0)
        #expect(store.resolve(agent: "claude", sessionID: "source", tty: "/dev/ttys001", cwd: "/tmp/shared", event: .startup) == nil)
        #expect(events.last?.values["reason"] == "ambiguousCWD")
        #expect(store.resolve(agent: "claude", sessionID: "source", tty: "/dev/ttys001", cwd: "/tmp/shared", event: .userSubmit)?.sessionID == "owned")
        #expect(events.last?.values["reason"] == "receiptWritten")
        let before = reads
        #expect(store.resolve(agent: "claude", sessionID: "source", tty: "/dev/ttys001", cwd: "/tmp/shared", event: .background)?.sessionID == "owned")
        #expect(events.last?.values["reason"] == "receiptHit"); #expect(reads == before)
        #expect(!String(describing: events).contains("/tmp/shared")); #expect(!String(describing: events).contains("private"))
    }
    @Test func locatorReasonsDoNotCaptureReturnedMetadataOrErrors() {
        var reason = ""
        #expect(GhosttySourceLocator.decodeDiagnosticOutput("diagnostic:notFrontmost", diagnostic: { reason = $0 }) == nil)
        #expect(reason == "notFrontmost")
        #expect(GhosttySourceLocator.decodeDiagnosticOutput("private stderr", diagnostic: { reason = $0 }) == nil)
        #expect(reason == "parseFailed")
        #expect(GhosttySourceLocator.decodeDiagnosticOutput("owned\nowned\u{1f}/tmp/private\u{1f}private title\n", diagnostic: { reason = $0 })?.focusedBefore == "owned")
        #expect(reason == "snapshotReady")
    }
}
