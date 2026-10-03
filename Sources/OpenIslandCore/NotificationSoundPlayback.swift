import Foundation

@MainActor
public protocol NotificationSoundPlayer: AnyObject {
    var duration: TimeInterval { get }
    var volume: Float { get set }
    func play() -> Bool
    func stop()
}

/// One active sound, no queue. The timer releases completed playback and stale tasks
/// cannot stop a replacement. Manual previews pass no limit and play the full sound.
@MainActor
public final class NotificationSoundPlayback {
    private var player: (any NotificationSoundPlayer)?
    private var task: Task<Void, Never>?
    public var isPlaying: Bool { player != nil }

    public init() {}

    @discardableResult
    public func play(_ next: any NotificationSoundPlayer, isMuted: Bool = false,
                     limit: TimeInterval? = nil, fadeDuration: TimeInterval = 0.5) -> Bool {
        stop()
        guard !isMuted, next.duration.isFinite, next.duration > 0 else { return false }
        next.volume = 1
        guard next.play() else { next.stop(); return false }
        player = next
        let duration = min(next.duration, limit ?? next.duration)
        let fade = limit != nil && next.duration > duration ? min(fadeDuration, duration) : 0
        task = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, duration - fade)))
                if fade > 0 {
                    let steps = 10
                    for step in 1...steps {
                        try await Task.sleep(for: .seconds(fade / Double(steps)))
                        guard !Task.isCancelled else { return }
                        self?.player?.volume = Float(steps - step) / Float(steps)
                    }
                }
                guard !Task.isCancelled else { return }
                self?.stop()
            } catch { /* Cancellation belongs to stop/replacement; do not touch a newer player. */ }
        }
        return true
    }

    public func setMuted(_ muted: Bool) { if muted { stop() } }

    public func stop() {
        task?.cancel()
        task = nil
        player?.stop()
        player = nil
    }
}
