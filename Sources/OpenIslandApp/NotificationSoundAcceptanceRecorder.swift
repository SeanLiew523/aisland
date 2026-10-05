import Darwin
import Foundation
import OpenIslandCore

/// Opted-in local verification only. Records an automatic playback
/// result, never a source message, filename, audio sample or session identity.
enum NotificationSoundAcceptanceRecorder {
    private struct Receipt: Encodable {
        let category: NotificationSoundCategory
        let timestamp: TimeInterval
        let muted: Bool
        let started: Bool
        let customAudioPlaying: Bool
        let duration: TimeInterval?
        let limit: TimeInterval?
    }

    static func record(category: NotificationSoundCategory, muted: Bool = false,
                       started: Bool = false, customAudioPlaying: Bool = false,
                       duration: TimeInterval? = nil, limit: TimeInterval? = nil) {
        let config: RuntimeAcceptanceConfiguration?
        do { config = try RuntimeAcceptanceConfiguration.current() } catch { return }
        guard let config else {
            recordNormalVerification(category: category, muted: muted, started: started,
                                     customAudioPlaying: customAudioPlaying, duration: duration, limit: limit,
                                     directory: FileManager.default.homeDirectoryForCurrentUser
                                        .appendingPathComponent("Library/Application Support/OpenIsland", isDirectory: true))
            return
        }
        let directory = config.socketURL.deletingLastPathComponent()
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil,
              let resolved = realpath(directory.path, nil) else { return }
        defer { free(resolved) }
        guard String(cString: resolved) == directory.path else { return }
        let url = directory.appendingPathComponent("sound-receipts.jsonl")
        let value = Receipt(category: category, timestamp: Date().timeIntervalSince1970,
                            muted: muted, started: started, customAudioPlaying: customAudioPlaying,
                            duration: duration, limit: limit)
        guard var data = try? JSONEncoder().encode(value) else { return }
        data.append(0x0a)
        let fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { return }
        defer { close(fd) }
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return }
                offset += count
            }
        }
    }

    /// Internal injection seam for isolated filesystem fixtures. The app always
    /// supplies the fixed normal directory above; no preference or environment gate.
    static func recordNormalVerification(category: NotificationSoundCategory, muted: Bool = false,
                                         started: Bool = false, customAudioPlaying: Bool = false,
                                         duration: TimeInterval? = nil, limit: TimeInterval? = nil,
                                         directory: URL, ownerUID: uid_t = getuid()) {
        let directoryFD = openCanonicalDirectory(directory, ownerUID: ownerUID)
        guard directoryFD >= 0 else { return }
        defer { close(directoryFD) }
        let markerFD = openat(directoryFD, ".sound-verification-enabled", O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard markerFD >= 0 else { return }
        defer { close(markerFD) }
        guard validFile(markerFD, ownerUID: ownerUID, empty: true) else { return }
        let receipt = Receipt(category: category, timestamp: Date().timeIntervalSince1970,
                              muted: muted, started: started, customAudioPlaying: customAudioPlaying,
                              duration: duration, limit: limit)
        guard var data = try? JSONEncoder().encode(receipt) else { return }
        data.append(0x0a)
        let filename = "notification-sound-verification.jsonl"
        var fd = openat(directoryFD, filename, O_WRONLY | O_APPEND | O_NOFOLLOW | O_NONBLOCK)
        if fd < 0 && errno == ENOENT {
            fd = openat(directoryFD, filename, O_WRONLY | O_CREAT | O_EXCL | O_APPEND | O_NOFOLLOW | O_NONBLOCK, 0o600)
        }
        guard fd >= 0 else { return }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return }
        defer { flock(fd, LOCK_UN) }
        var info = stat()
        guard validFile(fd, ownerUID: ownerUID),
              validFile(markerFD, ownerUID: ownerUID, empty: true),
              fstat(fd, &info) == 0, info.st_size >= 0,
              info.st_size <= 65_536 - data.count else { return }
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return }
                offset += count
            }
        }
    }

    private static func validFile(_ fd: Int32, ownerUID: uid_t, empty: Bool = false) -> Bool {
        var info = stat()
        return fstat(fd, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
            && info.st_uid == ownerUID && info.st_nlink == 1
            && (info.st_mode & 0o7777) == 0o600 && (!empty || info.st_size == 0)
    }

    /// Walk through held directory descriptors so no ancestor can redirect an
    /// open. Missing directories are never created by this optional recorder.
    private static func openCanonicalDirectory(_ url: URL, ownerUID: uid_t) -> Int32 {
        let path = url.path
        guard url.isFileURL, path.hasPrefix("/") else { return -1 }
        guard let resolved = realpath(path, nil) else { return -1 }
        defer { free(resolved) }
        guard String(cString: resolved) == path else { return -1 }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { return -1 }
        for component in path.split(separator: "/") {
            let next = openat(fd, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            close(fd)
            guard next >= 0 else { return -1 }
            fd = next
            var info = stat()
            guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
                  info.st_uid == 0 || info.st_uid == ownerUID else { close(fd); return -1 }
        }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == ownerUID else { close(fd); return -1 }
        return fd
    }
}
