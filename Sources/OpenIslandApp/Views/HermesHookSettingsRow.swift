import AppKit
import SwiftUI
import OpenIslandCore

/// Profile-scoped setup. Installation never grants Hermes' first-use consent.
struct HermesHookSettingsRow: View {
    let hooksBinaryURL: URL?
    let lang: LanguageManager
    @State private var profileDirectory = HermesHookInstallationManager.defaultProfileDirectory
    @State private var pythonURL = HermesHookInstallationManager.defaultPythonURL
    @State private var status: HermesHookInstallationStatus?
    @State private var message: String?
    @State private var busy = false
    private var chinese: Bool { lang.language.resolvedCode.hasPrefix("zh") }
    private func text(_ en: String, _ zh: String) -> String { chinese ? zh : en }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Hermes CLI").fontWeight(.medium)
                Spacer()
                Text(status?.isInstalled == true
                    ? (status?.hasConsent == true ? text("Configured · consent recorded", "已配置 · 已记录授权") : text("Configured · Hermes consent pending", "已配置 · 等待 Hermes 授权"))
                    : text("Not configured", "未配置"))
                    .foregroundStyle(.secondary).font(.caption)
                Button(text("Refresh", "刷新")) { refresh() }.disabled(busy)
                Button(status?.isInstalled == true ? text("Update", "更新") : text("Install", "安装")) { perform(install: true) }
                    .disabled(busy || hooksBinaryURL == nil)
                if status?.isInstalled == true {
                    Button(text("Uninstall", "卸载")) { perform(install: false) }.disabled(busy)
                }
            }
            HStack {
                Text(profileDirectory.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button(text("Choose profile…", "选择 profile…")) { choose(directory: true) }.disabled(busy)
                Button(text("Choose Python…", "选择 Python…")) { choose(directory: false) }.disabled(busy)
            }
            Text(text("Tracks turns and returns to the originating terminal. Approvals stay in Hermes. After installing, restart Hermes and approve the two AIsland hooks at its own prompt.", "显示回合状态并返回来源终端；审批留在 Hermes。安装后重启 Hermes，在它自己的提示中确认两条 AIsland hook。"))
                .font(.caption).foregroundStyle(.secondary)
            if let message { Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }
        .task { refresh() }
    }
    private func choose(directory: Bool) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = directory; panel.canChooseFiles = !directory
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        if directory { profileDirectory = selected } else { pythonURL = selected }
        status = nil; refresh()
    }
    private func refresh() { perform(install: nil) }
    private func perform(install: Bool?) {
        guard !busy else { return }
        busy = true; message = nil
        let manager = HermesHookInstallationManager(profileDirectory: profileDirectory, pythonURL: pythonURL)
        let binary = hooksBinaryURL
        Task {
            let result = await Task.detached { () -> Result<HermesHookInstallationStatus, Error> in
                Result {
                    if install == true {
                        guard let binary else { throw HermesHookInstallationError.missingBinary }
                        return try manager.install(hooksBinaryURL: binary)
                    }
                    if install == false { return try manager.uninstall() }
                    return try manager.status(hooksBinaryURL: binary)
                }
            }.value
            switch result {
            case let .success(value): status = value
            case let .failure(error): message = error.localizedDescription
            }
            busy = false
        }
    }
}
