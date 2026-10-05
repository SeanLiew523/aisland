import Foundation

@MainActor
public protocol NotificationSoundPlayer: AnyObject {
    var duration: TimeInterval { get }
    var volume: Float { get set }
    var failureHandler: (@MainActor () -> Void)? { get set }
    func play() -> Bool
    func stop()
}

/// One active sound, no queue. Muted automatic events leave manual previews alone.
/// Start/decode failure may try one fallback within the original automatic deadline.
@MainActor
public final class NotificationSoundPlayback {
    private var player: (any NotificationSoundPlayer)?
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0
    private let now: () -> TimeInterval
    private let sleepUntil: (TimeInterval) async throws -> Void
    public var isPlaying: Bool { player != nil }

    public init() {
        let clock = ContinuousClock(), epoch = clock.now
        now = {
            let components = epoch.duration(to: clock.now).components
            return Double(components.seconds) + Double(components.attoseconds) / 1e18
        }
        sleepUntil = { try await clock.sleep(until: epoch.advanced(by: .seconds($0))) }
    }

    // Internal clock seam: fixtures can drive the real scheduling logic without audio or wall-time races.
    init(now: @escaping () -> TimeInterval, sleepUntil: @escaping (TimeInterval) async throws -> Void) {
        self.now = now
        self.sleepUntil = sleepUntil
    }

    @discardableResult
    public func play(_ next: any NotificationSoundPlayer, isMuted: Bool = false,
                     limit: TimeInterval? = nil, fadeDuration: TimeInterval = 0.5,
                     fallback: (() -> (any NotificationSoundPlayer)?)? = nil) -> Bool {
        // Global mute changes use setMuted(true). A suppressed event must not stop a preview.
        guard !isMuted else { return false }
        stop()
        if let limit, !limit.isFinite || limit <= 0 { return false }
        let deadline = limit.map { now() + $0 }
        return start(next, deadline: deadline, fadeDuration: fadeDuration, fallback: fallback)
    }

    private func start(_ next: any NotificationSoundPlayer, deadline: TimeInterval?, fadeDuration: TimeInterval,
                       fallback: (() -> (any NotificationSoundPlayer)?)?) -> Bool {
        let remaining = deadline.map { $0 - now() }
        if let remaining, remaining <= 0 { next.stop(); return false }
        guard next.duration.isFinite, next.duration > 0 else {
            next.stop()
            return startFallback(fallback, deadline: deadline, fadeDuration: fadeDuration)
        }
        let token = generation
        let identity = ObjectIdentifier(next)
        next.volume = 1
        player = next
        next.failureHandler = { [weak self] in
            guard let self, self.generation == token,
                  let current = self.player, ObjectIdentifier(current) == identity else { return }
            self.stop()
            _ = self.startFallback(fallback, deadline: deadline, fadeDuration: fadeDuration)
        }
        guard next.play() else {
            // A stale failed attempt must not replace playback started by a callback.
            guard generation == token, player.map(ObjectIdentifier.init) == identity else { return isPlaying }
            stop()
            return startFallback(fallback, deadline: deadline, fadeDuration: fadeDuration)
        }
        guard generation == token, player.map(ObjectIdentifier.init) == identity else { return isPlaying }
        let startTime = now()
        let naturalEnd = startTime + next.duration
        let end = min(naturalEnd, deadline ?? .infinity)
        let duration = max(0, end - startTime)
        let fade = end < naturalEnd ? min(fadeDuration.isFinite ? max(0, fadeDuration) : 0, duration) : 0
        let sleepUntil = self.sleepUntil
        task = Task { [weak self] in
            do {
                // Absolute instants retain the original deadline even if task startup
                // or a fade continuation is delayed by MainActor contention.
                try await sleepUntil(end - fade)
                if fade > 0 {
                    let steps = 10
                    for step in 1...steps {
                        try await sleepUntil(end - fade + fade * Double(step) / Double(steps))
                        guard !Task.isCancelled, self?.generation == token else { return }
                        self?.player?.volume = Float(steps - step) / Float(steps)
                    }
                }
                guard !Task.isCancelled, self?.generation == token else { return }
                self?.stop()
            } catch { /* A canceled task must not touch the replacement player. */ }
        }
        return true
    }

    private func startFallback(_ fallback: (() -> (any NotificationSoundPlayer)?)?,
                               deadline: TimeInterval?, fadeDuration: TimeInterval) -> Bool {
        guard let replacement = fallback?() else { return false }
        // The fallback receives no fallback of its own: failure never recurses or loops.
        return start(replacement, deadline: deadline, fadeDuration: fadeDuration, fallback: nil)
    }

    public func setMuted(_ muted: Bool) { if muted { stop() } }

    public func stop() {
        generation &+= 1
        task?.cancel()
        task = nil
        player?.failureHandler = nil
        player?.stop()
        player = nil
    }
}
