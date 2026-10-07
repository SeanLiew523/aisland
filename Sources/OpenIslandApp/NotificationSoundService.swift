import AppKit
import AVFoundation
import OpenIslandCore

/// Category-specific sound settings and a single playback owner.
@MainActor
struct NotificationSoundService {
    private static let soundsDirectory = "/System/Library/Sounds"
    private static let defaultsKey = "notification.sound.name"
    static let defaultSoundName = NotificationSoundStore.defaultSoundName
    static let store: NotificationSoundStore = {
        do {
            if let acceptance = try RuntimeAcceptanceConfiguration.current() {
                return NotificationSoundStore(
                    defaults: try acceptance.isolatedPreferences(),
                    directory: acceptance.socketURL.deletingLastPathComponent()
                        .appendingPathComponent("NotificationSounds", isDirectory: true)
                )
            }
        } catch {
            // An invalid opted-in bundle must never import into production storage.
            fatalError("Invalid runtime acceptance sound configuration")
        }
        return NotificationSoundStore(
            defaults: .standard,
            directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("dev.aisland.app/NotificationSounds", isDirectory: true)
        )
    }()
    private static let playback = NotificationSoundPlayback()

    static func availableSounds() -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: soundsDirectory) else { return [] }
        return contents.filter { $0.hasSuffix(".aiff") }
            .map { ($0 as NSString).deletingPathExtension }.sorted()
    }

    /// Legacy callers retain their single-sound preference. New settings use `store`.
    static var selectedSoundName: String {
        get { UserDefaults.standard.string(forKey: defaultsKey) ?? defaultSoundName }
        set {
            guard newValue != selectedSoundName else { return }
            // Initialize/migrate first, then mirror a genuine legacy change to all categories.
            let existingStore = store
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
            for category in NotificationSoundCategory.allCases { existingStore.selectSystem(newValue, for: category) }
        }
    }

    static func stop() { playback.stop() }
    static func setMuted(_ muted: Bool) { playback.setMuted(muted) }

    @discardableResult
    static func play(_ name: String) -> Bool {
        stop()
        guard let player = systemPlayer(name) else { return false }
        return playback.play(player, fallback: { systemPlayer(defaultSoundName) })
    }

    /// Explicit previews ignore automatic-notification mute and play the full audio.
    @discardableResult
    static func preview(category: NotificationSoundCategory) -> Bool {
        stop()
        guard let player = player(for: category) else { return false }
        return playback.play(player, fallback: { systemPlayer(defaultSoundName) })
    }

    static func playNotification(category: NotificationSoundCategory, isMuted: Bool) {
        guard !isMuted else {
            NotificationSoundAcceptanceRecorder.record(category: category, muted: true)
            return
        }
        stop()
        guard let player = player(for: category) else { return }
        let limit: TimeInterval? = store.playbackMode == .shortFade ? 5 : nil
        let started = playback.play(player, limit: limit, fallback: { systemPlayer(defaultSoundName) })
        NotificationSoundAcceptanceRecorder.record(
            category: category, started: started,
            customAudioPlaying: (player as? MP3Player)?.audio.isPlaying ?? false,
            duration: player.duration, limit: limit
        )
    }

    static func playNotification(isMuted: Bool) {
        playNotification(category: .completed, isMuted: isMuted)
    }

    private static func player(for category: NotificationSoundCategory) -> (any NotificationSoundPlayer)? {
        let resolved = store.resolve(category)
        if let url = resolved.fileURL,
           let audio = try? AVAudioPlayer(contentsOf: url), audio.prepareToPlay() {
            return MP3Player(audio)
        }
        if case .system(let name) = resolved.selection { return systemPlayer(name) }
        return systemPlayer(defaultSoundName)
    }

    private static func systemPlayer(_ name: String) -> SystemPlayer? {
        let selectedName = availableSounds().contains(name) ? name : defaultSoundName
        let url = URL(fileURLWithPath: soundsDirectory).appendingPathComponent("\(selectedName).aiff")
        guard let sound = NSSound(contentsOf: url, byReference: false) else { return nil }
        return SystemPlayer(sound)
    }
}

@MainActor
private final class MP3Player: NSObject, NotificationSoundPlayer, AVAudioPlayerDelegate {
    let audio: AVAudioPlayer
    var failureHandler: (@MainActor () -> Void)?
    init(_ audio: AVAudioPlayer) {
        self.audio = audio
        super.init()
        audio.delegate = self
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        // Each service request creates a distinct wrapper. The playback owner also checks
        // generation and player identity before accepting this asynchronously delivered failure.
        Task { @MainActor [weak self] in self?.failureHandler?() }
    }
    var duration: TimeInterval { audio.duration }
    var volume: Float { get { audio.volume } set { audio.volume = newValue } }
    func play() -> Bool { audio.numberOfLoops = 0; return audio.play() }
    func stop() { audio.stop() }
}

@MainActor
private final class SystemPlayer: NotificationSoundPlayer {
    let sound: NSSound
    var failureHandler: (@MainActor () -> Void)?
    init(_ sound: NSSound) { self.sound = sound }
    var duration: TimeInterval { sound.duration }
    var volume: Float { get { sound.volume } set { sound.volume = newValue } }
    func play() -> Bool { sound.loops = false; return sound.play() }
    func stop() { sound.stop() }
}
