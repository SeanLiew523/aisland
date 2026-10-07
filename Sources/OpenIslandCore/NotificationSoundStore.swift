import Foundation
import AVFoundation
import AudioToolbox

public enum NotificationSoundCategory: String, CaseIterable, Codable, Sendable {
    case completed, approval, answer
}

public enum NotificationSoundPlaybackMode: String, CaseIterable, Codable, Sendable {
    case shortFade, full
}

public struct ManagedNotificationSound: Codable, Equatable, Sendable {
    public let filename: String
    public let displayName: String
    public let duration: TimeInterval
}

public enum NotificationSoundSelection: Codable, Equatable, Sendable {
    case system(name: String)
    case custom(ManagedNotificationSound)
}

public struct NotificationSoundResolution: Sendable {
    public let selection: NotificationSoundSelection
    public let fileURL: URL?
    public let usedFallback: Bool
}

public enum NotificationSoundImportError: Error, LocalizedError {
    case notMP3, tooLarge, invalidAudio, unsafeDirectory

    public var errorDescription: String? {
        switch self {
        case .notMP3: "Choose an MP3 audio file."
        case .tooLarge: "The MP3 must be no larger than 20 MB."
        case .invalidAudio: "The MP3 cannot be decoded or has no audio."
        case .unsafeDirectory: "The managed sound directory is unavailable."
        }
    }
}

/// Owns copies of imported audio. A failed import never changes the selected sound.
/// Inject defaults and a directory in tests; this type does not read other app preferences.
public final class NotificationSoundStore {
    public static let defaultSoundName = "Bottle"
    public static let maximumImportBytes = 20 * 1024 * 1024
    private let defaults: UserDefaults
    public let directory: URL
    private let validate: (URL) throws -> TimeInterval
    private let fm = FileManager.default
    private static let legacyKey = "notification.sound.name"
    private static let modeKey = "notification.sound.playbackMode"

    public init(defaults: UserDefaults, directory: URL,
                validate: @escaping (URL) throws -> TimeInterval = NotificationSoundStore.validateMP3) {
        self.defaults = defaults
        self.directory = directory.standardizedFileURL
        self.validate = validate
        let legacy = defaults.string(forKey: Self.legacyKey) ?? Self.defaultSoundName
        for category in NotificationSoundCategory.allCases where defaults.data(forKey: key(category)) == nil {
            persist(.system(name: legacy), for: category)
        }
    }

    public var playbackMode: NotificationSoundPlaybackMode {
        get { NotificationSoundPlaybackMode(rawValue: defaults.string(forKey: Self.modeKey) ?? "") ?? .shortFade }
        set { defaults.set(newValue.rawValue, forKey: Self.modeKey) }
    }

    public func selection(for category: NotificationSoundCategory) -> NotificationSoundSelection {
        guard let data = defaults.data(forKey: key(category)),
              let selection = try? JSONDecoder().decode(NotificationSoundSelection.self, from: data) else {
            return .system(name: Self.defaultSoundName)
        }
        return selection
    }

    public func resolve(_ category: NotificationSoundCategory) -> NotificationSoundResolution {
        let selection = selection(for: category)
        switch selection {
        case .system:
            return NotificationSoundResolution(selection: selection, fileURL: nil, usedFallback: false)
        case .custom(let asset):
            if let url = managedURL(asset.filename), (try? validate(url)) != nil {
                return NotificationSoundResolution(selection: selection, fileURL: url, usedFallback: false)
            }
            // Retain the selected metadata so Settings can explain the fallback and offer replacement.
            return NotificationSoundResolution(selection: .system(name: Self.defaultSoundName), fileURL: nil, usedFallback: true)
        }
    }

    @discardableResult
    public func importMP3(from source: URL, for category: NotificationSoundCategory) throws -> ManagedNotificationSound {
        guard source.pathExtension.lowercased() == "mp3" else { throw NotificationSoundImportError.notMP3 }
        try ensureDirectory()
        try checkSize(source)
        let filename = UUID().uuidString + ".mp3"
        let staged = directory.appendingPathComponent(".\(filename).importing")
        let final = directory.appendingPathComponent(filename)
        defer { try? fm.removeItem(at: staged) }
        try fm.copyItem(at: source, to: staged)
        try checkSize(staged)
        let duration = try validate(staged)
        guard duration.isFinite, duration > 0 else { throw NotificationSoundImportError.invalidAudio }
        let asset = ManagedNotificationSound(filename: filename, displayName: source.lastPathComponent, duration: duration)
        let previous = selection(for: category)
        // Rename inside the same directory is atomic. Commit the setting only after this succeeds.
        try fm.moveItem(at: staged, to: final)
        persist(.custom(asset), for: category)
        removeUnreferenced(previous)
        return asset
    }

    public func selectSystem(_ name: String, for category: NotificationSoundCategory) {
        let previous = selection(for: category)
        persist(.system(name: name), for: category)
        removeUnreferenced(previous)
    }

    public func restoreDefault(for category: NotificationSoundCategory) {
        selectSystem(Self.defaultSoundName, for: category)
    }

    private func key(_ category: NotificationSoundCategory) -> String { "notification.sound.category.\(category.rawValue)" }

    private func persist(_ selection: NotificationSoundSelection, for category: NotificationSoundCategory) {
        if let data = try? JSONEncoder().encode(selection) { defaults.set(data, forKey: key(category)) }
    }

    private func ensureDirectory() throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw NotificationSoundImportError.unsafeDirectory
        }
    }

    private func checkSize(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw NotificationSoundImportError.invalidAudio }
        guard let size = values.fileSize, size <= Self.maximumImportBytes else { throw NotificationSoundImportError.tooLarge }
    }

    private func managedURL(_ filename: String) -> URL? {
        guard filename.hasSuffix(".mp3"), UUID(uuidString: String(filename.dropLast(4))) != nil,
              filename == URL(fileURLWithPath: filename).lastPathComponent,
              let root = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              root.isDirectory == true, root.isSymbolicLink != true else { return nil }
        let url = directory.appendingPathComponent(filename)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
        return url
    }

    private func removeUnreferenced(_ previous: NotificationSoundSelection) {
        guard case .custom(let asset) = previous,
              !NotificationSoundCategory.allCases.contains(where: {
                  if case .custom(let selected) = selection(for: $0) {
                      return selected.filename.caseInsensitiveCompare(asset.filename) == .orderedSame
                  }
                  return false
              }),
              let url = managedURL(asset.filename) else { return }
        try? fm.removeItem(at: url)
    }

    /// Check the container type as well as actual decoded PCM; a renamed WAV is not an MP3.
    public static func validateMP3(_ url: URL) throws -> TimeInterval {
        var file: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr, let file else {
            throw NotificationSoundImportError.invalidAudio
        }
        defer { AudioFileClose(file) }
        var type: AudioFileTypeID = 0
        var size = UInt32(MemoryLayout<AudioFileTypeID>.size)
        guard AudioFileGetProperty(file, kAudioFilePropertyFileFormat, &size, &type) == noErr,
              type == kAudioFileMP3Type else { throw NotificationSoundImportError.notMP3 }
        do {
            let audio = try AVAudioFile(forReading: url)
            let duration = Double(audio.length) / audio.processingFormat.sampleRate
            guard audio.length > 0, duration.isFinite, duration > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 4096) else {
                throw NotificationSoundImportError.invalidAudio
            }
            try audio.read(into: buffer)
            guard buffer.frameLength > 0 else { throw NotificationSoundImportError.invalidAudio }
            // Decode the end too, without processing arbitrarily long audio on the UI thread.
            audio.framePosition = max(0, audio.length - 4096)
            try audio.read(into: buffer)
            guard buffer.frameLength > 0 else { throw NotificationSoundImportError.invalidAudio }
            return duration
        } catch {
            throw NotificationSoundImportError.invalidAudio
        }
    }
}
