import Darwin
import Foundation
import Testing
@testable import OpenIslandApp

struct MiniMaxCodeCopyDiagnosticsTests {
    private struct Fixture {
        let root: URL
        var marker: URL { root.appendingPathComponent(MiniMaxCodeCopyDiagnosticRecorder.markerName) }
        var log: URL { root.appendingPathComponent(MiniMaxCodeCopyDiagnosticRecorder.logName) }
        init() throws {
            root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
                .appendingPathComponent("minimax-copy-diagnostic-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        }
        func create(_ url: URL, data: Data = Data(), mode: mode_t = 0o600) throws {
            try data.write(to: url)
            #expect(chmod(url.path, mode) == 0)
        }
        func record(ownerUID: uid_t = getuid()) {
            MiniMaxCodeCopyDiagnosticRecorder.record(.init(), directory: root, ownerUID: ownerUID)
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
    @Test func disabledRecorderDoesNotCreateFilesOrDirectories() throws {
        let f = try Fixture(); defer { f.remove() }
        #expect(!MiniMaxCodeCopyDiagnosticRecorder.isEnabled(directory: f.root))
        f.record()
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.root.path).isEmpty)
        let absent = f.root.appendingPathComponent("absent")
        MiniMaxCodeCopyDiagnosticRecorder.record(.init(), directory: absent)
        #expect(!FileManager.default.fileExists(atPath: absent.path))
    }
    @Test func validOptInProducesOnlyFixedVocabularyAndPrivateBoundedFields() throws {
        let f = try Fixture(); defer { f.remove() }
        try f.create(f.marker)
        #expect(MiniMaxCodeCopyDiagnosticRecorder.isEnabled(directory: f.root))
        var diagnostic = MiniMaxCodeCopyDiagnostic()
        diagnostic.stage = .focus; diagnostic.reason = .copyFocusUnobserved
        diagnostic.focusedRole = "synthetic-secret-body-or-ID"
        diagnostic.focusPolls = Int.max; diagnostic.focusQueryError = Int.min
        diagnostic.searchCount = Int.max; diagnostic.searchNodes = -1
        MiniMaxCodeCopyDiagnosticRecorder.record(diagnostic, directory: f.root)
        let line = try String(contentsOf: f.log, encoding: .utf8)
        #expect(!line.contains("synthetic-secret"))
        #expect(line.contains("focusedRole=unavailable") && line.contains("focusPolls=60000"))
        #expect(line.contains("focusQueryError=-25220") && line.contains("stage=focus"))
        #expect(line.contains("searchCount=60000") && line.contains("searchNodes=0"))
        let keys = line.split(separator: " ").map { String($0.split(separator: "=", maxSplits: 1)[0]) }
        #expect(Set(keys) == Set(["timestamp", "stage", "reason", "cleanup", "searchCount", "searchNodes", "windowRaise", "windowRaiseSucceeded", "windowFocused", "windowFocusProof", "focusWindowMatches", "focusAncestorMatches", "focusPolls", "focusQueryError", "focusedRole", "focusEqual", "pointerMatches", "frontmost", "inputAvailable", "copied", "restored", "deadlineExpired", "entryBudgetMs", "elapsedMs"]))
        var info = stat(); #expect(lstat(f.log.path, &info) == 0)
        #expect(info.st_uid == getuid() && info.st_nlink == 1)
        #expect((info.st_mode & S_IFMT) == S_IFREG && (info.st_mode & 0o7777) == 0o600)
        #expect(try Data(contentsOf: f.marker).isEmpty)
    }
    @Test func badMarkerModeContentOrOwnerNeverEnablesOrMutates() throws {
        for mode: mode_t in [0o400, 0o644, 0o1600, 0o600] {
            let f = try Fixture(); defer { f.remove() }
            let data = mode == 0o600 ? Data([1]) : Data()
            try f.create(f.marker, data: data, mode: mode)
            #expect(!MiniMaxCodeCopyDiagnosticRecorder.isEnabled(directory: f.root))
            f.record()
            #expect(!FileManager.default.fileExists(atPath: f.log.path))
            #expect(try Data(contentsOf: f.marker) == data)
            var info = stat(); #expect(lstat(f.marker.path, &info) == 0)
            #expect((info.st_mode & 0o7777) == mode)
        }
        let f = try Fixture(); defer { f.remove() }
        try f.create(f.marker)
        #expect(!MiniMaxCodeCopyDiagnosticRecorder.isEnabled(directory: f.root, ownerUID: getuid() + 1))
        f.record(ownerUID: getuid() + 1)
        #expect(!FileManager.default.fileExists(atPath: f.log.path))
    }
    @Test func markerAndLogRejectSymlinkHardlinkDirectoryAndFIFO() throws {
        for markerTarget in [true, false] {
            for kind in 0..<4 {
                let f = try Fixture(); defer { f.remove() }
                if !markerTarget { try f.create(f.marker) }
                let file = markerTarget ? f.marker : f.log
                let target = f.root.appendingPathComponent("target")
                try f.create(target)
                switch kind {
                case 0: try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
                case 1: #expect(link(target.path, file.path) == 0)
                case 2: try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
                default: #expect(mkfifo(file.path, 0o600) == 0)
                }
                f.record()
                #expect(try Data(contentsOf: target).isEmpty)
                if markerTarget { #expect(!FileManager.default.fileExists(atPath: f.log.path)) }
            }
        }
    }
    @Test func badExistingLogPermissionsArePreserved() throws {
        for mode: mode_t in [0o400, 0o644, 0o1600] {
            let f = try Fixture(); defer { f.remove() }
            try f.create(f.marker)
            let original = Data("fixture\n".utf8)
            try f.create(f.log, data: original, mode: mode)
            f.record()
            #expect(try Data(contentsOf: f.log) == original)
            var info = stat(); #expect(lstat(f.log.path, &info) == 0)
            #expect((info.st_mode & 0o7777) == mode)
        }
    }
    @Test func redirectedDirectoryAndRemovedMarkerStopRecording() throws {
        let f = try Fixture(); defer { f.remove() }
        try f.create(f.marker)
        let alias = f.root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: f.root)
        #expect(!MiniMaxCodeCopyDiagnosticRecorder.isEnabled(directory: alias))
        MiniMaxCodeCopyDiagnosticRecorder.record(.init(), directory: alias)
        #expect(!FileManager.default.fileExists(atPath: f.log.path))
        f.record()
        let before = try Data(contentsOf: f.log)
        try FileManager.default.removeItem(at: f.marker)
        f.record()
        #expect(try Data(contentsOf: f.log) == before)
    }
    @Test func capacityAndConcurrentLockDoNotChangeLog() throws {
        for size in [65_536, 65_537, 65_535] {
            let f = try Fixture(); defer { f.remove() }
            try f.create(f.marker)
            let original = Data(repeating: 1, count: size)
            try f.create(f.log, data: original)
            f.record()
            #expect(try Data(contentsOf: f.log) == original)
        }
        let f = try Fixture(); defer { f.remove() }
        try f.create(f.marker); try f.create(f.log)
        let fd = open(f.log.path, O_WRONLY)
        #expect(fd >= 0); defer { close(fd) }
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
        f.record()
        #expect(try Data(contentsOf: f.log).isEmpty)
    }
    @Test func cleanupRequiresEveryOwnershipCondition() {
        func admitted(_ flags: [Bool]) -> Bool {
            MiniMaxCodeCopyCleanupAdmission.permits(openedByNavigation: flags[0], sameSource: flags[1],
                sameWindow: flags[2], frontmost: flags[3], focusBelongsToMenu: flags[4], hasTime: flags[5])
        }
        #expect(admitted(Array(repeating: true, count: 6)))
        for index in 0..<6 {
            var flags = Array(repeating: true, count: 6); flags[index] = false
            #expect(!admitted(flags))
        }
    }
    @Test func changedFocusDuringActionQuerySuppressesCancelAndNeverReactivates() {
        var sameFocus = true
        var cancellations = 0
        let result = MiniMaxCodeCopyCleanupAdmission.cancelIfCurrent(isCurrent: { sameFocus },
            supportsCancel: { sameFocus = false; return true }, cancel: { cancellations += 1; return true })
        #expect(result == .focusChanged && cancellations == 0)
        sameFocus = false
        var queries = 0
        #expect(MiniMaxCodeCopyCleanupAdmission.cancelIfCurrent(isCurrent: { sameFocus },
            supportsCancel: { queries += 1; return true }, cancel: { cancellations += 1; return true }) == .focusChanged)
        #expect(queries == 0 && cancellations == 0)
    }
    @Test func unsupportedAndFailedTargetedCancelAreReportedWithoutFallbackInput() {
        var cancellations = 0
        #expect(MiniMaxCodeCopyCleanupAdmission.cancelIfCurrent(isCurrent: { true },
            supportsCancel: { false }, cancel: { cancellations += 1; return true }) == .unsupported)
        #expect(cancellations == 0)
        #expect(MiniMaxCodeCopyCleanupAdmission.cancelIfCurrent(isCurrent: { true },
            supportsCancel: { true }, cancel: { cancellations += 1; return false }) == .attempted)
        #expect(cancellations == 1)
        #expect(MiniMaxCodeCopyCleanupAdmission.cancelIfCurrent(isCurrent: { true },
            supportsCancel: { true }, cancel: { cancellations += 1; return true }) == .dispatched)
        #expect(cancellations == 2)
    }

}
