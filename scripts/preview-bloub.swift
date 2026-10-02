import AppKit
import SwiftUI

// Isolated native preview: no AppModel, bridge, hooks, installed bundle or preferences.
private struct BloubPreview: View {
    @State private var mode: UnifiedBars.Mode = .idle
    @State private var playing = true
    @State private var cycles = true

    private let modes: [UnifiedBars.Mode] = [.idle, .running, .waiting]
    private func title(_ mode: UnifiedBars.Mode) -> String {
        switch mode { case .idle: "空闲"; case .running: "运行"; case .waiting: "等待审批／回答" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("bloub · 原生动效试验").font(.system(size: 22, weight: .semibold))
            Text("独立预览，不读取真实会话或修改已安装应用。24 点实尺寸与 48 点放大对照。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack(spacing: 32) {
                ForEach(modes, id: \.self) { state in
                    VStack(spacing: 14) {
                        Text(title(state)).font(.system(size: 13, weight: .medium))
                        HStack(spacing: 16) {
                            UnifiedBars(mode: state, size: 24)
                            BloubStatusGlyph(mode: state, size: 24, isActive: playing)
                            BloubStatusGlyph(mode: state, size: 48, isActive: playing)
                        }
                        .padding(16).background(Color.black, in: RoundedRectangle(cornerRadius: 16))
                        Text("原竖条  /  24 pt  /  48 pt").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            HStack(spacing: 12) {
                BloubStatusGlyph(mode: mode, size: 24, isActive: playing)
                Spacer().frame(width: 180)
                Image(systemName: "square.grid.2x2.fill").foregroundStyle(.cyan)
            }
            .padding(.horizontal, 16).frame(height: 32)
            .background(Color.black, in: UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 16,
                                                               bottomTrailingRadius: 16, topTrailingRadius: 0))
            .frame(maxWidth: .infinity, alignment: .center)
            HStack {
                ForEach(modes, id: \.self) { state in
                    Button(title(state)) { cycles = false; mode = state }
                }
                Spacer()
                Toggle("播放角色", isOn: $playing)
                Toggle("三态轮播", isOn: $cycles)
            }.toggleStyle(.checkbox)
            Text("下方预览演示状态间形变；手动选择可测试快速切换。关闭播放可检查静态状态。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(28).frame(width: 710).background(Color(nsColor: .windowBackgroundColor))
        .task(id: cycles) {
            while cycles && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, cycles else { return }
                let current = modes.firstIndex(of: mode) ?? 0
                mode = modes[(current + 1) % modes.count]
            }
        }
    }
}

@main
private enum PreviewMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 766, height: 430),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Bloub Status Preview"
        let delegate = PreviewWindowDelegate()
        window.delegate = delegate
        window.contentView = NSHostingView(rootView: BloubPreview())
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--verify-lifecycle") {
            let glyph = BloubLayerView(frame: CGRect(x: 10, y: 10, width: 24, height: 24))
            window.contentView?.addSubview(glyph)
            Task { @MainActor in
                // WindowServer can take longer than 0.2 s to expose a new app.
                let deadline = Date().addingTimeInterval(3)
                while !window.occlusionState.contains(.visible) && Date() < deadline {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                glyph.update(mode: .idle, isActive: true, reduceMotion: false)
                glyph.layoutSubtreeIfNeeded()
                fputs("Lifecycle visibility: visible=\(window.isVisible), occlusion=\(window.occlusionState.rawValue), attached=\(glyph.window === window), hidden=\(glyph.isHiddenOrHasHiddenAncestor), frame=\(glyph.frame), animations=\(glyph.hasScheduledAnimations), generation=\(glyph.animationGeneration), needsLayout=\(glyph.needsLayout)\n", stderr)
                precondition(glyph.hasScheduledAnimations, "Visible idle must animate")
                let generation = glyph.animationGeneration
                glyph.update(mode: .idle, isActive: true, reduceMotion: false)
                glyph.needsLayout = true
                glyph.layoutSubtreeIfNeeded()
                precondition(glyph.animationGeneration == generation, "Unchanged updates restarted playback")
                glyph.update(mode: .running, isActive: false, reduceMotion: false)
                glyph.layoutSubtreeIfNeeded()
                precondition(!glyph.hasScheduledAnimations, "Expanded surface kept playing")
                glyph.update(mode: .idle, isActive: true, reduceMotion: true)
                glyph.layoutSubtreeIfNeeded()
                precondition(!glyph.hasScheduledAnimations, "Reduce Motion kept playing")
                glyph.update(mode: .running, isActive: true, reduceMotion: false)
                glyph.layoutSubtreeIfNeeded()
                precondition(glyph.hasScheduledAnimations, "Resume did not start playback")
                glyph.isHidden = true
                glyph.layoutSubtreeIfNeeded()
                precondition(!glyph.hasScheduledAnimations, "Hidden view kept playing")
                glyph.isHidden = false
                glyph.update(mode: .waiting, isActive: true, reduceMotion: false)
                glyph.layoutSubtreeIfNeeded()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                    precondition(!glyph.hasScheduledAnimations, "Notify repeated after its entry pop")
                    glyph.update(mode: .waiting, isActive: true, reduceMotion: false,
                                 tint: .approval, waitingMotion: .alive)
                    glyph.layoutSubtreeIfNeeded()
                    precondition(glyph.hasScheduledAnimations, "Living notify did not start its loop")
                    let waitingGeneration = glyph.animationGeneration
                    glyph.update(mode: .waiting, isActive: true, reduceMotion: false,
                                 tint: .approval, waitingMotion: .alive)
                    glyph.needsLayout = true
                    glyph.layoutSubtreeIfNeeded()
                    precondition(glyph.animationGeneration == waitingGeneration, "Waiting loop restarted")
                    glyph.update(mode: .waiting, isActive: true, reduceMotion: true,
                                 tint: .answer, waitingMotion: .alive)
                    glyph.layoutSubtreeIfNeeded()
                    precondition(!glyph.hasScheduledAnimations, "Reduced motion kept notify playing")
                    glyph.update(mode: .running, isActive: true, reduceMotion: false)
                    glyph.layoutSubtreeIfNeeded()
                    window.orderOut(nil)
                    glyph.needsLayout = true
                    glyph.layoutSubtreeIfNeeded()
                    precondition(!glyph.hasScheduledAnimations, "Invisible window kept playing")
                    print("Native lifecycle checks passed: visible, unchanged, inactive, reduced motion, resumed, hidden, notify settled, living notify, unchanged notify, reduced notify, window hidden")
                    app.terminate(nil)
                }
            }
        }
        withExtendedLifetime(delegate) { app.run() }
    }
}

private final class PreviewWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
}
