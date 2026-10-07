import SwiftUI
import AppKit
import OpenIslandCore

// MARK: - Settings tabs

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case setup
    case display
    case sound
    case appearance
    case watch
    case shortcuts
    case lab
    case about

    var id: String { rawValue }

    func label(_ lang: LanguageManager) -> String {
        switch self {
        case .general:    lang.t("settings.tab.general")
        case .setup:      lang.t("settings.tab.setup")
        case .appearance: lang.t("settings.tab.appearance")
        case .display:    lang.t("settings.tab.display")
        case .sound:      lang.t("settings.tab.sound")
        case .watch:      "Watch"
        case .shortcuts:  lang.t("settings.tab.shortcuts")
        case .lab:        lang.t("settings.tab.lab")
        case .about:      lang.t("settings.tab.about")
        }
    }

    var icon: String {
        switch self {
        case .general:    "gearshape.fill"
        case .setup:      "arrow.down.circle.fill"
        case .appearance: "paintbrush.fill"
        case .display:    "textformat.size"
        case .sound:      "speaker.wave.2.fill"
        case .watch:      "applewatch"
        case .shortcuts:  "keyboard.fill"
        case .lab:        "flask.fill"
        case .about:      "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .general:    .gray
        case .setup:      .orange
        case .appearance: .purple
        case .display:    .blue
        case .sound:      .green
        case .watch:      .cyan
        case .shortcuts:  .gray
        case .lab:        .pink
        case .about:      .blue
        }
    }

    var section: SettingsSection {
        switch self {
        case .general, .setup, .display, .sound, .appearance, .watch: .system
        case .shortcuts, .lab:                                        .advanced
        case .about:                                                  .app
        }
    }
}

enum SettingsSection: String, CaseIterable {
    case system
    case advanced
    case app

    func header(_ lang: LanguageManager) -> String {
        switch self {
        case .system:   lang.t("settings.section.system")
        case .advanced: lang.t("settings.section.advanced")
        case .app:      AppBrand.displayName
        }
    }

    var tabs: [SettingsTab] {
        SettingsTab.allCases.filter { $0.section == self && $0 != .watch }
    }
}

// MARK: - Root settings view

struct SettingsView: View {
    var model: AppModel
    @State private var selectedTab: SettingsTab = .general

    private var lang: LanguageManager { model.lang }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detailView
        }
        .frame(minWidth: 680, idealWidth: 780, minHeight: 480, idealHeight: 560)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .openIslandSelectSetupTab)) { _ in
            selectedTab = .setup
        }
    }

    // MARK: Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selectedTab) {
            ForEach(SettingsSection.allCases, id: \.self) { section in
                Section(section.header(lang)) {
                    ForEach(section.tabs) { tab in
                        Label {
                            Text(tab.label(lang))
                        } icon: {
                            Image(systemName: tab.icon)
                                .foregroundStyle(tab.iconColor)
                        }
                        .tag(tab)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: Detail

    @ViewBuilder
    private var detailView: some View {
        ZStack(alignment: .topTrailing) {
            switch selectedTab {
            case .general:
                GeneralSettingsPane(model: model)
            case .setup:
                SetupSettingsPane(model: model)
            case .appearance:
                AppearanceSettingsPane(model: model)
            case .display:
                DisplaySettingsPane(model: model)
            case .sound:
                SoundSettingsPane(model: model)
            case .watch:
                WatchSettingsPane(model: model)
            case .shortcuts:
                PlaceholderSettingsPane(model: model, titleKey: "settings.tab.shortcuts", subtitleKey: "settings.shortcuts.comingSoon")
            case .lab:
                PlaceholderSettingsPane(model: model, titleKey: "settings.tab.lab", subtitleKey: "settings.lab.comingSoon")
            case .about:
                AboutSettingsPane(model: model)
            }

            if model.updateChecker.hasUpdate, let version = model.updateChecker.latestVersion {
                UpdateBanner(version: version, lang: lang) {
                    model.updateChecker.downloadAndInstall()
                }
                .padding(.top, 8)
                .padding(.trailing, 16)
            }
        }
    }
}

// MARK: - General

struct GeneralSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    var body: some View {
        Form {
            Section(lang.t("settings.section.system")) {
                Toggle(lang.t("settings.general.launchAtLogin"), isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.launchAtLoginEnabled = $0 }
                ))

                Picker(lang.t("settings.general.monitor"), selection: Binding(
                    get: { model.overlayDisplaySelectionID },
                    set: { model.overlayDisplaySelectionID = $0 }
                )) {
                    Text(lang.t("settings.general.automatic")).tag(OverlayDisplayOption.automaticID)
                    ForEach(model.overlayDisplayOptions) { option in
                        Text(option.title)
                            .tag(option.id)
                            .disabled(!option.isAvailable)
                    }
                }
            }

            Section(lang.t("settings.general.language")) {
                Picker(lang.t("settings.general.language"), selection: Binding(
                    get: { lang.language },
                    set: { lang.language = $0 }
                )) {
                    Text(lang.t("settings.general.languageSystem")).tag(LanguageManager.AppLanguage.system)
                    Text(lang.t("settings.general.languageEnglish")).tag(LanguageManager.AppLanguage.en)
                    Text(lang.t("settings.general.languageChinese")).tag(LanguageManager.AppLanguage.zhHans)
                    Text(lang.t("settings.general.languageTraditionalChinese")).tag(LanguageManager.AppLanguage.zhHant)
                }
                Button(lang.t("settings.general.replayWelcome")) { model.replayWelcome?() }
            }

            Section(lang.t("settings.general.behavior")) {
                Toggle(lang.t("settings.general.keepOpenUntilDecision"), isOn: Binding(
                    get: { model.keepNotchOpenUntilDecision },
                    set: { model.keepNotchOpenUntilDecision = $0 }
                ))
                Toggle(lang.t("settings.general.showDockIcon"), isOn: Binding(
                    get: { model.showDockIcon },
                    set: { model.showDockIcon = $0 }
                ))
                Toggle(lang.t("settings.general.hapticFeedback"), isOn: Binding(
                    get: { model.hapticFeedbackEnabled },
                    set: { model.hapticFeedbackEnabled = $0 }
                ))
                Toggle(lang.t("settings.general.completionReply"), isOn: Binding(
                    get: { model.completionReplyEnabled },
                    set: { model.completionReplyEnabled = $0 }
                ))
                Toggle(lang.t("settings.general.suppressFrontmostNotifications"), isOn: Binding(
                    get: { model.suppressFrontmostNotifications },
                    set: { model.suppressFrontmostNotifications = $0 }
                ))
            }

        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.general"))
    }
}

// MARK: - Display

struct DisplaySettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    var body: some View {
        Form {
            Section(lang.t("settings.display.monitor")) {
                Picker(lang.t("settings.display.position"), selection: Binding(
                    get: { model.overlayDisplaySelectionID },
                    set: { model.overlayDisplaySelectionID = $0 }
                )) {
                    Text(lang.t("settings.general.automatic")).tag(OverlayDisplayOption.automaticID)
                    ForEach(model.overlayDisplayOptions) { option in
                        Text(option.title)
                            .tag(option.id)
                            .disabled(!option.isAvailable)
                    }
                }
            }

            if let diag = model.overlayPlacementDiagnostics {
                Section(lang.t("settings.display.diagnostics")) {
                    LabeledContent(lang.t("settings.display.currentScreen"), value: diag.targetScreenName)
                    LabeledContent(lang.t("settings.display.layoutMode"), value: diag.modeDescription)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.display"))
    }
}

// MARK: - Sound

struct SoundSettingsPane: View {
    var model: AppModel
    @State private var selections: [NotificationSoundCategory: NotificationSoundSelection] = [:]
    @State private var fallbacks: Set<NotificationSoundCategory> = []
    @State private var messages: [NotificationSoundCategory: String] = [:]
    @State private var playbackMode: NotificationSoundPlaybackMode = .shortFade

    private var lang: LanguageManager { model.lang }
    private var store: NotificationSoundStore { NotificationSoundService.store }
    private var availableSounds: [String] { NotificationSoundService.availableSounds() }

    private func text(_ en: String, _ zh: String, _ hant: String) -> String {
        switch lang.language.resolvedCode {
        case "zh-Hans": zh
        case "zh-Hant": hant
        default: en
        }
    }

    var body: some View {
        Form {
            Section(lang.t("settings.sound.notifications")) {
                Toggle(lang.t("settings.sound.mute"), isOn: Binding(
                    get: { model.isSoundMuted },
                    set: { _ in model.toggleSoundMuted(); NotificationSoundService.setMuted(model.isSoundMuted) }
                ))
                Picker(text("Automatic playback", "自动提示长度", "自動提示長度"), selection: $playbackMode) {
                    Text(text("Up to 5 seconds, fade out", "最多 5 秒，淡出结束", "最多 5 秒，淡出結束"))
                        .tag(NotificationSoundPlaybackMode.shortFade)
                    Text(text("Full audio", "完整播放", "完整播放")).tag(NotificationSoundPlaybackMode.full)
                }
                Text(text("New alerts replace the current sound.",
                          "新提示会替换正在播放的声音。",
                          "新提示會替換正在播放的聲音。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(NotificationSoundCategory.allCases, id: \.self) { category in
                Section(categoryTitle(category)) {
                    Picker(text("Sound", "声音", "聲音"), selection: sourceBinding(category)) {
                        ForEach(availableSounds, id: \.self) { name in
                            Text(name).tag("system:" + name)
                        }
                        Text(text("Custom MP3…", "自定义 MP3…", "自訂 MP3…")).tag("custom")
                    }
                    if case .custom(let asset) = selections[category] {
                        Text(asset.displayName).lineLimit(1).truncationMode(.middle)
                        Text(text("Managed copy · ", "已保存本地副本 · ", "已儲存本機副本 · ")
                             + String(format: "%.1f s", asset.duration))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(text("Preview full audio", "完整试听", "完整試聽")) {
                            refresh()
                            if !NotificationSoundService.preview(category: category) {
                                messages[category] = text("Playback failed. Check your audio output.", "播放失败，请检查音频输出。", "播放失敗，請檢查音訊輸出。")
                            }
                        }
                        Button(text("Import / Replace MP3", "导入 / 替换 MP3", "匯入 / 替換 MP3")) { importMP3(category) }
                        Button(text("Restore default", "恢复默认", "恢復預設")) {
                            NotificationSoundService.stop()
                            store.restoreDefault(for: category)
                            messages[category] = nil
                            refresh()
                        }
                    }
                    if fallbacks.contains(category) {
                        Text(text("The managed MP3 is missing or unreadable. Alerts and previews use Bottle until you replace it or restore the default.",
                                  "本地 MP3 已丢失或无法读取。提示和试听暂用 Bottle；请替换文件或恢复默认。",
                                  "本機 MP3 已遺失或無法讀取。提示和試聽暫用 Bottle；請替換檔案或恢復預設。"))
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if let message = messages[category] {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button(text("Stop playback", "停止播放", "停止播放")) { NotificationSoundService.stop() }
                Text(text("Manual previews play the full sound even when automatic alerts are muted. MP3 files are limited to 20 MB.",
                          "主动试听始终完整播放，不受自动提示静音影响。MP3 文件最大 20 MB。",
                          "主動試聽始終完整播放，不受自動提示靜音影響。MP3 檔案最大 20 MB。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.sound"))
        .onAppear { refresh(); playbackMode = store.playbackMode }
        .onChange(of: playbackMode) { _, mode in NotificationSoundService.stop(); store.playbackMode = mode }
        .onChange(of: model.isSoundMuted) { _, muted in NotificationSoundService.setMuted(muted) }
        .onDisappear { NotificationSoundService.stop() }
    }

    private func categoryTitle(_ category: NotificationSoundCategory) -> String {
        switch category {
        case .completed: text("Task completed", "任务完成", "任務完成")
        case .approval: text("Waiting for approval", "等待审批", "等待審批")
        case .answer: text("Waiting for an answer", "等待回答", "等待回答")
        }
    }

    private func sourceBinding(_ category: NotificationSoundCategory) -> Binding<String> {
        Binding(get: {
            if case .system(let name) = selections[category] { return "system:" + name }
            if case .custom = selections[category] { return "custom" }
            return "system:" + NotificationSoundService.defaultSoundName
        }, set: { source in
            if source == "custom" { importMP3(category) }
            else if source.hasPrefix("system:") {
                NotificationSoundService.stop()
                store.selectSystem(String(source.dropFirst(7)), for: category)
                messages[category] = nil
                refresh()
            }
        })
    }

    private func refresh() {
        for category in NotificationSoundCategory.allCases {
            selections[category] = store.selection(for: category)
            if store.resolve(category).usedFallback { fallbacks.insert(category) }
            else { fallbacks.remove(category) }
        }
    }

    private func importMP3(_ category: NotificationSoundCategory) {
        NotificationSoundService.stop()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = text("Import MP3", "导入 MP3", "匯入 MP3")
        guard panel.runModal() == .OK, let url = panel.url else {
            messages[category] = text("Import cancelled. Your selection is unchanged.", "已取消导入，原有选择保持不变。", "已取消匯入，原有選擇保持不變。")
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try store.importMP3(from: url, for: category)
            messages[category] = text("Imported. You can move or delete the original file.", "已导入；移动或删除原始文件不影响声音。", "已匯入；移動或刪除原始檔案不影響聲音。")
        } catch {
            let reason: String
            switch error as? NotificationSoundImportError {
            case .notMP3: reason = text("Choose a real MP3 file.", "请选择真实 MP3 文件。", "請選擇真正的 MP3 檔案。")
            case .tooLarge: reason = text("The file exceeds 20 MB.", "文件超过 20 MB。", "檔案超過 20 MB。")
            case .invalidAudio: reason = text("The file cannot be decoded or has no audio.", "文件无法解码或没有有效音频。", "檔案無法解碼或沒有有效音訊。")
            default: reason = text("The file or managed directory is inaccessible.", "无法访问文件或本地声音目录。", "無法存取檔案或本機聲音目錄。")
            }
            messages[category] = reason + text(" Your previous selection is unchanged.", "原有选择保持不变。", "原有選擇保持不變。")
        }
        refresh()
    }
}

// MARK: - About

struct AboutSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }
    private let primaryInk = Color.white.opacity(0.94)

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)

                Text(AppBrand.displayName)
                    .font(.title.bold())

                Text(lang.t("app.description"))
                    .foregroundStyle(.secondary)

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text(lang.t("settings.about.version", version))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            Form {
                Section {
                    aboutActionRow(
                        title: lang.t("settings.about.checkForUpdates"),
                        systemImage: "arrow.triangle.2.circlepath",
                        tint: primaryInk,
                        action: {
                            model.updateChecker.checkForUpdates()
                        }
                    )
                    .disabled(!model.updateChecker.canCheckForUpdates)
                    .opacity(model.updateChecker.canCheckForUpdates ? 1 : 0.55)
                    .accessibilityIdentifier("settings.about.checkForUpdates")

                    UpdateSettingsStatus(checker: model.updateChecker, lang: lang)
                }

                Section {
                    aboutActionRow(
                        title: lang.t("settings.about.quitApp"),
                        systemImage: "rectangle.portrait.and.arrow.right",
                        tint: Color(red: 1.0, green: 0.29, blue: 0.29),
                        action: {
                            model.quitApplication()
                        }
                    )
                    .accessibilityIdentifier("settings.about.quitApp")
                }
            }
            .formStyle(.grouped)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationTitle(lang.t("settings.tab.about"))
    }

    private func aboutActionRow(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18, alignment: .leading)

                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))

                Spacer()
            }
            .foregroundStyle(tint)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Setup

struct SetupSettingsPane: View {
    var model: AppModel

    @State private var confirmingUninstallClaude = false
    @State private var confirmingUninstallCodex = false
    @State private var confirmingUninstallOpenCode = false
    @State private var confirmingUninstallQoder = false
    @State private var confirmingUninstallQwenCode = false
    @State private var confirmingUninstallFactory = false
    @State private var confirmingUninstallCodebuddy = false
    @State private var confirmingUninstallZcode = false
    @State private var confirmingUninstallWorkbuddy = false
    @State private var confirmingUninstallCursor = false
    @State private var confirmingUninstallGemini = false
    @State private var confirmingUninstallKimi = false
    @State private var confirmingUninstallGrok = false
    @State private var confirmingUninstallPi = false
    @State private var confirmingUninstallOhMyPi = false
    @State private var confirmingUninstallClaudeUsage = false

    private var lang: LanguageManager { model.lang }

    var body: some View {
        Form {
            Section {
                Text(lang.t("setup.connection.explanation"))
                    .font(.callout)
                Text(lang.t("setup.connection.automatic"))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.hooks.automaticConnectionErrors.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { agent in
                    Text("\(agent.rawValue): \(model.hooks.automaticConnectionErrors[agent] ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(lang.t("setup.connection.configurationOnly"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let reason = model.hooks.setupBlockReason(requiresBinary: false) {
                    Text(lang.t(reason.rawValue))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !model.hasAnyInstalledAgent {
                emptyStateBanner
            }

            claudeConfigDirectorySection

            Section(lang.t("setup.section.hooks")) {
                hookRow(
                    name: "Claude Code",
                    agent: .claudeCode,
                    installed: model.claudeHooksInstalled,
                    configurationKnown: model.claudeHookStatus != nil,
                    busy: model.isClaudeHookSetupBusy,
                    configLocationURL: model.claudeHookStatus?.settingsURL,
                    installAction: { model.installClaudeHooks() },
                    uninstallAction: { confirmingUninstallClaude = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallClaude) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallClaudeHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("settings.general.uninstallConfirmMessage.claude"))
                }

                hookRow(
                    name: "Codex",
                    agent: .codex,
                    installed: model.codexHooksInstalled,
                    configurationKnown: model.codexHookStatus != nil,
                    busy: model.isCodexSetupBusy,
                    configLocationURL: codexHookConfigURL,
                    installAction: { model.installCodexHooks() },
                    uninstallAction: { confirmingUninstallCodex = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallCodex) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallCodexHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("settings.general.uninstallConfirmMessage.codex"))
                }

                hookRow(
                    name: "OpenCode",
                    agent: .openCode,
                    installed: model.openCodePluginInstalled,
                    configurationKnown: model.openCodePluginStatus != nil,
                    busy: model.isOpenCodeSetupBusy,
                    requiresBinary: false,
                    configLocationURL: model.openCodePluginStatus?.configURL,
                    installAction: { model.installOpenCodePlugin() },
                    uninstallAction: { confirmingUninstallOpenCode = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallOpenCode) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallOpenCodePlugin()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove the AIsland plugin from ~/.config/opencode/plugins/.")
                }

                hookRow(
                    name: "Qoder",
                    agent: .qoder,
                    installed: model.qoderHooksInstalled,
                    configurationKnown: model.qoderHookStatus != nil,
                    busy: model.isQoderHookSetupBusy,
                    configLocationURL: model.qoderHookStatus?.settingsURL,
                    installAction: { model.installQoderHooks() },
                    uninstallAction: { confirmingUninstallQoder = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallQoder) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallQoderHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove AIsland hooks from ~/.qoder/settings.json.")
                }

                hookRow(
                    name: "Qwen Code",
                    agent: .qwenCode,
                    installed: model.qwenCodeHooksInstalled,
                    configurationKnown: model.qwenCodeHookStatus != nil,
                    busy: model.isQwenCodeHookSetupBusy,
                    configLocationURL: model.qwenCodeHookStatus?.settingsURL,
                    installAction: { model.installQwenCodeHooks() },
                    uninstallAction: { confirmingUninstallQwenCode = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallQwenCode) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallQwenCodeHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove AIsland hooks from ~/.qwen/settings.json.")
                }

                hookRow(
                    name: "Factory",
                    agent: .factory,
                    installed: model.factoryHooksInstalled,
                    configurationKnown: model.factoryHookStatus != nil,
                    busy: model.isFactoryHookSetupBusy,
                    configLocationURL: model.factoryHookStatus?.settingsURL,
                    installAction: { model.installFactoryHooks() },
                    uninstallAction: { confirmingUninstallFactory = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallFactory) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallFactoryHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove AIsland hooks from ~/.factory/settings.json.")
                }

                hookRow(
                    name: "CodeBuddy",
                    agent: .codebuddy,
                    installed: model.codebuddyHooksInstalled,
                    configurationKnown: model.codebuddyHookStatus != nil,
                    busy: model.isCodebuddyHookSetupBusy,
                    configLocationURL: model.codebuddyHookStatus?.settingsURL,
                    installAction: { model.installCodebuddyHooks() },
                    uninstallAction: { confirmingUninstallCodebuddy = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallCodebuddy) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallCodebuddyHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove AIsland hooks from ~/.codebuddy/settings.json.")
                }

                hookRow(
                    name: "ZCode",
                    agent: .zcode,
                    installed: model.zcodeHooksInstalled,
                    configurationKnown: model.zcodeHookStatus != nil,
                    busy: model.isZcodeHookSetupBusy,
                    configLocationURL: model.zcodeHookStatus?.settingsURL,
                    installAction: { model.installZcodeHooks() },
                    uninstallAction: { confirmingUninstallZcode = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallZcode) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallZcodeHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove AIsland hooks from ~/.zcode/cli/config.json.")
                }

                hookRow(
                    name: "WorkBuddy",
                    agent: .workbuddy,
                    installed: model.workbuddyHooksInstalled,
                    configurationKnown: model.workbuddyHookStatus != nil,
                    busy: model.isWorkbuddyHookSetupBusy,
                    configLocationURL: model.workbuddyHookStatus?.settingsURL,
                    installAction: { model.installWorkbuddyHooks() },
                    uninstallAction: { confirmingUninstallWorkbuddy = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallWorkbuddy) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallWorkbuddyHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove AIsland hooks from ~/.workbuddy/settings.json.")
                }

                hookRow(
                    name: "Cursor",
                    agent: .cursor,
                    installed: model.cursorHooksInstalled,
                    configurationKnown: model.cursorHookStatus != nil,
                    busy: model.isCursorHookSetupBusy,
                    requiresBinary: true,
                    configLocationURL: model.cursorHookStatus?.hooksURL,
                    installAction: { model.installCursorHooks() },
                    uninstallAction: { confirmingUninstallCursor = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallCursor) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallCursorHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove the AIsland hooks from ~/.cursor/hooks.json.")
                }

                hookRow(
                    name: "Gemini CLI",
                    agent: .gemini,
                    installed: model.geminiHooksInstalled,
                    configurationKnown: model.geminiHookStatus != nil,
                    busy: model.isGeminiHookSetupBusy,
                    configLocationURL: geminiHookConfigURL,
                    installAction: { model.installGeminiHooks() },
                    uninstallAction: { confirmingUninstallGemini = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallGemini) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallGeminiHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove AIsland hooks from ~/.gemini/settings.json.")
                }

                hookRow(
                    name: "Kimi CLI",
                    agent: .kimi,
                    installed: model.kimiHooksInstalled,
                    configurationKnown: model.kimiHookStatus != nil,
                    busy: model.isKimiHookSetupBusy,
                    configLocationURL: model.kimiHookStatus?.configURL,
                    installAction: { model.installKimiHooks() },
                    uninstallAction: { confirmingUninstallKimi = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallKimi) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallKimiHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove AIsland hooks from ~/.kimi/config.toml.")
                }

                hookRow(
                    name: "Grok Build",
                    agent: .grok,
                    installed: model.grokHooksInstalled,
                    configurationKnown: model.grokHookStatus != nil,
                    busy: model.isGrokHookSetupBusy,
                    requiresBinary: true,
                    configLocationURL: model.grokHookStatus?.hooksURL,
                    installAction: { model.installGrokHooks() },
                    uninstallAction: { confirmingUninstallGrok = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallGrok) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallGrokHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove AIsland hooks from ~/.grok/hooks/open-island.json.")
                }

                desktopConnectionRow(agent: .deepSeekDesktop, name: "DeepSeek Harness Desktop")
                desktopConnectionRow(agent: .miniMaxCodeDesktop, name: "MiniMaxCode Desktop")

                HermesHookSettingsRow(hooksBinaryURL: model.hooksBinaryURL, lang: lang, setupDisabled: model.hooks.isRuntimeAcceptance, setupDisabledExplanationKey: model.hooks.sourceSetupAcceptance == nil ? "setup.connection.isolated" : "setup.connection.sourceSetupScope", sourceDetected: model.hooks.detectedInstallations[.hermes] != nil, automaticStatus: model.hooks.hermesHookStatus, receivedSessionEventProfiles: model.hooks.hermesSessionEventProfiles) { status, intent in
                    model.hooks.hermesHookStatus = status
                    model.hooks.intentStore.setIntent(intent, for: .hermes)
                }
                .disabled(model.hooks.isAutomaticConnectionBusy)
                if model.hooks.sourceSetupAcceptance?.agents.contains(.hermes) == true {
                    Button(lang.t("setup.desktop.stopAutomatic")) { model.hooks.cancelSourceSetupHermes() }
                        .disabled(model.hooks.isAutomaticConnectionBusy || model.hooks.intentStore.intent(for: .hermes) == .uninstalled)
                }

                hookRow(
                    name: "Pi",
                    agent: .pi,
                    installed: model.piExtensionInstalled,
                    configurationKnown: model.piExtensionStatus != nil,
                    busy: model.isPiSetupBusy,
                    requiresBinary: false,
                    configLocationURL: model.piExtensionStatus?.extensionURL,
                    installAction: { model.installPiExtension() },
                    uninstallAction: { confirmingUninstallPi = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallPi) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallPiExtension()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove the AIsland extension from ~/.pi/agent/extensions/.")
                }

                hookRow(
                    name: "Oh My Pi",
                    agent: .ohMyPi,
                    installed: model.ohMyPiExtensionInstalled,
                    configurationKnown: model.ohMyPiExtensionStatus != nil,
                    busy: model.isOhMyPiSetupBusy,
                    requiresBinary: false,
                    configLocationURL: model.ohMyPiExtensionStatus?.extensionURL,
                    installAction: { model.installOhMyPiExtension() },
                    uninstallAction: { confirmingUninstallOhMyPi = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallOhMyPi) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallOhMyPiExtension()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove the AIsland extension from ~/.omp/agent/extensions/.")
                }
            }

            Section {
                HStack {
                    Label(lang.t("setup.usageBridge"), systemImage: "chart.bar")
                    Spacer()
                    if model.claudeUsageInstalled {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(lang.t("setup.usageBridgeReady"))
                                .foregroundStyle(.secondary)
                        }
                        Button(lang.t("setup.connection.remove")) {
                            confirmingUninstallClaudeUsage = true
                        }
                        .disabled(model.hooks.isRuntimeAcceptance)
                    } else if model.isClaudeUsageSetupBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(lang.t("setup.connection.configure")) {
                            model.installClaudeUsageBridge()
                        }
                        .disabled(model.hooks.isRuntimeAcceptance)
                    }
                }
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallClaudeUsage) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallClaudeUsageBridge()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("settings.general.uninstallConfirmMessage.claudeUsage"))
                }

                Toggle(lang.t("settings.general.showCodexUsage"), isOn: Binding(
                    get: { model.showCodexUsage },
                    set: { model.showCodexUsage = $0 }
                ))
            } header: {
                HStack(spacing: 4) {
                    Text(lang.t("setup.section.usage"))
                    Text(lang.t("setup.optional"))
                        .foregroundStyle(.tertiary)
                }
            }

            Section(lang.t("setup.section.permissions")) {
                HStack(alignment: .top) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang.t("setup.permissionsTitle"))
                            Text(lang.t("setup.permissionsDesc"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "lock.shield")
                    }
                    Spacer()
                }
            }

            hookDiagnosticsSection


            Section {
                Button(lang.t("setup.installAll")) {
                    Task { await model.hooks.configureDetectedSources() }
                }
                .disabled(model.hooks.isRuntimeAcceptance || model.hooks.isAutomaticConnectionBusy)
                .frame(maxWidth: .infinity, alignment: .center)
                Text(lang.t("setup.connection.configureAllExplanation"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.setup"))
    }

    @ViewBuilder
    private var claudeConfigDirectorySection: some View {
        Section {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lang.t("setup.claudeConfigDir.title"))
                        Text(ClaudeConfigDirectory.resolved().path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } icon: {
                    Image(systemName: "folder")
                }
                Spacer()
                if ClaudeConfigDirectory.customDirectory != nil {
                    Button(lang.t("setup.claudeConfigDir.reset")) {
                        model.updateClaudeConfigDirectory(to: nil)
                    }
                    .font(.caption)
                }
                Button(lang.t("setup.claudeConfigDir.choose")) {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    panel.showsHiddenFiles = true
                    panel.prompt = lang.t("setup.claudeConfigDir.choose")
                    if panel.runModal() == .OK, let url = panel.url {
                        model.updateClaudeConfigDirectory(to: url)
                    }
                }
            }
        } header: {
            HStack(spacing: 4) {
                Text(lang.t("setup.claudeConfigDir.section"))
                Text(lang.t("setup.optional"))
                    .foregroundStyle(.tertiary)
            }
        } footer: {
            Text(lang.t("setup.claudeConfigDir.footer"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var allReady: Bool {
        model.claudeHooksInstalled && model.codexHooksInstalled && model.openCodePluginInstalled
            && model.qoderHooksInstalled && model.qwenCodeHooksInstalled && model.factoryHooksInstalled && model.codebuddyHooksInstalled && model.zcodeHooksInstalled && model.workbuddyHooksInstalled
            && model.cursorHooksInstalled && model.geminiHooksInstalled && model.kimiHooksInstalled
            && model.grokHooksInstalled
            && model.piExtensionInstalled && model.ohMyPiExtensionInstalled && model.claudeUsageInstalled
    }

    @ViewBuilder
    private var emptyStateBanner: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(lang.t("setup.banner.noHooks.title"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(lang.t("setup.banner.noHooks.message"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var codexHookConfigURL: URL? {
        if let hooksURL = model.codexHookStatus?.hooksURL, FileManager.default.fileExists(atPath: hooksURL.path) {
            return hooksURL
        }
        return model.codexHookStatus?.configURL ?? model.codexHookStatus?.hooksURL
    }

    private var geminiHookConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/settings.json")
    }

    private var hasErrors: Bool {
        model.healthReports.contains { !$0.errors.isEmpty }
    }

    private var hasRepairableIssues: Bool {
        model.healthReports.contains { !$0.repairableIssues.isEmpty }
    }

    @ViewBuilder
    private var hookDiagnosticsSection: some View {
        Section {
            ForEach(model.healthReports.filter { !$0.issues.isEmpty }) { report in
                issueList(report: report)
            }

            if model.healthReports.isEmpty {
                HStack {
                    Text(lang.t("setup.diagnostics.notRun"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(lang.t("setup.diagnostics.runCheck")) {
                        model.runHealthChecks()
                    }
                }
            } else if !hasErrors {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(lang.t("setup.diagnostics.allHealthy"))
                    Spacer()
                    Button(lang.t("setup.diagnostics.recheck")) {
                        model.runHealthChecks()
                    }
                    .font(.caption)
                }
            } else {
                HStack(spacing: 10) {
                    Button(lang.t("setup.diagnostics.recheck")) {
                        model.runHealthChecks()
                    }

                    if hasRepairableIssues {
                        Button(lang.t("setup.diagnostics.repair")) {
                            model.repairHooks()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        } header: {
            HStack(spacing: 4) {
                Text(lang.t("setup.section.diagnostics"))
                if hasErrors {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption2)
                }
            }
        }
    }

    @ViewBuilder
    private func issueList(report: HookHealthReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(report.agent.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: issueIcon(for: issue))
                        .font(.caption2)
                        .foregroundStyle(issueColor(for: issue))
                        .frame(width: 14)

                    Text(issue.description)
                        .font(.caption)
                        .foregroundStyle(issue.severity == .info ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let binaryPath = report.binaryPath {
                Text("Binary: \(binaryPath)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func issueIcon(for issue: HookHealthReport.Issue) -> String {
        switch issue.severity {
        case .info: "info.circle.fill"
        case .error: issue.isAutoRepairable ? "wrench.fill" : "exclamationmark.triangle.fill"
        }
    }

    private func issueColor(for issue: HookHealthReport.Issue) -> Color {
        switch issue.severity {
        case .info: .blue
        case .error: issue.isAutoRepairable ? .orange : .red
        }
    }

    @ViewBuilder
    private func hookRow(
        name: String,
        agent: AgentIdentifier,
        installed: Bool,
        configurationKnown: Bool,
        busy: Bool,
        requiresBinary: Bool = true,
        configLocationURL: URL? = nil,
        installAction: @escaping () -> Void,
        uninstallAction: @escaping () -> Void
    ) -> some View {
        let blocked = model.hooks.setupBlockReason(requiresBinary: requiresBinary)
        let sourceDetected = model.hooks.detectedInstallations[agent] != nil
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(name, systemImage: "terminal")
                Spacer()
                if installed {
                    HStack(spacing: 8) {
                        if let configLocationURL {
                            Button {
                                revealInFinder(configLocationURL)
                            } label: {
                                Image(systemName: "arrow.up.forward.square")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(lang.t("setup.revealConfigLocation"))
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(lang.t("setup.connection.configured"))
                                .foregroundStyle(.secondary)
                        }
                        Button(lang.t("setup.connection.remove")) {
                            uninstallAction()
                        }
                        .foregroundStyle(.red)
                        .font(.caption)
                        .disabled(model.hooks.isRuntimeAcceptance || model.hooks.isAutomaticConnectionBusy)
                    }
                } else if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Button(lang.t("setup.connection.configure")) {
                        installAction()
                    }
                    .disabled(blocked != nil || !sourceDetected || model.hooks.isAutomaticConnectionBusy)
                }
            }
            if let blocked {
                Text(lang.t(blocked.rawValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !sourceDetected {
                Text(lang.t("setup.connection.sourceMissing"))
                    .font(.caption).foregroundStyle(.secondary)
            } else if !installed && !busy {
                Text(lang.t(configurationKnown ? "setup.connection.notConfigured" : "setup.connection.unknown"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func desktopConnectionRow(agent: AgentIdentifier, name: String) -> some View {
        let evidence = model.hooks.detectedInstallations[agent]
        let optedOut = model.hooks.intentStore.intent(for: agent) == .uninstalled
        let state = model.hooks.desktopConnectionStates[agent]
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(name, systemImage: "desktopcomputer")
                Spacer()
                if optedOut {
                    Button(lang.t("setup.connection.configure")) { model.hooks.reconnectDesktopSource(agent) }
                } else {
                    Button(lang.t("setup.desktop.stopAutomatic")) { model.hooks.removeDesktopConnectionIntent(agent) }
                }
            }
            Text(optedOut ? lang.t("setup.desktop.optedOut") : model.hooks.automaticConnectionErrors[agent]
                ?? lang.t(evidence == nil ? "setup.connection.sourceMissing" : "setup.desktop." + (state?.rawValue ?? "checking")))
                .font(.caption).foregroundStyle(.secondary)
            if !optedOut, evidence != nil {
                HStack {
                    Button(lang.t("setup.desktop.checkAgain")) { Task { await model.hooks.configureDetectedSources() } }
                    if agent == .miniMaxCodeDesktop && state == .waitingForProfile {
                        Button(lang.t("setup.desktop.chooseDataDirectory")) {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let selected = panel.url { model.hooks.confirmMiniMaxDataDirectory(selected) }
                        }
                    }
                    if let app = evidence?.bundleURL {
                        Button(lang.t("setup.desktop.openSource")) { NSWorkspace.shared.open(app) }
                    }
                }
            }
        }
        .disabled(model.hooks.sourceSetupDisabled || model.hooks.isAutomaticConnectionBusy || evidence == nil)
    }

    private func revealInFinder(_ url: URL) {
        let fileManager = FileManager.default
        let standardizedURL = url.standardizedFileURL

        if fileManager.fileExists(atPath: standardizedURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([standardizedURL])
            return
        }

        let directoryURL = standardizedURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: directoryURL.path) {
            NSWorkspace.shared.open(directoryURL)
        }
    }
}

// MARK: - Watch

struct WatchSettingsPane: View {
    var model: AppModel

    @State private var pairingCode: String = "----"

    var body: some View {
        Form {
            Section {
                Toggle("Watch Notifications", isOn: Binding(
                    get: { model.watchNotificationEnabled },
                    set: { model.watchNotificationEnabled = $0 }
                ))

                if model.watchNotificationEnabled {
                    Text("When enabled, the macOS app broadcasts a Bonjour service that your iPhone can discover on the same WiFi network.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("General")
            }

            if model.watchNotificationEnabled {
                Section("Pairing") {
                    HStack {
                        Text("Pairing Code")
                        Spacer()
                        Text(pairingCode)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundStyle(.blue)
                    }

                    Text("Enter this code on your iPhone app to pair. Code expires after 2 minutes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Refresh Code") {
                        model.watchRelay?.endpoint.regeneratePairingCode()
                        pairingCode = model.watchPairingCode
                    }
                }

                Section("Paired Devices") {
                    if model.watchConnectedDevices > 0 {
                        HStack {
                            Label("iPhone", systemImage: "iphone")
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 7, height: 7)
                                Text("Connected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        HStack {
                            Label("No devices paired", systemImage: "iphone.slash")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Revoke All Pairings", role: .destructive) {
                        model.watchRelay?.endpoint.revokeAllTokens()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Watch")
        .onAppear {
            pairingCode = model.watchPairingCode
        }
    }
}

// MARK: - Placeholder

struct PlaceholderSettingsPane: View {
    var model: AppModel
    let titleKey: String
    let subtitleKey: String

    private var lang: LanguageManager { model.lang }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(lang.t(subtitleKey))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationTitle(lang.t(titleKey))
    }
}

// MARK: - Remote Connection

struct RemoteConnectionSection: View {
    var model: AppModel

    @State private var copiedCommand: String?

    private var remoteSessionCount: Int {
        model.state.sessions.filter(\.isRemote).count
    }

    private var socketName: String {
        "open-island-\(getuid()).sock"
    }

    private var setupCommand: String {
        "./scripts/remote-setup.sh user@host"
    }

    private var sshCommand: String {
        "ssh -R /tmp/\(socketName):/tmp/\(socketName) user@host"
    }

    private var sshConfigSnippet: String {
        """
        Host myserver
            RemoteForward /tmp/\(socketName) /tmp/\(socketName)
        """
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                // Status
                HStack {
                    Label("SSH Remote", systemImage: "network")
                    Spacer()
                    if remoteSessionCount > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 7, height: 7)
                            Text("\(remoteSessionCount) active")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No remote sessions")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text("Monitor Claude Code running on remote servers via SSH.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Step 1
                remoteSetupStep(
                    number: "1",
                    title: "Deploy hooks to remote server",
                    description: "Run from the AIsland repo directory:",
                    command: setupCommand
                )

                // Step 2
                remoteSetupStep(
                    number: "2",
                    title: "Connect with socket forwarding",
                    description: "Add to ~/.ssh/config (recommended):",
                    command: sshConfigSnippet,
                    multiline: true
                )

                // Step 2 alternative
                VStack(alignment: .leading, spacing: 4) {
                    Text("Or connect directly:")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    copyableCommand(sshCommand)
                }

                // Tip
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue.opacity(0.8))
                        .padding(.top, 1)
                    Text("The remote sshd needs `StreamLocalBindUnlink yes` in /etc/ssh/sshd_config for reliable reconnects.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack(spacing: 4) {
                Text("Remote")
                Text("Beta")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func remoteSetupStep(
        number: String,
        title: String,
        description: String,
        command: String,
        multiline: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(number)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(.blue.opacity(0.7)))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            Text(description)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            copyableCommand(command, multiline: multiline)
        }
    }

    @ViewBuilder
    private func copyableCommand(_ command: String, multiline: Bool = false) -> some View {
        let isCopied = copiedCommand == command
        GroupBox {
            HStack(alignment: multiline ? .top : .center) {
                Text(command)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(multiline ? nil : 1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copiedCommand = command
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copiedCommand == command {
                            copiedCommand = nil
                        }
                    }
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(isCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, multiline ? 2 : 0)
        }
    }
}

// MARK: - Update Banner

struct UpdateBanner: View {
    let version: String
    let lang: LanguageManager
    var onUpdate: () -> Void

    var body: some View {
        Button(action: onUpdate) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(lang.t("settings.update.available", version))
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.blue)
            )
        }
        .buttonStyle(.plain)
        .shadow(color: .blue.opacity(0.3), radius: 4, y: 2)
    }
}


/// Progress remains visible in Settings while Sparkle validates and installs.
struct UpdateSettingsStatus: View {
    var checker: UpdateChecker
    var lang: LanguageManager

    private var statusKey: String? {
        switch checker.phase {
        case .idle: nil
        case .checking: "settings.update.checking"
        case .available: "settings.update.ready"
        case .downloading: "settings.update.downloading"
        case .extracting: "settings.update.extracting"
        case .installing: "settings.update.installing"
        case .installed: "settings.update.installed"
        case .upToDate: "settings.update.upToDate"
        case .blocked, .failed: checker.messageKey
        }
    }
    var body: some View {
        if let statusKey {
            VStack(alignment: .leading, spacing: 10) {
                if let version = checker.latestVersion, checker.phase != .upToDate {
                    Text(lang.t("settings.update.latestVersion", version)).font(.headline)
                }
                Text(lang.t(statusKey)).font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.update.status")
                if checker.phase == .checking || checker.phase == .installing {
                    ProgressView().controlSize(.small)
                } else if checker.phase == .downloading {
                    if let progress = checker.downloadProgress {
                        ProgressView(value: progress).accessibilityIdentifier("settings.update.progress")
                    } else { ProgressView().controlSize(.small) }
                    Text(checker.expectedBytes > 0
                         ? "\(ByteCountFormatter.string(fromByteCount: Int64(clamping: checker.downloadedBytes), countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: Int64(clamping: checker.expectedBytes), countStyle: .file))"
                         : ByteCountFormatter.string(fromByteCount: Int64(clamping: checker.downloadedBytes), countStyle: .file))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                } else if checker.phase == .extracting {
                    ProgressView(value: checker.extractionProgress)
                }
                if let detail = checker.errorDetail { Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                HStack {
                    if checker.hasUpdate {
                        Button(lang.t("settings.update.downloadInstall")) { checker.downloadAndInstall() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("settings.update.downloadInstall")
                    }
                    if checker.canCancel { Button(lang.t("settings.update.cancel")) { checker.cancel() } }
                    if checker.canRetryTermination { Button(lang.t("settings.update.retryRelaunch")) { checker.retryRelaunch() } }
                    if let notes = checker.releaseNotesURL {
                        Link(lang.t("settings.update.releaseNotes"), destination: notes)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }
}
