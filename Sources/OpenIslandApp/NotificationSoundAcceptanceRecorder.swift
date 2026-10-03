import Darwin
import Foundation
import OpenIslandCore

/// Opted-in local acceptance bundles only. Records an automatic playback
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
        guard let config = try? RuntimeAcceptanceConfiguration.current() else { return }
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
}
