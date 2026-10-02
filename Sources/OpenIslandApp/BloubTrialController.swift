import AppKit
import OpenIslandCore
import SwiftUI

enum BloubTrialColorStyle: String, CaseIterable {
    case paper, status, blue, mint

    var title: String {
        switch self {
        case .paper: "暖白"
        case .status: "状态色：审批粉／回答黄"
        case .blue: "柔蓝"
        case .mint: "薄荷绿"
        }
    }
}

enum BloubTrialState: String, CaseIterable {
    case idle, running, approval, answer

    var title: String {
        switch self {
        case .idle: "空闲"
        case .running: "运行"
        case .approval: "等待审批"
        case .answer: "等待回答"
        }
    }

    var mode: UnifiedBars.Mode {
        switch self {
        case .idle: .idle
        case .running: .running
        case .approval, .answer: .waiting
        }
    }

    var statusTint: BloubTint {
        switch self {
        case .approval: .approval
        case .answer: .answer
        default: .paper
        }
    }

    func snapshot(expanded: Bool = false) -> IslandDebugSnapshot {
        let source: IslandDebugScenario = switch self {
        case .idle, .running: .closed
        case .approval: .approvalCard
        case .answer: .questionCard
        }
        let original = source.snapshot()
        var session = original.sessions.first!
        if self == .idle { session.phase = .completed }
        session.jumpTarget = nil
        return IslandDebugSnapshot(
            title: title, summary: "bloub 本地模拟会话", previewHeight: original.previewHeight,
            notchStatus: expanded ? .opened : .closed,
            notchOpenReason: expanded ? .click : nil,
            islandSurface: .sessionList(actionableSessionID: session.phase.requiresAttention ? session.id : nil),
            sessions: [session], selectedSessionID: session.id
        )
    }
}

/// Only enabled by the separately packaged trial bundle's Info.plist.
/// Uses the real app/overlay without runtime discovery, bridge or hook setup.
@MainActor
final class BloubTrialController {
    static var isEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "OpenIslandBloubTrial") as? Bool == true
    }

    static var launchEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        guard isEnabled else { return environment }
        environment["OPEN_ISLAND_HARNESS_SCENARIO"] = "closed"
        environment["OPEN_ISLAND_HARNESS_START_BRIDGE"] = "0"
        environment["OPEN_ISLAND_HARNESS_BOOT_ANIMATION"] = "0"
        environment["OPEN_ISLAND_HARNESS_INTERACTIVE"] = "1"
        environment["OPEN_ISLAND_HARNESS_PRESENT_OVERLAY"] = "1"
        return environment
    }

    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) { self.model = model }

    func show() {
        if window == nil {
            model.bloubColorStyle = .status
            model.bloubWaitingMotion = .alive
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 660, height: 410),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Bloub 刘海试验"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: BloubTrialControls(model: model))
            window.center()
            self.window = window
            model.openSettingsWindow = { [weak self] in self?.show() }
            model.loadDebugSnapshot(BloubTrialState.approval.snapshot(), presentOverlay: true)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct BloubTrialControls: View {
    @Bindable var model: AppModel
    @State private var state: BloubTrialState = .approval

    private func tint(for state: BloubTrialState) -> BloubTint {
        switch model.bloubColorStyle {
        case .paper: .paper
        case .status: state.statusTint
        case .blue: .blue
        case .mint: .mint
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("在真实刘海位置试一试").font(.system(size: 21, weight: .semibold))
            Text("点击下方状态，屏幕顶部会同步变化。四组对照是 24 pt 实尺寸与 48 pt 放大图。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack(spacing: 20) {
                ForEach(BloubTrialState.allCases, id: \.self) { sample in
                    VStack(spacing: 10) {
                        HStack(spacing: 14) {
                            BloubStatusGlyph(mode: sample.mode, size: 24, isActive: model.bloubPlayback,
                                             tint: tint(for: sample), waitingMotion: model.bloubWaitingMotion)
                            BloubStatusGlyph(mode: sample.mode, size: 48, isActive: model.bloubPlayback,
                                             tint: tint(for: sample), waitingMotion: model.bloubWaitingMotion)
                        }.padding(12).background(.black, in: RoundedRectangle(cornerRadius: 14))
                        Button(sample.title) {
                            state = sample
                            model.loadDebugSnapshot(sample.snapshot(), presentOverlay: true)
                        }
                    }
                }
            }
            Divider()
            Picker("角色颜色", selection: $model.bloubColorStyle) {
                ForEach(BloubTrialColorStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("等待动效", selection: $model.bloubWaitingMotion) {
                ForEach(BloubWaitingMotion.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
                Toggle("播放动效", isOn: $model.bloubPlayback).toggleStyle(.checkbox)
                Spacer()
                Button("展开任务卡") { model.loadDebugSnapshot(state.snapshot(expanded: true), presentOverlay: true) }
                Button("收起刘海") { model.loadDebugSnapshot(state.snapshot(), presentOverlay: true) }
                Button("退出试验") { NSApp.terminate(nil) }
            }
            Text("模拟会话 · 等待时约 5 秒眨眼一次，柔和闭合；通知点保持亮度。\n空闲节奏保持原样。退出后原应用继续使用；Dock 图标可重新打开此窗口。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }.padding(24).frame(width: 660)
    }
}
