// Recording-only scheduling and sample data. Production views and animations are unchanged.
import AppKit
import OpenIslandCore

@MainActor
enum NativeDemoCapture {
    private static var timer: Timer?
    private static var frame = 0
    private static var started = Date()
    private static var activeSegment = -1
    static let cuts: [Double] = [0, 3, 7, 13.4, 16, 22.4, 25, 28, 30.4, 34]

    static func start(model: AppModel) {
        guard let directory = ProcessInfo.processInfo.environment["AGENT_ISLAND_MEDIA_DIR"] else { return }
        model.refreshCodexHookStatus()
        model.refreshClaudeHookStatus()
        model.refreshCCForkHookStatuses()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            started = .now
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in
                MainActor.assumeIsolated { record(model: model, directory: directory) }
            }
        }
    }

    private static func record(model: AppModel, directory: String) {
        let elapsed = Date().timeIntervalSince(started)
        let segment = cuts.lastIndex(where: { elapsed >= $0 }) ?? 0
        if segment >= cuts.count - 1 { timer?.invalidate(); NSApp.terminate(nil); return }
        if segment != activeSegment {
            activeSegment = segment
            model.loadDebugSnapshot(snapshot(segment: segment), presentOverlay: true)
        }
        guard let window = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible }), let view = window.contentView else { return }
        window.displayIfNeeded()
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds.integral
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        bitmap.size = bounds.size
        view.cacheDisplay(in: bounds, to: bitmap)
        // Core Animation is not driven by SwiftUI redraws. Read the actual native
        // presentation tree, preserving the live paths rather than their resting values.
        var rendered = bitmap
        if let nativeLayer = view.layer?.presentation(),
           let context = CGContext(data: nil, width: bitmap.pixelsWide, height: bitmap.pixelsHigh,
                                   bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            context.translateBy(x: 0, y: CGFloat(bitmap.pixelsHigh))
            context.scaleBy(x: CGFloat(bitmap.pixelsWide) / bounds.width,
                            y: -CGFloat(bitmap.pixelsHigh) / bounds.height)
            nativeLayer.render(in: context)
            if let image = context.makeImage() { rendered = NSBitmapImageRep(cgImage: image) }
        }
        guard let png = rendered.representation(using: .png, properties: [:]) else { return }
        let name = String(format: "frame-%04d.png", frame)
        try? png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
        let meta = "\(frame),\(elapsed),\(window.frame.width),\(window.frame.height),\(segment)\n"
        let timingURL = URL(fileURLWithPath: directory).appendingPathComponent("timing.csv")
        if !FileManager.default.fileExists(atPath: timingURL.path) { FileManager.default.createFile(atPath: timingURL.path, contents: Data()) }
        if let handle = try? FileHandle(forWritingTo: timingURL) { try? handle.seekToEnd(); try? handle.write(contentsOf: Data(meta.utf8)); try? handle.close() }
        frame += 1
    }

    private static func snapshot(segment: Int) -> IslandDebugSnapshot {
        let scenarios: [IslandDebugScenario] = [.closed, .closed, .approvalCard, .approvalCard, .questionCard, .questionCard, .sessionList, .completionCard, .closed]
        let base = scenarios[segment].snapshot()
        let compact = [0, 1, 2, 4, 8].contains(segment)
        let idle = segment == 0 || segment == 8
        let now = Date()
        var main = base.sessions[0]
        main.title = "Claude Code · aisland"
        main.tool = .claudeCode
        main.codexMetadata = nil
        main.claudeMetadata = nil
        main.jumpTarget = nil
        if idle { main.phase = .completed }
        main.summary = segment == 7 ? "登录流程已更新，检查通过。" : "优化登录流程"
        if main.permissionRequest != nil { main.permissionRequest = PermissionRequest(title: "允许修改登录流程？", summary: "更新会话校验逻辑", affectedPath: "src/auth/session.ts", primaryActionTitle: "允许", secondaryActionTitle: "拒绝") }
        if main.questionPrompt != nil { main.questionPrompt = QuestionPrompt(title: "选择登录方式", questions: [QuestionPromptItem(question: "使用哪种登录方式？", header: "登录", options: [QuestionOption(label: "Session cookies", description: "服务端管理会话"), QuestionOption(label: "JWT tokens", description: "无状态令牌"), QuestionOption(label: "OAuth 2.0", description: "第三方登录")])]) }
        let codex = AgentSession(id: "media-codex", title: "Codex · command-palette", tool: .codex, origin: .demo, attachmentState: .attached, phase: idle ? .completed : .running, summary: "完善命令面板", updatedAt: now, jumpTarget: nil)
        let gemini = AgentSession(id: "media-gemini", title: "Gemini CLI · website", tool: .geminiCLI, origin: .demo, attachmentState: .attached, phase: .completed, summary: "首页布局检查完成", updatedAt: now.addingTimeInterval(-60), jumpTarget: nil)
        return IslandDebugSnapshot(title: "AIsland native recording", summary: "Native UI, example sessions", previewHeight: base.previewHeight, notchStatus: compact ? .closed : base.notchStatus, notchOpenReason: compact ? nil : base.notchOpenReason, islandSurface: base.islandSurface, sessions: [main, codex, gemini], selectedSessionID: main.id)
    }
}
