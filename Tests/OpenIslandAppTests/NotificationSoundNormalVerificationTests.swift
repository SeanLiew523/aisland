import Darwin
import Foundation
import OpenIslandCore
import Testing
@testable import OpenIslandApp

struct NotificationSoundNormalVerificationTests {
    private struct Fixture {
        let root: URL
        var marker: URL { root.appendingPathComponent(".sound-verification-enabled") }
        var log: URL { root.appendingPathComponent("notification-sound-verification.jsonl") }

        init() throws {
            root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
                .appendingPathComponent("sound-receipt-fixture-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        }

        func create(_ url: URL, data: Data = Data(), mode: mode_t = 0o600) throws {
            try data.write(to: url)
            #expect(chmod(url.path, mode) == 0)
        }

        func enable() throws { try create(marker) }
        func record(ownerUID: uid_t = getuid()) {
            NotificationSoundAcceptanceRecorder.recordNormalVerification(
                category: .approval, started: true, customAudioPlaying: true,
                duration: 8.5, limit: 5, directory: root, ownerUID: ownerUID)
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func missingDirectoryAndMissingMarkerHaveNoFilesystemSideEffects() throws {
        let f = try Fixture(); defer { f.remove() }
        f.record()
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.root.path).isEmpty)
        let absent = f.root.appendingPathComponent("absent/OpenIsland", isDirectory: true)
        NotificationSoundAcceptanceRecorder.recordNormalVerification(category: .completed, directory: absent)
        #expect(!FileManager.default.fileExists(atPath: absent.deletingLastPathComponent().path))
    }

    @Test func validMarkerWritesOnlyPlaybackFieldsAndPrivateRegularLog() throws {
        let f = try Fixture(); defer { f.remove() }
        try f.enable(); f.record()
        let data = try Data(contentsOf: f.log)
        #expect(data.last == 0x0a)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == Set(["category", "timestamp", "muted", "started", "customAudioPlaying", "duration", "limit"]))
        #expect(object["category"] as? String == "approval")
        #expect(object["started"] as? Bool == true)
        #expect(object["customAudioPlaying"] as? Bool == true)
        #expect(object["duration"] as? Double == 8.5)
        #expect(object["limit"] as? Double == 5)
        var info = stat()
        #expect(lstat(f.log.path, &info) == 0)
        #expect(info.st_uid == getuid() && info.st_nlink == 1)
        #expect((info.st_mode & S_IFMT) == S_IFREG && (info.st_mode & 0o7777) == 0o600)
        #expect(try Data(contentsOf: f.marker).isEmpty)
    }

    @Test func removedMarkerStopsFurtherReceipts() throws {
        let f = try Fixture(); defer { f.remove() }
        try f.enable(); f.record()
        let before = try Data(contentsOf: f.log)
        try FileManager.default.removeItem(at: f.marker)
        f.record()
        #expect(try Data(contentsOf: f.log) == before)
        #expect(!FileManager.default.fileExists(atPath: f.marker.path))
    }

    @Test func nonemptyAndOversizeMarkersAreRejectedWithoutMutation() throws {
        for data in [Data([1]), Data(repeating: 1, count: 65_537)] {
            let f = try Fixture(); defer { f.remove() }
            try f.create(f.marker, data: data)
            f.record()
            #expect(!FileManager.default.fileExists(atPath: f.log.path))
            #expect(try Data(contentsOf: f.marker) == data)
        }
    }

    @Test func markerPermissionsAndSpecialModesAreRejectedWithoutRepair() throws {
        for mode: mode_t in [0o400, 0o644, 0o666, 0o1600] {
            let f = try Fixture(); defer { f.remove() }
            try f.create(f.marker, mode: mode)
            f.record()
            #expect(!FileManager.default.fileExists(atPath: f.log.path))
            var info = stat(); #expect(lstat(f.marker.path, &info) == 0)
            #expect((info.st_mode & 0o7777) == mode)
        }
    }

    @Test func markerSymlinkDirectoryAndFIFOAreRejected() throws {
        for kind in 0..<3 {
            let f = try Fixture(); defer { f.remove() }
            let target = f.root.appendingPathComponent("target")
            try f.create(target)
            switch kind {
            case 0: try FileManager.default.createSymbolicLink(at: f.marker, withDestinationURL: target)
            case 1: try FileManager.default.createDirectory(at: f.marker, withIntermediateDirectories: false)
            default: #expect(mkfifo(f.marker.path, 0o600) == 0)
            }
            f.record()
            #expect(!FileManager.default.fileExists(atPath: f.log.path))
            #expect(try Data(contentsOf: target).isEmpty)
            var info = stat(); #expect(lstat(f.marker.path, &info) == 0)
            #expect((info.st_mode & S_IFMT) == [S_IFLNK, S_IFDIR, S_IFIFO][kind])
        }
    }

    @Test func hardlinkedMarkerIsRejected() throws {
        let f = try Fixture(); defer { f.remove() }
        try f.enable()
        let alias = f.root.appendingPathComponent("marker-alias")
        #expect(link(f.marker.path, alias.path) == 0)
        f.record()
        #expect(!FileManager.default.fileExists(atPath: f.log.path))
        #expect(try Data(contentsOf: alias).isEmpty)
    }

    @Test func foreignOwnerUIDIsRejected() throws {
        let f = try Fixture(); defer { f.remove() }
        try f.enable(); f.record(ownerUID: getuid() + 1)
        #expect(!FileManager.default.fileExists(atPath: f.log.path))
        #expect(try Data(contentsOf: f.marker).isEmpty)
    }

    @Test func logPermissionsAndHardlinksAreRejectedWithoutMutation() throws {
        for mode: mode_t in [0o400, 0o644, 0o1600, 0o600] {
            let f = try Fixture(); defer { f.remove() }
            try f.enable()
            let original = Data("existing fixture\n".utf8)
            try f.create(f.log, data: original, mode: mode)
            if mode == 0o600 { #expect(link(f.log.path, f.root.appendingPathComponent("log-alias").path) == 0) }
            f.record()
            #expect(try Data(contentsOf: f.log) == original)
            var info = stat(); #expect(lstat(f.log.path, &info) == 0)
            #expect((info.st_mode & 0o7777) == mode)
        }
    }

    @Test func logSymlinkDirectoryAndFIFOAreRejected() throws {
        for kind in 0..<3 {
            let f = try Fixture(); defer { f.remove() }
            try f.enable()
            let target = f.root.appendingPathComponent("target")
            let original = Data("target fixture".utf8)
            try f.create(target, data: original)
            switch kind {
            case 0: try FileManager.default.createSymbolicLink(at: f.log, withDestinationURL: target)
            case 1: try FileManager.default.createDirectory(at: f.log, withIntermediateDirectories: false)
            default: #expect(mkfifo(f.log.path, 0o600) == 0)
            }
            f.record()
            #expect(try Data(contentsOf: target) == original)
            var info = stat(); #expect(lstat(f.log.path, &info) == 0)
            #expect((info.st_mode & S_IFMT) == [S_IFLNK, S_IFDIR, S_IFIFO][kind])
        }
    }

    @Test func redirectedParentAndDirectoryAreRejected() throws {
        let f = try Fixture(); defer { f.remove() }
        try f.enable()
        let alias = f.root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: f.root)
        for directory in [alias, alias.appendingPathComponent("alias")] {
            NotificationSoundAcceptanceRecorder.recordNormalVerification(category: .answer, directory: directory)
        }
        #expect(!FileManager.default.fileExists(atPath: f.log.path))
    }

    @Test func fullOversizeAndInsufficientSpaceLogsAreRejectedWithoutTruncation() throws {
        for size in [65_536, 65_537, 65_535] {
            let f = try Fixture(); defer { f.remove() }
            try f.enable()
            let original = Data(repeating: 0x20, count: size)
            try f.create(f.log, data: original)
            f.record()
            #expect(try Data(contentsOf: f.log) == original)
        }
    }

    @Test func repeatedReceiptsStayBoundedAndComplete() throws {
        let f = try Fixture(); defer { f.remove() }
        try f.enable()
        for _ in 0..<600 { f.record() }
        let data = try Data(contentsOf: f.log)
        #expect(data.count <= 65_536 && data.count > 65_000)
        #expect(data.last == 0x0a)
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        #expect(!lines.isEmpty)
        for line in lines { #expect(throws: Never.self) { _ = try JSONSerialization.jsonObject(with: Data(line.utf8)) } }
    }
}
