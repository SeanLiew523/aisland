import AppKit
import AVFoundation
import SwiftUI
import OpenIslandCore

@MainActor
@Observable
final class OnboardingPlaybackState {
    var muted = false
    var reduceMotion = false
    var elapsed = 0.0
}

enum OnboardingExit: Equatable { case completed, skipped, closed }

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
private final class OnboardingControlsHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
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
    private var state = OnboardingPlaybackState()
    var isPresenting: Bool { window != nil }
    private(set) var lastError: String?

    /// Persistence is the caller's responsibility so hook migration can finish
    /// before claiming automatic presentation. Settings replay bypasses that gate.
    @discardableResult
    func present(language: OnboardingLanguage, completion: @escaping (OnboardingExit) -> Void) -> Bool {
        guard !isPresenting else { window?.makeKeyAndOrderFront(nil); return false }
        guard let screen = OnboardingGeometry.selectedScreen() else {
            lastError = "No display is available for the welcome."; return false
        }
        let media: OnboardingMedia
        do { media = try OnboardingMedia(language: language) }
        catch { lastError = "Welcome media could not be loaded: \(error.localizedDescription)"; return false }
        lastError = nil
        self.completion = completion
        state = OnboardingPlaybackState()
        state.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let root = NSView(frame: CGRect(origin: .zero,size: screen.frame.size))
        root.autoresizingMask = [.width,.height]
        let scene = OnboardingSceneView(media: media,language: language,geometry: .read(screen))
        scene.frame = root.bounds; scene.autoresizingMask = [.width,.height]
        scene.reduceMotion = state.reduceMotion
        self.scene = scene
        root.addSubview(scene)
        let controls = OnboardingControlsHostingView(rootView: OnboardingControls(state: state,language: language) { [weak self] in self?.finish(.skipped) })
        controls.frame = root.bounds; controls.autoresizingMask = [.width,.height]
        controls.wantsLayer = true; controls.layer?.backgroundColor = NSColor.clear.cgColor
        root.addSubview(controls)
        let window = OnboardingWindow(contentRect: screen.frame,styleMask: [.borderless],backing: .buffered,defer: false)
        window.title = language == .chinese ? "欢迎使用 AIsland" : "Welcome to AIsland"
        window.delegate = self; window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue+1)
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.contentView = root; window.setFrame(screen.frame,display: false)
        self.window = window
        originalPresentation = NSApp.presentationOptions
        NSApp.presentationOptions = [.hideDock,.hideMenuBar]
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
        if elapsed >= OnboardingTimeline.duration { finish(.completed) }
    }

    private func installObservers() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isPresenting else { return event }
            if event.keyCode == 53 { self.finish(.skipped); return nil }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" {
                self.finish(.closed); return nil
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

    func windowWillClose(_ notification: Notification) { finish(.closed) }

    private func finish(_ result: OnboardingExit) {
        guard window != nil else { return }
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
        if let originalPresentation { NSApp.presentationOptions = originalPresentation }
        originalPresentation = nil
    }
}

private struct OnboardingControls: View {
    @Bindable var state: OnboardingPlaybackState
    let language: OnboardingLanguage
    let skip: () -> Void
    private var chinese: Bool { language == .chinese }
    private var light: Bool { state.elapsed >= 6 && state.elapsed < 8.2 || state.elapsed >= 13.9 }
    var body: some View {
        VStack {
            HStack {
                Text("AIsland").font(.system(size: 15,weight: .semibold))
                Spacer()
                Button(chinese ? "跳过开场" : "Skip intro",action: skip)
                    .keyboardShortcut(.escape,modifiers: [])
            }
            Spacer()
            HStack(spacing: 24) {
                Toggle(chinese ? "静音" : "Mute",isOn: $state.muted)
                Toggle(chinese ? "减少动态效果" : "Reduce motion",isOn: $state.reduceMotion)
                Spacer()
                Text(String(format: "%.0f / 22 s",state.elapsed)).monospacedDigit().font(.system(size: 11))
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(light ? Color(red: 0.14,green: 0.21,blue: 0.31) : .white)
        .buttonStyle(.bordered)
        .toggleStyle(.checkbox)
        .padding(.horizontal,30)
        .padding(.top, max(40, NSApplication.shared.mainWindow?.screen?.safeAreaInsets.top ?? 0)+12)
        .padding(.bottom,26)
        .overlay(alignment: .bottom) {
            GeometryReader { geometry in
                Rectangle().fill(Color(red: 0.44,green: 0.61,blue: 1))
                    .frame(width: geometry.size.width*state.elapsed/OnboardingTimeline.duration,height: 2)
            }.frame(height: 2).accessibilityHidden(true)
        }
    }
}
