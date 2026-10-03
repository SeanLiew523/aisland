import AppKit
import AVFoundation
import Observation
import OpenIslandCore

@MainActor
@Observable
final class OnboardingPlaybackState {
    var muted = false
    var reduceMotion = false
    var elapsed = 0.0
}

enum OnboardingExit: Equatable { case completed, skipped, closed }

/// First launch runs to the natural ending; replay is an explicit user action.
/// This policy never alters presentation/completion preferences.
enum OnboardingPlaybackMode: Sendable {
    case autoMandatory
    case explicitReplay

    var permitsManualExit: Bool { self == .explicitReplay }

    func permitsFinish(_ result: OnboardingExit, elapsed: Double) -> Bool {
        switch result {
        case .completed: elapsed >= OnboardingTimeline.duration
        case .closed: permitsManualExit
        case .skipped: false
        }
    }

    func exitForKey(keyCode: UInt16, command: Bool, characters: String?) -> OnboardingExit? {
        guard permitsManualExit else { return nil }
        return keyCode == 53 || (command && characters?.lowercased() == "w") ? .closed : nil
    }
}

/// One clock drives the score, sprite selection, title beats and 22-second end.
/// AVAudioPlayer's device time is monotonic; uptime is the silent fallback.
struct OnboardingPlaybackClock {
    let startUptime: Double
    let startAudioDeviceTime: Double?
    func elapsed(uptime: Double, audioDeviceTime: Double?) -> Double {
        if let startAudioDeviceTime, let audioDeviceTime {
            return max(0,audioDeviceTime-startAudioDeviceTime)
        }
        return max(0,uptime-startUptime)
    }
}

@MainActor
private final class OnboardingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var scene: OnboardingSceneView?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var clock: OnboardingPlaybackClock?
    private var escapeMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var motionObserver: NSObjectProtocol?
    private var originalPresentation: NSApplication.PresentationOptions?
    private var completion: ((OnboardingExit) -> Void)?
    private var playbackMode: OnboardingPlaybackMode = .explicitReplay
    private var state = OnboardingPlaybackState()
    private var hapticsEnabled = false
    private var nextHaptic = 0
    private let hapticTimes = [3.0, 8.2, 10.7, 15.7, 20.7]
    var isPresenting: Bool { window != nil }
    /// The app delegate uses this to refuse ordinary menu/Cmd-Q termination.
    /// Force Quit, signals and shutdown are outside this controller's policy.
    var isMandatoryPlayback: Bool { isPresenting && playbackMode == .autoMandatory }
    private(set) var lastError: String?

    /// Persistence is the caller's responsibility so hook migration can finish
    /// before claiming automatic presentation. Settings replay bypasses that gate.
    @discardableResult
    func present(language: OnboardingLanguage, mode: OnboardingPlaybackMode = .autoMandatory,
                 initiallyMuted: Bool = false,
                 hapticFeedbackEnabled: Bool = false,
                 completion: @escaping (OnboardingExit) -> Void) -> Bool {
        guard !isPresenting else { window?.makeKeyAndOrderFront(nil); return false }
        guard let screen = OnboardingGeometry.selectedScreen() else {
            lastError = "No display is available for the welcome."; return false
        }
        let media: OnboardingMedia
        do { media = try OnboardingMedia(language: language) }
        catch { lastError = "Welcome media could not be loaded: \(error.localizedDescription)"; return false }
        lastError = nil
        self.completion = completion
        playbackMode = mode
        state = OnboardingPlaybackState()
        state.muted = initiallyMuted
        hapticsEnabled = hapticFeedbackEnabled
        nextHaptic = 0
        state.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let root = NSView(frame: CGRect(origin: .zero,size: screen.frame.size))
        root.autoresizingMask = [.width,.height]
        let scene = OnboardingSceneView(media: media,language: language,geometry: .read(screen))
        scene.frame = root.bounds; scene.autoresizingMask = [.width,.height]
        scene.reduceMotion = state.reduceMotion
        self.scene = scene
        root.addSubview(scene)
        let window = OnboardingWindow(contentRect: screen.frame,styleMask: [.borderless],backing: .buffered,defer: false)
        window.title = language == .chinese ? "欢迎使用 AIsland" : "Welcome to AIsland"
        window.delegate = self; window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue+1)
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.contentView = root; window.setFrame(screen.frame,display: false)
        self.window = window
        originalPresentation = NSApp.presentationOptions
        NSApp.presentationOptions = mode == .autoMandatory
            ? [.hideDock, .hideMenuBar, .disableHideApplication]
            : [.hideDock, .hideMenuBar]
        installObservers()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startScore()
        timer = Timer(timeInterval: 1.0/60.0,repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!,forMode: .common)
        tick()
        return true
    }

    private func startScore() {
        // Preparation is complete before this one shared scheduling origin.
        let lead = 0.06
        if let url = Bundle.appResources.url(forResource: "intro-v6",withExtension: "wav"),
           let audio = try? AVAudioPlayer(contentsOf: url) {
            audio.prepareToPlay()
            audio.volume = state.muted ? 0 : 1
            let start = audio.deviceCurrentTime+lead
            if audio.play(atTime: start) {
                player = audio
                clock = OnboardingPlaybackClock(startUptime: ProcessInfo.processInfo.systemUptime+lead,startAudioDeviceTime: start)
                return
            }
        }
        // Failed audio never blocks the introduction or causes a second launch.
        state.muted = true
        clock = OnboardingPlaybackClock(startUptime: ProcessInfo.processInfo.systemUptime,startAudioDeviceTime: nil)
    }

    private func tick() {
        guard let clock, let scene else { return }
        let elapsed = clock.elapsed(uptime: ProcessInfo.processInfo.systemUptime,audioDeviceTime: player?.deviceCurrentTime)
        state.elapsed = min(OnboardingTimeline.duration,elapsed)
        player?.volume = state.muted ? 0 : 1
        scene.time = state.elapsed; scene.reduceMotion = state.reduceMotion; scene.needsDisplay = true
        if nextHaptic < hapticTimes.count, elapsed >= hapticTimes[nextHaptic] {
            let beat = hapticTimes[nextHaptic]
            while nextHaptic < hapticTimes.count, elapsed >= hapticTimes[nextHaptic] { nextHaptic += 1 }
            if hapticsEnabled, !state.reduceMotion, elapsed - beat < 0.15 {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        if elapsed >= OnboardingTimeline.duration { finish(.completed) }
    }

    private func installObservers() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isPresenting else { return event }
            let command = event.modifierFlags.contains(.command)
            if event.keyCode == 53 || (command && event.charactersIgnoringModifiers?.lowercased() == "w") {
                if let exit = self.playbackMode.exitForKey(
                    keyCode: event.keyCode, command: command,
                    characters: event.charactersIgnoringModifiers
                ) { self.finish(exit) }
                // Consume these shortcuts even when mandatory playback refuses
                // them, so the underlying Settings window cannot handle them.
                return nil
            }
            return event
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,object: nil,queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let screen = OnboardingGeometry.selectedScreen() else { self?.finish(.closed); return }
                self.window?.setFrame(screen.frame,display: true)
                self.scene?.geometry = .read(screen)
            }
        }
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object: nil,queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.state.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { !isMandatoryPlayback }

    func windowWillClose(_ notification: Notification) { finish(.closed) }

    private func finish(_ result: OnboardingExit) {
        guard window != nil, playbackMode.permitsFinish(result, elapsed: state.elapsed) else { return }
        let callback = completion
        stop()
        callback?(result)
    }

    /// Application termination tears down without opening settings as a side effect.
    func stop() {
        completion = nil
        timer?.invalidate(); timer = nil
        player?.stop(); player = nil; clock = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }; escapeMonitor = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }; screenObserver = nil
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }; motionObserver = nil
        window?.delegate = nil; window?.orderOut(nil); window?.close(); window = nil
        scene = nil
        playbackMode = .explicitReplay
        if let originalPresentation { NSApp.presentationOptions = originalPresentation }
        originalPresentation = nil
    }
}
