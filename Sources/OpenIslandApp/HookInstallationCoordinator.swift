import Foundation
import AppKit
import Observation
import OpenIslandCore

@MainActor
@Observable
final class HookInstallationCoordinator {
    @ObservationIgnored
    let intentStore: AgentIntentStore
    nonisolated let isRuntimeAcceptance: Bool
    nonisolated let sourceSetupAcceptance: RuntimeAcceptanceConfiguration.SourceSetup?
    var sourceSetupDisabled: Bool { isRuntimeAcceptance && sourceSetupAcceptance == nil }

    init(
        intentStore: AgentIntentStore = AgentIntentStore(),
        isRuntimeAcceptance: Bool = false,
        sourceSetupAcceptance: RuntimeAcceptanceConfiguration.SourceSetup? = nil,
        piExtensionInstallationManager: PiExtensionInstallationManager = PiExtensionInstallationManager(agent: .pi),
        ohMyPiExtensionInstallationManager: PiExtensionInstallationManager = PiExtensionInstallationManager(agent: .ohMyPi),
        installationDetector: AgentInstallationDetector = AgentInstallationDetector(),
        hermesInstallationManager: HermesHookInstallationManager = HermesHookInstallationManager()
    ) {
        self.installationDetector = installationDetector
        self.hermesInstallationManager = hermesInstallationManager
        self.intentStore = intentStore
        self.isRuntimeAcceptance = isRuntimeAcceptance || sourceSetupAcceptance != nil
        self.sourceSetupAcceptance = sourceSetupAcceptance
        self.piExtensionInstallationManager = piExtensionInstallationManager
        self.ohMyPiExtensionInstallationManager = ohMyPiExtensionInstallationManager
    }

    @ObservationIgnored private let installationDetector: AgentInstallationDetector
    @ObservationIgnored let hermesInstallationManager: HermesHookInstallationManager
    var detectedInstallations: [AgentIdentifier: AgentInstallationDetector.Evidence] = [:]
    var automaticConnectionErrors: [AgentIdentifier: String] = [:]
    var isAutomaticConnectionBusy = false
    var desktopConnectionStates: [AgentIdentifier: DesktopConnectionInstallationManager.State] = [:]
    @ObservationIgnored private var confirmedMiniMaxDataDirectory: URL?
    @ObservationIgnored private let connectionObservationStarted = Date()
    @ObservationIgnored private var receivedSourceSetupAgents: Set<AgentIdentifier> = []
    var hermesHookStatus: HermesHookInstallationStatus?
    /// Runtime observation is separate from Hermes' persisted consent record.
    /// Profile identity comes from the validated bridge event, never the focused terminal.
    var hermesSessionEventProfiles: Set<String> = []

    var codexHookStatus: CodexHookInstallationStatus?
    var claudeHookStatus: ClaudeHookInstallationStatus?
    var qoderHookStatus: ClaudeHookInstallationStatus?
    var qwenCodeHookStatus: ClaudeHookInstallationStatus?
    var factoryHookStatus: ClaudeHookInstallationStatus?
    var codebuddyHookStatus: ClaudeHookInstallationStatus?
    var zcodeHookStatus: ClaudeHookInstallationStatus?
    var workbuddyHookStatus: ClaudeHookInstallationStatus?
    var openCodePluginStatus: OpenCodePluginInstallationStatus?
    var cursorHookStatus: CursorHookInstallationStatus?
    var geminiHookStatus: GeminiHookInstallationStatus?
    var kimiHookStatus: KimiHookInstallationStatus?
    var grokHookStatus: GrokHookInstallationStatus?
    var piExtensionStatus: PiExtensionInstallationStatus?
    var ohMyPiExtensionStatus: PiExtensionInstallationStatus?
    var claudeStatusLineStatus: ClaudeStatusLineInstallationStatus?
    var claudeUsageSnapshot: ClaudeUsageSnapshot?
    var codexUsageSnapshot: CodexUsageSnapshot?
    var hooksBinaryURL: URL?
    var isCodexSetupBusy = false
    var isClaudeHookSetupBusy = false
    var isQoderHookSetupBusy = false
    var isQwenCodeHookSetupBusy = false
    var isFactoryHookSetupBusy = false
    var isCodebuddyHookSetupBusy = false
    var isZcodeHookSetupBusy = false
    var isWorkbuddyHookSetupBusy = false
    var isOpenCodeSetupBusy = false
    var isCursorHookSetupBusy = false
    var isGeminiHookSetupBusy = false
    var isKimiHookSetupBusy = false
    var isGrokHookSetupBusy = false
    var isPiSetupBusy = false
    var isOhMyPiSetupBusy = false
    var isClaudeUsageSetupBusy = false

    @ObservationIgnored
    var onStatusMessage: ((String) -> Void)?

    @ObservationIgnored
    private let codexHookInstallationManager = CodexHookInstallationManager()

    /// Computed so it always reflects the latest `ClaudeConfigDirectory` setting.
    private var claudeHookInstallationManager: ClaudeHookInstallationManager {
        ClaudeHookInstallationManager()
    }

    @ObservationIgnored
    private let qoderHookInstallationManager = ClaudeHookInstallationManager(
        claudeDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".qoder", isDirectory: true),
        hookSource: "qoder"
    )

    @ObservationIgnored
    private let qwenCodeHookInstallationManager = ClaudeHookInstallationManager(
        claudeDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".qwen", isDirectory: true),
        hookSource: "qwen"
    )

    @ObservationIgnored
    private let factoryHookInstallationManager = ClaudeHookInstallationManager(
        claudeDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".factory", isDirectory: true),
        hookSource: "factory"
    )

    @ObservationIgnored
    private let codebuddyHookInstallationManager = ClaudeHookInstallationManager(
        claudeDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codebuddy", isDirectory: true),
        hookSource: "codebuddy"
    )

    /// ZCode stores Claude-format hook groups nested under
    /// `hooks.events` in `~/.zcode/cli/config.json` and supports a fixed
    /// seven-event set, so it gets its own manager rather than the flat
    /// settings.json path the other CC forks use.
    @ObservationIgnored
    private let zcodeHookInstallationManager = ZCodeHookInstallationManager()

    /// WorkBuddy speaks the Claude hook format in `~/.workbuddy/settings.json`
    /// but only consumes an event subset, so it passes its own event set.
    @ObservationIgnored
    private let workbuddyHookInstallationManager = ClaudeHookInstallationManager(
        claudeDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".workbuddy", isDirectory: true),
        hookSource: "workbuddy",
        hookEvents: ClaudeHookInstaller.workbuddyEventSpecs
    )

    @ObservationIgnored
    private let openCodePluginInstallationManager = OpenCodePluginInstallationManager()

    @ObservationIgnored
    private let cursorHookInstallationManager = CursorHookInstallationManager()

    @ObservationIgnored
    private let geminiHookInstallationManager = GeminiHookInstallationManager()

    @ObservationIgnored
    private let kimiHookInstallationManager = KimiHookInstallationManager()

    @ObservationIgnored
    private let grokHookInstallationManager = GrokHookInstallationManager()
    private let piExtensionInstallationManager: PiExtensionInstallationManager

    @ObservationIgnored
    private let ohMyPiExtensionInstallationManager: PiExtensionInstallationManager

    /// Computed so it always reflects the latest `ClaudeConfigDirectory` setting.
    private var claudeStatusLineInstallationManager: ClaudeStatusLineInstallationManager {
        ClaudeStatusLineInstallationManager()
    }

    @ObservationIgnored
    private var claudeUsageMonitorTask: Task<Void, Never>?

    @ObservationIgnored
    private var codexUsageMonitorTask: Task<Void, Never>?

    @ObservationIgnored
    private var relativeTimestampFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }

    private var isolatedStatusTitle: String {
        LanguageManager.shared.language.resolvedCode.hasPrefix("zh") ? "独立验收 · 未安装" : "Isolated acceptance · not installed"
    }
    private var isolatedStatusSummary: String {
        if sourceSetupAcceptance != nil {
            return LanguageManager.shared.language.resolvedCode.hasPrefix("zh") ? "此独立验收仅配置清单中的 Hermes、DeepSeek 与 MiniMaxCode 桌面；其它来源配置保持原样。" : "This isolated case configures only its listed Hermes, DeepSeek and MiniMaxCode Desktop sources; other source configurations are preserved."
        }
        return LanguageManager.shared.language.resolvedCode.hasPrefix("zh") ? "来源读取与安装已停用。" : "Source reads and installation are disabled."
    }

    // MARK: - Computed display properties

    enum SetupBlockReason: String {
        case isolatedAcceptance = "setup.connection.isolated"
        case sourceSetupScope = "setup.connection.sourceSetupScope"
        case missingHooksBinary = "setup.connection.missingHelper"
    }

    /// This describes AIsland's configuration prerequisites, not whether the
    /// source agent is installed or its runtime connection has been verified.
    func setupBlockReason(requiresBinary: Bool) -> SetupBlockReason? {
        if sourceSetupAcceptance != nil { return .sourceSetupScope }
        if isRuntimeAcceptance { return .isolatedAcceptance }
        if requiresBinary && hooksBinaryURL == nil { return .missingHooksBinary }
        return nil
    }

    var codexHooksInstalled: Bool {
        codexHookStatus?.managedHooksPresent == true
    }

    var claudeHooksInstalled: Bool {
        claudeHookStatus?.managedHooksPresent == true
    }

    var qoderHooksInstalled: Bool {
        qoderHookStatus?.managedHooksPresent == true
    }

    var qwenCodeHooksInstalled: Bool {
        qwenCodeHookStatus?.managedHooksPresent == true
    }

    var factoryHooksInstalled: Bool {
        factoryHookStatus?.managedHooksPresent == true
    }

    var codebuddyHooksInstalled: Bool {
        codebuddyHookStatus?.managedHooksPresent == true
    }

    var zcodeHooksInstalled: Bool {
        zcodeHookStatus?.managedHooksPresent == true
    }

    var workbuddyHooksInstalled: Bool {
        workbuddyHookStatus?.managedHooksPresent == true
    }

    var openCodePluginInstalled: Bool {
        openCodePluginStatus?.isInstalled == true
    }

    var cursorHooksInstalled: Bool {
        cursorHookStatus?.managedHooksPresent == true
    }

    var geminiHooksInstalled: Bool {
        geminiHookStatus?.managedHooksPresent == true
    }

    var kimiHooksInstalled: Bool {
        kimiHookStatus?.managedHooksPresent == true
    }

    var grokHooksInstalled: Bool {
        grokHookStatus?.managedHooksPresent == true
    }

    var piExtensionInstalled: Bool {
        piExtensionStatus?.isInstalled == true
    }

    var ohMyPiExtensionInstalled: Bool {
        ohMyPiExtensionStatus?.isInstalled == true
    }

    var claudeUsageInstalled: Bool {
        claudeStatusLineStatus?.managedStatusLineInstalled == true
    }

    var claudeHookStatusTitle: String {
        if isRuntimeAcceptance { return isolatedStatusTitle }
        if claudeHooksInstalled {
            return "Claude hooks installed"
        }

        if hooksBinaryURL == nil {
            return "Hook binary not found"
        }

        return "Claude hooks not installed"
    }

    var claudeHookStatusSummary: String {
        if isRuntimeAcceptance { return isolatedStatusSummary }
        guard let status = claudeHookStatus else {
            return "Reading \(ClaudeConfigDirectory.resolved().appendingPathComponent("settings.json").path)."
        }

        if claudeHooksInstalled {
            if status.hasClaudeIslandHooks {
                return "managed hooks present · claude-island hooks also detected"
            }
            return "managed hooks present"
        }

        if hooksBinaryURL == nil {
            return "Build OpenIslandHooks before installing."
        }

        if status.hasClaudeIslandHooks {
            return "claude-island hooks detected · managed hooks absent"
        }

        return "no managed Claude hooks"
    }

    var claudeUsageStatusTitle: String {
        if isRuntimeAcceptance { return isolatedStatusTitle }
        guard let status = claudeStatusLineStatus else {
            return "Claude usage status unavailable"
        }

        if status.managedStatusLineInstalled {
            return "Claude usage bridge installed"
        }

        if status.managedStatusLineNeedsRepair {
            return "Claude usage bridge needs repair"
        }

        if status.hasConflictingStatusLine {
            return "Custom Claude status line detected"
        }

        return "Claude usage bridge not installed"
    }

    var claudeUsageStatusSummary: String {
        if isRuntimeAcceptance { return isolatedStatusSummary }
        guard let status = claudeStatusLineStatus else {
            return "Reading \(ClaudeConfigDirectory.resolved().appendingPathComponent("settings.json").path)."
        }

        if status.managedStatusLineInstalled {
            if let summary = claudeUsageSummaryText {
                return "Caching rate limits from Claude Code · \(summary)"
            }
            return "Caching rate limits from Claude Code into \(status.cacheURL.path)."
        }

        if status.managedStatusLineNeedsRepair {
            return "AIsland detected a missing managed Claude status line script and will repair it automatically."
        }

        if status.hasConflictingStatusLine {
            return "AIsland will not overwrite an existing Claude status line automatically."
        }

        return "Install a managed Claude status line to cache 5h and 7d usage locally."
    }

    var claudeUsageSummaryText: String? {
        guard let snapshot = claudeUsageSnapshot else {
            return nil
        }

        var components: [String] = []
        if let fiveHour = snapshot.fiveHour {
            components.append("5h \(fiveHour.roundedUsedPercentage)%")
        }
        if let sevenDay = snapshot.sevenDay {
            components.append("7d \(sevenDay.roundedUsedPercentage)%")
        }
        if let cachedAt = snapshot.cachedAt {
            components.append("updated \(relativeTimestampFormatter.localizedString(for: cachedAt, relativeTo: .now))")
        }
        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    var codexUsageStatusTitle: String {
        if isRuntimeAcceptance { return isolatedStatusTitle }
        if codexUsageSnapshot?.isEmpty == false {
            return "Codex rate limits detected"
        }

        return "Waiting for Codex rate limits"
    }

    var codexUsageStatusSummary: String {
        if isRuntimeAcceptance { return isolatedStatusSummary }
        if let summary = codexUsageSummaryText {
            return "Reading the latest local rollout token_count snapshots · \(summary)"
        }

        return "Passively reading ~/.codex/sessions/**/rollout-*.jsonl and extracting token_count.rate_limits."
    }

    var codexUsageSummaryText: String? {
        guard let snapshot = codexUsageSnapshot else {
            return nil
        }

        var components = snapshot.windows.map { window in
            "\(window.label) \(window.roundedUsedPercentage)%"
        }

        if let planType = snapshot.planType {
            components.append("plan \(planType)")
        }

        if let capturedAt = snapshot.capturedAt {
            components.append("updated \(relativeTimestampFormatter.localizedString(for: capturedAt, relativeTo: .now))")
        }

        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    var openCodePluginStatusTitle: String {
        if isRuntimeAcceptance { return isolatedStatusTitle }
        if openCodePluginInstalled {
            return "OpenCode plugin installed"
        }

        return "OpenCode plugin not installed"
    }

    var openCodePluginStatusSummary: String {
        if isRuntimeAcceptance { return isolatedStatusSummary }
        guard let status = openCodePluginStatus else {
            return "Reading ~/.config/opencode state."
        }

        if status.isInstalled {
            return "managed plugin present in \(status.pluginsDirectory.path)"
        }

        if status.pluginFilePresent && !status.pluginRegistered {
            return "plugin file present but not registered in config.json"
        }

        return "no managed OpenCode plugin"
    }

    var cursorHookStatusTitle: String {
        if isRuntimeAcceptance { return isolatedStatusTitle }
        if cursorHooksInstalled {
            return "Cursor hooks installed"
        }

        if hooksBinaryURL == nil {
            return "Hook binary not found"
        }

        return "Cursor hooks not installed"
    }

    var cursorHookStatusSummary: String {
        if isRuntimeAcceptance { return isolatedStatusSummary }
        guard cursorHookStatus != nil else {
            return "Reading ~/.cursor/hooks.json."
        }

        if cursorHooksInstalled {
            return "managed hooks present"
        }

        if hooksBinaryURL == nil {
            return "Build OpenIslandHooks before installing."
        }

        return "no managed Cursor hooks"
    }

    var geminiHookStatusTitle: String {
        if isRuntimeAcceptance { return isolatedStatusTitle }
        guard let status = geminiHookStatus else { return "Gemini hooks loading" }
        return status.managedHooksPresent ? "Gemini hooks installed" : "Gemini hooks not installed"
    }

    var geminiHookStatusSummary: String {
        if isRuntimeAcceptance { return isolatedStatusSummary }
        guard let status = geminiHookStatus else {
            return "Reading ~/.gemini/settings.json."
        }

        if hooksBinaryURL == nil {
            return "Build OpenIslandHooks before installing."
        }

        return status.managedHooksPresent ? "managed hooks present" : "no managed Gemini hooks"
    }

    var kimiHookStatusTitle: String {
        if isRuntimeAcceptance { return isolatedStatusTitle }
        if kimiHooksInstalled {
            return "Kimi hooks installed"
        }

        if hooksBinaryURL == nil {
            return "Hook binary not found"
        }

        return "Kimi hooks not installed"
    }

    var kimiHookStatusSummary: String {
        if isRuntimeAcceptance { return isolatedStatusSummary }
        guard kimiHookStatus != nil else {
            return "Reading ~/.kimi/config.toml."
        }

        if kimiHooksInstalled {
            return "managed hooks present"
        }

        if hooksBinaryURL == nil {
            return "Build OpenIslandHooks before installing."
        }

        return "no managed Kimi hooks"
    }

    var grokHookStatusTitle: String {
        if isRuntimeAcceptance { return isolatedStatusTitle }
        if grokHooksInstalled {
            return "Grok hooks installed"
        }

        if hooksBinaryURL == nil {
            return "Hook binary not found"
        }

        return "Grok hooks not installed"
    }

    var grokHookStatusSummary: String {
        if isRuntimeAcceptance { return isolatedStatusSummary }
        guard grokHookStatus != nil else {
            return "Reading ~/.grok/hooks/open-island.json."
        }

        if grokHooksInstalled {
            return "managed hooks present"
        }

        if hooksBinaryURL == nil {
            return "Build OpenIslandHooks before installing."
        }

        return "no managed Grok hooks"
    }

    var codexHookStatusTitle: String {
        if isRuntimeAcceptance { return isolatedStatusTitle }
        if codexHooksInstalled {
            return "Codex hooks installed"
        }

        if hooksBinaryURL == nil {
            return "Hook binary not found"
        }

        return "Codex hooks not installed"
    }

    var codexHookStatusSummary: String {
        if isRuntimeAcceptance { return isolatedStatusSummary }
        guard let status = codexHookStatus else {
            return "Reading ~/.codex state."
        }

        if codexHooksInstalled {
            let featureText = status.featureFlagEnabled ? "feature on" : "feature off"
            return "\(featureText) · managed hooks present"
        }

        if hooksBinaryURL == nil {
            return "Build OpenIslandHooks before installing."
        }

        return status.featureFlagEnabled ? "feature on · no managed hooks" : "feature off · no managed hooks"
    }

    // MARK: - Claude config directory

    /// Updates the custom Claude config directory, cleans up old hooks if present, and refreshes status.
    func updateClaudeConfigDirectory(to newDirectory: URL?) {
        guard !isRuntimeAcceptance else { return }
        let oldDirectory = ClaudeConfigDirectory.resolved()
        let oldHadHooks = claudeHookStatus?.managedHooksPresent == true

        ClaudeConfigDirectory.customDirectory = newDirectory

        // Refresh status from the new directory
        refreshClaudeHookStatus()
        refreshClaudeUsageState()

        let newPath = ClaudeConfigDirectory.resolved().path
        if oldHadHooks {
            let oldPath = oldDirectory.path
            if oldPath != newPath {
                onStatusMessage?("Claude config directory changed to \(newPath). Hooks in \(oldPath) were not removed — uninstall them manually if no longer needed.")
            }
        } else {
            onStatusMessage?("Claude config directory set to \(newPath).")
        }
    }

    // MARK: - Auto-update hooks binary

    /// Overwrites the installed hooks binary if the app bundle ships a newer version.
    /// Call once at startup after hooksBinaryURL is set.
    func updateHooksBinaryIfNeeded() {
        guard !isRuntimeAcceptance else { return }
        guard let sourceURL = hooksBinaryURL else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let source = sourceURL
                let updated = try await Task.detached(priority: .utility) {
                    try ManagedHooksBinary.updateIfNeeded(from: source)
                }.value
                if updated {
                    self.onStatusMessage?("Hooks binary updated to match the current app version.")
                    self.refreshCodexHookStatus()
                    self.refreshClaudeHookStatus()
                    self.refreshCursorHookStatus()
                }
            } catch {
                self.onStatusMessage?("Failed to update hooks binary: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Health check & auto-repair

    var codexHealthReport: HookHealthReport?
    var claudeHealthReport: HookHealthReport?
    var openCodeHealthReport: HookHealthReport?

    /// Every report produced by the last check, in display order.
    var healthReports: [HookHealthReport] {
        [claudeHealthReport, codexHealthReport, openCodeHealthReport].compactMap(\.self)
    }


    /// Runs health checks for Claude, Codex and OpenCode hooks.
    func runHealthChecks() {
        guard !isRuntimeAcceptance else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }

            let binaryURL = self.hooksBinaryURL
            let (claudeReport, codexReport, openCodeReport) = await Task.detached(priority: .utility) {
                let claude = HookHealthCheck.checkClaude(hooksBinaryURL: binaryURL)
                let codex = HookHealthCheck.checkCodex(hooksBinaryURL: binaryURL)
                let openCode = HookHealthCheck.checkOpenCode()
                return (claude, codex, openCode)
            }.value

            self.claudeHealthReport = claudeReport
            self.codexHealthReport = codexReport
            self.openCodeHealthReport = openCodeReport

            if !claudeReport.isHealthy || !codexReport.isHealthy || !openCodeReport.isHealthy {
                let claudeIssueCount = claudeReport.errors.count
                let codexIssueCount = codexReport.errors.count
                let openCodeIssueCount = openCodeReport.errors.count
                self.onStatusMessage?("Hook health check: \(claudeIssueCount) Claude, \(codexIssueCount) Codex, \(openCodeIssueCount) OpenCode issue(s).")
            }
        }
    }

    /// Attempts to auto-repair repairable issues by re-installing hooks.
    /// Returns true if any repairs were attempted.
    @discardableResult
    func repairHooksIfNeeded() async -> Bool {
        guard !isRuntimeAcceptance else { return false }
        var repaired = false

        // Re-run health checks first
        let binaryURL = hooksBinaryURL
        let (claudeReport, codexReport, openCodeReport) = await Task.detached(priority: .utility) {
            let claude = HookHealthCheck.checkClaude(hooksBinaryURL: binaryURL)
            let codex = HookHealthCheck.checkCodex(hooksBinaryURL: binaryURL)
            let openCode = HookHealthCheck.checkOpenCode()
            return (claude, codex, openCode)
        }.value

        claudeHealthReport = claudeReport
        codexHealthReport = codexReport
        openCodeHealthReport = openCodeReport

        // Repair Claude hooks if there are repairable issues
        if !claudeReport.repairableIssues.isEmpty, hooksBinaryURL != nil, detectedInstallations[.claudeCode] != nil, intentStore.intent(for: .claudeCode) != .uninstalled {
            onStatusMessage?("Repairing Claude hooks: \(claudeReport.repairableIssues.map(\.description).joined(separator: "; "))")
            installClaudeHooks()
            repaired = true
        }

        // Repair Codex hooks if there are repairable issues
        if !codexReport.repairableIssues.isEmpty, hooksBinaryURL != nil, detectedInstallations[.codex] != nil, intentStore.intent(for: .codex) != .uninstalled {
            onStatusMessage?("Repairing Codex hooks: \(codexReport.repairableIssues.map(\.description).joined(separator: "; "))")
            installCodexHooks()
            repaired = true
        }

        // Repair OpenCode plugin if there are repairable issues
        if !openCodeReport.repairableIssues.isEmpty, detectedInstallations[.openCode] != nil, intentStore.intent(for: .openCode) != .uninstalled {
            onStatusMessage?("Repairing OpenCode plugin: \(openCodeReport.repairableIssues.map(\.description).joined(separator: "; "))")
            installOpenCodePlugin()
            repaired = true
        }

        // Refresh health reports after repair
        if repaired {
            try? await Task.sleep(for: .milliseconds(500))
            let (updatedClaude, updatedCodex, updatedOpenCode) = await Task.detached(priority: .utility) {
                let claude = HookHealthCheck.checkClaude(hooksBinaryURL: binaryURL)
                let codex = HookHealthCheck.checkCodex(hooksBinaryURL: binaryURL)
                let openCode = HookHealthCheck.checkOpenCode()
                return (claude, codex, openCode)
            }.value
            claudeHealthReport = updatedClaude
            codexHealthReport = updatedCodex
            openCodeHealthReport = updatedOpenCode

            if updatedClaude.isHealthy && updatedCodex.isHealthy && updatedOpenCode.isHealthy {
                onStatusMessage?("Hook repair completed successfully.")
            } else {
                let remaining = updatedClaude.errors.count + updatedCodex.errors.count + updatedOpenCode.errors.count
                onStatusMessage?("Hook repair finished with \(remaining) remaining issue(s).")
            }
        }

        return repaired
    }

    // MARK: - Refresh

    func refreshCodexHookStatus() {
        guard !isRuntimeAcceptance else { return }
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.codexHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.codexHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to read Codex hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshClaudeHookStatus() {
        guard !isRuntimeAcceptance else { return }
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.claudeHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.claudeHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to read Claude hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshCCForkHookStatuses() {
        guard !isRuntimeAcceptance else { return }
        refreshCCForkHookStatus(manager: qoderHookInstallationManager, name: "Qoder") { [weak self] in self?.qoderHookStatus = $0 }
        refreshCCForkHookStatus(manager: qwenCodeHookInstallationManager, name: "Qwen Code") { [weak self] in self?.qwenCodeHookStatus = $0 }
        refreshCCForkHookStatus(manager: factoryHookInstallationManager, name: "Factory") { [weak self] in self?.factoryHookStatus = $0 }
        refreshCCForkHookStatus(manager: codebuddyHookInstallationManager, name: "CodeBuddy") { [weak self] in self?.codebuddyHookStatus = $0 }
        refreshCCForkHookStatus(manager: zcodeHookInstallationManager, name: "ZCode") { [weak self] in self?.zcodeHookStatus = $0 }
        refreshCCForkHookStatus(manager: workbuddyHookInstallationManager, name: "WorkBuddy") { [weak self] in self?.workbuddyHookStatus = $0 }
    }

    private func refreshCCForkHookStatus(
        manager: any ClaudeFormatHookInstallationManaging,
        name: String,
        apply: @MainActor @escaping (ClaudeHookInstallationStatus) -> Void
    ) {
        guard !isRuntimeAcceptance else { return }
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try manager.status(hooksBinaryURL: self.hooksBinaryURL)
                apply(status)
            } catch {
                self.onStatusMessage?("Failed to read \(name) hook status: \(error.localizedDescription)")
            }
        }
    }

    /// Awaitable versions of refresh for use in startup flow to avoid race conditions.
    func refreshAllHookStatusAndWait() async {
        guard !sourceSetupDisabled else { return }
        if detectedInstallations[.hermes] != nil {
            do { hermesHookStatus = try await Task.detached { [hermesInstallationManager, hooksBinaryURL] in
                try hermesInstallationManager.status(hooksBinaryURL: hooksBinaryURL)
            }.value } catch { automaticConnectionErrors[.hermes] = error.localizedDescription }
        }
        // The dedicated source-setup case never reads unrelated hook configs,
        // usage caches or repairs the optional usage bridge.
        if sourceSetupAcceptance != nil { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try self.claudeHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                    self.claudeHookStatus = status
                } catch {
                    self.onStatusMessage?("Failed to read Claude hook status: \(error.localizedDescription)")
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try self.codexHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                    self.codexHookStatus = status
                } catch {
                    self.onStatusMessage?("Failed to read Codex hook status: \(error.localizedDescription)")
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try self.openCodePluginInstallationManager.status()
                    self.openCodePluginStatus = status
                } catch {
                    self.onStatusMessage?("Failed to read OpenCode plugin status: \(error.localizedDescription)")
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let usageState = try self.readClaudeUsageState(repairManagedBridgeIfNeeded: true)
                    self.claudeStatusLineStatus = usageState.status
                    self.claudeUsageSnapshot = usageState.snapshot
                } catch {
                    self.onStatusMessage?("Failed to read Claude usage state: \(error.localizedDescription)")
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do { self.cursorHookStatus = try self.cursorHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL) }
                catch { self.onStatusMessage?("Failed to read Cursor hook status: \(error.localizedDescription)") }
            }

            // CC fork agents
            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                for (manager, name, apply) in [
                    (self.qoderHookInstallationManager, "Qoder", { @MainActor @Sendable [weak self] (s: ClaudeHookInstallationStatus) in self?.qoderHookStatus = s }),
                    (self.qwenCodeHookInstallationManager, "Qwen Code", { @MainActor @Sendable [weak self] (s: ClaudeHookInstallationStatus) in self?.qwenCodeHookStatus = s }),
                    (self.factoryHookInstallationManager, "Factory", { @MainActor @Sendable [weak self] (s: ClaudeHookInstallationStatus) in self?.factoryHookStatus = s }),
                    (self.codebuddyHookInstallationManager, "CodeBuddy", { @MainActor @Sendable [weak self] (s: ClaudeHookInstallationStatus) in self?.codebuddyHookStatus = s }),
                    (self.zcodeHookInstallationManager, "ZCode", { @MainActor @Sendable [weak self] (s: ClaudeHookInstallationStatus) in self?.zcodeHookStatus = s }),
                    (self.workbuddyHookInstallationManager, "WorkBuddy", { @MainActor @Sendable [weak self] (s: ClaudeHookInstallationStatus) in self?.workbuddyHookStatus = s }),
                ] as [(any ClaudeFormatHookInstallationManaging, String, @MainActor @Sendable (ClaudeHookInstallationStatus) -> Void)] {
                    do {
                        let status = try manager.status(hooksBinaryURL: self.hooksBinaryURL)
                        apply(status)
                    } catch {
                        self.onStatusMessage?("Failed to read \(name) hook status: \(error.localizedDescription)")
                    }
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try self.geminiHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                    self.geminiHookStatus = status
                } catch {
                    self.onStatusMessage?("Failed to read Gemini hook status: \(error.localizedDescription)")
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try self.kimiHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                    self.kimiHookStatus = status
                } catch {
                    self.onStatusMessage?("Failed to read Kimi hook status: \(error.localizedDescription)")
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try self.grokHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                    self.grokHookStatus = status
                } catch {
                    self.onStatusMessage?("Failed to read Grok hook status: \(error.localizedDescription)")
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                self.loadPiExtensionStatuses()
            }
        }
    }

    func refreshOpenCodePluginStatus() {
        guard !isRuntimeAcceptance else { return }
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.openCodePluginInstallationManager.status()
                self.openCodePluginStatus = status
            } catch {
                self.onStatusMessage?("Failed to read OpenCode plugin status: \(error.localizedDescription)")
            }
        }
    }

    func refreshCursorHookStatus() {
        guard !isRuntimeAcceptance else { return }
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.cursorHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.cursorHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to read Cursor hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshGeminiHookStatus() {
        guard !isRuntimeAcceptance else { return }
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.geminiHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.geminiHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to read Gemini hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshKimiHookStatus() {
        guard !isRuntimeAcceptance else { return }
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.kimiHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.kimiHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to read Kimi hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshGrokHookStatus() {
        guard !isRuntimeAcceptance else { return }
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.grokHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.grokHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to read Grok hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshPiExtensionStatuses() {
        guard !isRuntimeAcceptance else { return }
        Task { [weak self] in
            guard let self else { return }
            self.loadPiExtensionStatuses()
        }
    }

    /// Reads Pi and Oh My Pi installation status independently so one
    /// corrupted manifest cannot block the other agent's status refresh.
    func loadPiExtensionStatuses() {
        guard !isRuntimeAcceptance else { return }
        do {
            piExtensionStatus = try piExtensionInstallationManager.status()
        } catch {
            onStatusMessage?(
                "Failed to read Pi extension status: \(error.localizedDescription)"
            )
        }

        do {
            ohMyPiExtensionStatus = try ohMyPiExtensionInstallationManager.status()
        } catch {
            onStatusMessage?(
                "Failed to read Oh My Pi extension status: \(error.localizedDescription)"
            )
        }
    }

    func refreshClaudeUsageState() {
        guard !isRuntimeAcceptance else { return }
        let manager = claudeStatusLineInstallationManager
        Task { [weak self] in
            guard let self else { return }

            do {
                let usageState = try await Task.detached(priority: .utility) {
                    var status = try manager.status()
                    var repairedManagedBridge = false
                    if status.managedStatusLineNeedsRepair {
                        status = try manager.install()
                        repairedManagedBridge = true
                    }
                    let snapshot = try ClaudeUsageLoader.load()
                    return (status: status, snapshot: snapshot, repairedManagedBridge: repairedManagedBridge)
                }.value
                self.claudeStatusLineStatus = usageState.status
                self.claudeUsageSnapshot = usageState.snapshot
                if usageState.repairedManagedBridge {
                    self.onStatusMessage?("Recovered the Claude usage bridge after repairing a missing managed script.")
                }
            } catch {
                self.onStatusMessage?("Failed to read Claude usage state: \(error.localizedDescription)")
            }
        }
    }

    func refreshCodexUsageState() {
        guard !isRuntimeAcceptance else { return }
        Task { [weak self] in
            guard let self else { return }

            do {
                let snapshot = try await Task.detached(priority: .utility) {
                    try CodexUsageLoader.load()
                }.value
                self.codexUsageSnapshot = snapshot
            } catch {
                self.onStatusMessage?("Failed to read Codex usage state: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Intent-aware helpers

    func runStartupSetup(onReady: () -> Void) async {
        var wrapperFailed = false
        if let sourceSetupAcceptance {
            do { hooksBinaryURL = try sourceSetupAcceptance.prepareHooksWrapper() }
            catch {
                wrapperFailed = true
                for agent in sourceSetupAcceptance.agents { automaticConnectionErrors[agent] = "The isolated callback helper could not be prepared. No source configuration was changed." }
            }
        }
        await detectInstalledSources()
        await refreshAllHookStatusAndWait()
        recordSourceSetupStates()
        migrateIntentStoreIfNeeded()
        onReady()
        if !wrapperFailed { await configureDetectedSources() }
    }

    /// Only detected sources are admitted. Explicit removal survives both
    /// first launch and future source installations. Untouched detected sources
    /// are configured on each startup/re-scan, independently of onboarding.
    func detectInstalledSources() async {
        guard !sourceSetupDisabled else { return }
        detectedInstallations = await Task.detached { [installationDetector] in installationDetector.detect() }.value
    }

    /// Sequential configuration: completion reflects the installer result,
    /// rather than an unawaited UI action or a fixed delay.
    func configureDetectedSources() async {
        guard !sourceSetupDisabled, !isAutomaticConnectionBusy else { return }
        isAutomaticConnectionBusy = true
        defer { isAutomaticConnectionBusy = false }
        await detectInstalledSources()
        for agent in AgentIdentifier.allCases where shouldAutoInstall(agent) {
            do {
                try await configureDetectedSource(agent)
                automaticConnectionErrors[agent] = nil
                if agent == .deepSeekDesktop || agent == .miniMaxCodeDesktop {
                    if desktopConnectionStates[agent] == .waitingForProfile || desktopConnectionStates[agent] == .waitingForSourceExit { continue }
                }
                intentStore.setIntent(.installed, for: agent)
                automaticConnectionErrors[agent] = nil
            } catch {
                automaticConnectionErrors[agent] = error.localizedDescription
                onStatusMessage?("\(agent.rawValue): \(error.localizedDescription)")
            }
        }
        await refreshAllHookStatusAndWait()
        recordSourceSetupStates()
    }

    private func recordSourceSetupStates() {
        guard let sourceSetupAcceptance else { return }
        for agent in sourceSetupAcceptance.agents {
            let state: RuntimeAcceptanceConfiguration.SourceSetup.ConnectionState
            if intentStore.intent(for: agent) == .uninstalled { state = .cancelled }
            else if automaticConnectionErrors[agent] != nil { state = .error }
            else if detectedInstallations[agent] == nil { state = .absent }
            else if let desktop = desktopConnectionStates[agent] {
                switch desktop {
                case .waitingForProfile: state = .waitingForProfile
                case .waitingForSourceExit: state = .waitingForSourceExit
                case .waitingForActivation: state = .waitingForActivation
                case .configuredFiles: state = .configured
                case .eventReceived: state = .eventReceived
                }
            } else if receivedSourceSetupAgents.contains(agent) { state = .eventReceived }
            else if agent == .hermes && hermesHookStatus?.isCurrent == true { state = hermesHookStatus?.hasConsent == true ? .configured : .waitingForConsent }
            else { state = .installed }
            do { try sourceSetupAcceptance.record(agent: agent, state: state) }
            catch { onStatusMessage?("Isolated source-setup receipt could not be written.") }
        }
    }

    private func configureDetectedSource(_ agent: AgentIdentifier) async throws {
        if let sourceSetupAcceptance, !sourceSetupAcceptance.agents.contains(agent) { return }
        if agent == .deepSeekDesktop || agent == .miniMaxCodeDesktop {
            try await configureDesktopSource(agent)
            return
        }
        if agent == .pi || agent == .ohMyPi {
            guard let data = loadBundledPiExtension() else { throw AutomaticConnectionError.missingExtension }
            let manager = agent == .pi ? piExtensionInstallationManager : ohMyPiExtensionInstallationManager
            let updated = try await Task.detached { try manager.install(extensionSourceData: data) }.value
            if agent == .pi { piExtensionStatus = updated } else { ohMyPiExtensionStatus = updated }
            return
        }
        if agent == .openCode {
            guard let data = loadBundledOpenCodePlugin() else { throw AutomaticConnectionError.missingExtension }
            let manager = openCodePluginInstallationManager
            _ = try await Task.detached { try manager.install(pluginSourceData: data) }.value
            return
        }
        guard let binary = hooksBinaryURL else { throw HermesHookInstallationError.missingBinary }
        let action: @Sendable () throws -> Void
        switch agent {
        case .claudeCode: let manager = claudeHookInstallationManager; action = { _ = try manager.install(hooksBinaryURL: binary) }
        case .codex: let manager = codexHookInstallationManager; action = { _ = try manager.install(hooksBinaryURL: binary) }
        case .cursor: let manager = cursorHookInstallationManager; action = { _ = try manager.install(hooksBinaryURL: binary) }
        case .qoder: let manager = qoderHookInstallationManager; action = { _ = try manager.install(hooksBinaryURL: binary) }
        case .qwenCode: let manager = qwenCodeHookInstallationManager; action = { _ = try manager.install(hooksBinaryURL: binary) }
        case .factory: let manager = factoryHookInstallationManager; action = { _ = try manager.install(hooksBinaryURL: binary) }
        case .codebuddy: let manager = codebuddyHookInstallationManager; action = { _ = try manager.install(hooksBinaryURL: binary) }
        case .zcode: let manager = zcodeHookInstallationManager; action = { _ = try manager.install(hooksBinaryURL: binary) }
        case .workbuddy: let manager = workbuddyHookInstallationManager; action = { _ = try manager.install(hooksBinaryURL: binary) }
        case .gemini: let manager = geminiHookInstallationManager; action = { _ = try manager.install(hooksBinaryURL: binary) }
        case .kimi: let manager = kimiHookInstallationManager; action = { _ = try manager.install(hooksBinaryURL: binary) }
        case .grok: let manager = grokHookInstallationManager; action = { _ = try manager.install(hooksBinaryURL: binary) }
        case .openCode: return
        case .hermes:
            let manager = hermesInstallationManager
            if let sourceSetupAcceptance { try sourceSetupAcceptance.backupHermesConfiguration(profileURL: manager.profileDirectory) }
            action = { _ = try manager.install(hooksBinaryURL: binary) }
        case .pi, .ohMyPi, .claudeUsageBridge, .deepSeekDesktop, .miniMaxCodeDesktop: return
        }
        try await Task.detached(priority: .utility) { try action() }.value
    }

    func observeDesktopConnectionEvent(_ event: AgentEvent) {
        guard !sourceSetupDisabled, case let .sessionStarted(start) = event,
              start.timestamp >= connectionObservationStarted, start.origin == .live else { return }
        let agent: AgentIdentifier?
        switch start.tool {
        case .deepseekHarness: agent = .deepSeekDesktop
        case .minimaxCodeDesktop: agent = .miniMaxCodeDesktop
        case .hermesCLI: agent = .hermes
        default: agent = nil
        }
        if let agent {
            if agent == .hermes, let profile = start.jumpTarget?.runtimeProfileID,
               profile.hasPrefix("/") {
                hermesSessionEventProfiles.insert(URL(fileURLWithPath: profile).standardizedFileURL.path)
            }
            if agent != .hermes { desktopConnectionStates[agent] = .eventReceived }
            receivedSourceSetupAgents.insert(agent)
            recordSourceSetupStates()
        }
    }

    func cancelSourceSetupHermes() {
        guard sourceSetupAcceptance?.agents.contains(.hermes) == true, !isAutomaticConnectionBusy else { return }
        intentStore.setIntent(.uninstalled, for: .hermes)
        recordSourceSetupStates()
    }

    func confirmMiniMaxDataDirectory(_ directory: URL) {
        guard !sourceSetupDisabled else { return }
        confirmedMiniMaxDataDirectory = directory.standardizedFileURL
        Task { await configureDetectedSources() }
    }

    func removeDesktopConnectionIntent(_ agent: AgentIdentifier) {
        guard !sourceSetupDisabled, !isAutomaticConnectionBusy,
              agent == .deepSeekDesktop || agent == .miniMaxCodeDesktop else { return }
        // A source-side disable/removal still belongs to the source plugin UI.
        // Preserve a durable opt-out so startup/re-scan cannot re-enable it.
        intentStore.setIntent(.uninstalled, for: agent)
        recordSourceSetupStates()
    }

    func reconnectDesktopSource(_ agent: AgentIdentifier) {
        guard !sourceSetupDisabled, !isAutomaticConnectionBusy,
              agent == .deepSeekDesktop || agent == .miniMaxCodeDesktop else { return }
        intentStore.setIntent(.untouched, for: agent)
        Task { await configureDetectedSources() }
    }

    private func configureDesktopSource(_ agent: AgentIdentifier) async throws {
        guard let evidence = detectedInstallations[agent], let app = evidence.bundleURL else { return }
        guard let packages = Bundle.appResources.url(forResource: "AgentIntegrationPackages", withExtension: nil) else { throw AutomaticConnectionError.missingExtension }
        let node = installationDetector.executableDirectories.map { $0.appendingPathComponent("node") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
        let probe = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/MiniMaxCodeSourceProbe")
        let manager = DesktopConnectionInstallationManager(supportDirectory: sourceSetupAcceptance?.supportURL,
            packagesDirectory: packages, nodeURL: node, bundledProbeURL: probe,
            bridgeSocketURL: sourceSetupAcceptance?.socketURL ?? BridgeSocketLocation.defaultURL,
            preservesPreviousHelper: sourceSetupAcceptance != nil)
        if agent == .miniMaxCodeDesktop {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.minimax.agent")
                .filter { !$0.isTerminated && $0.bundleURL?.resolvingSymlinksInPath() == app.resolvingSymlinksInPath() }
            let pid = running.count == 1 ? running[0].processIdentifier : nil
            let explicit = confirmedMiniMaxDataDirectory
            let state = try await Task.detached {
                let discovered = if let pid { try? MiniMaxCodeActiveDataDirectory.resolve(processID: pid, appURL: app) } else { nil as URL? }
                return try manager.configureMiniMax(evidence: evidence, activeDataDirectory: discovered ?? explicit)
            }.value
            if desktopConnectionStates[agent] != .eventReceived { desktopConnectionStates[agent] = state }
        } else {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.deepseek.dsh").contains { !$0.isTerminated }
            let state = try await Task.detached { try manager.configureDeepSeek(evidence: evidence, sourceRunning: running) }.value
            if desktopConnectionStates[agent] != .eventReceived { desktopConnectionStates[agent] = state }
        }
    }

    private enum AutomaticConnectionError: LocalizedError {
        case missingExtension
        var errorDescription: String? { "The bundled AIsland event extension is unavailable." }
    }

    func shouldAutoInstall(_ agent: AgentIdentifier) -> Bool {
        guard !sourceSetupDisabled else { return false }
        if let sourceSetupAcceptance, !sourceSetupAcceptance.agents.contains(agent) { return false }
        guard intentStore.shouldAutomaticallyConfigure(agent, installationDetected: detectedInstallations[agent] != nil, configurationCurrent: false) else {
            return false
        }

        switch agent {
        case .claudeCode: return claudeHookStatus?.isCurrent != true
        case .codex: return codexHookStatus?.isCurrent != true
        case .cursor: return !cursorHooksInstalled
        case .qoder: return qoderHookStatus?.isCurrent != true
        case .qwenCode: return qwenCodeHookStatus?.isCurrent != true
        case .factory: return factoryHookStatus?.isCurrent != true
        case .codebuddy: return codebuddyHookStatus?.isCurrent != true
        case .zcode: return zcodeHookStatus?.isCurrent != true
        case .workbuddy: return workbuddyHookStatus?.isCurrent != true
        case .openCode: return !openCodePluginInstalled
        case .gemini: return !geminiHooksInstalled
        case .kimi: return !kimiHooksInstalled
        case .grok: return !grokHooksInstalled
        case .pi: return !(piExtensionStatus?.isCurrent ?? false)
        case .ohMyPi: return !(ohMyPiExtensionStatus?.isCurrent ?? false)
        case .claudeUsageBridge: return false
        case .hermes: return hermesHookStatus?.isCurrent != true
        case .deepSeekDesktop, .miniMaxCodeDesktop: return true
        }
    }

    // MARK: - Intent store migration

    /// Reconciles the persisted intent store with the hook status currently
    /// observed on disk. Must be called only after
    /// `refreshAllHookStatusAndWait()` has returned, otherwise every agent
    /// will be recorded as `.untouched` and legacy users will have their
    /// installed hooks silently forgotten.
    func migrateIntentStoreIfNeeded() {
        if isRuntimeAcceptance {
            // Maintain the calling acceptance domain's onboarding readiness;
            // no source inspection or installation is performed.
            intentStore.migrateFromLegacyStateIfNeeded { _ in false }
            return
        }
        intentStore.migrateFromLegacyStateIfNeeded { [self] agent in
            switch agent {
            case .claudeCode: return claudeHooksInstalled
            case .codex: return codexHooksInstalled
            case .cursor: return cursorHooksInstalled
            case .qoder: return qoderHooksInstalled
            case .qwenCode: return qwenCodeHooksInstalled
            case .factory: return factoryHooksInstalled
            case .codebuddy: return codebuddyHooksInstalled
            case .zcode: return zcodeHooksInstalled
            case .workbuddy: return workbuddyHooksInstalled
            case .openCode: return openCodePluginInstalled
            case .gemini: return geminiHooksInstalled
            case .kimi: return kimiHooksInstalled
            case .grok: return grokHooksInstalled
            case .pi: return piExtensionInstalled
            case .ohMyPi: return ohMyPiExtensionInstalled
            case .claudeUsageBridge: return claudeUsageInstalled
            case .hermes: return hermesHookStatus?.isInstalled == true
            case .deepSeekDesktop, .miniMaxCodeDesktop: return false
            }
        }
    }

    // MARK: - Install / uninstall

    func installCodexHooks() {
        guard !isRuntimeAcceptance else { return }
        guard let hooksBinaryURL else {
            onStatusMessage?("Could not find a local OpenIslandHooks binary. Build the package first.")
            return
        }

        updateCodexHooks(userMessage: "Installing Codex hooks.", intent: .installed) { manager in
            try manager.install(hooksBinaryURL: hooksBinaryURL)
        }
    }

    func uninstallCodexHooks() {
        guard !isRuntimeAcceptance else { return }
        updateCodexHooks(userMessage: "Removing Codex hooks.", intent: .uninstalled) { manager in
            try manager.uninstall()
        }
    }

    func installClaudeHooks() {
        guard !isRuntimeAcceptance else { return }
        guard let hooksBinaryURL else {
            onStatusMessage?("Could not find a local OpenIslandHooks binary. Build the package first.")
            return
        }

        updateClaudeHooks(userMessage: "Installing Claude hooks.", intent: .installed) { manager in
            try manager.install(hooksBinaryURL: hooksBinaryURL)
        }
    }

    func uninstallClaudeHooks() {
        guard !isRuntimeAcceptance else { return }
        updateClaudeHooks(userMessage: "Removing Claude hooks.", intent: .uninstalled) { manager in
            try manager.uninstall()
        }
    }

    func installQoderHooks() {
        guard !isRuntimeAcceptance else { return }
        updateCCForkHooks(manager: qoderHookInstallationManager, name: "Qoder", agent: .qoder, isBusySetter: { [weak self] in self?.isQoderHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.qoderHookStatus = $0 }, install: true)
    }

    func uninstallQoderHooks() {
        guard !isRuntimeAcceptance else { return }
        updateCCForkHooks(manager: qoderHookInstallationManager, name: "Qoder", agent: .qoder, isBusySetter: { [weak self] in self?.isQoderHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.qoderHookStatus = $0 }, install: false)
    }

    func installQwenCodeHooks() {
        guard !isRuntimeAcceptance else { return }
        updateCCForkHooks(manager: qwenCodeHookInstallationManager, name: "Qwen Code", agent: .qwenCode, isBusySetter: { [weak self] in self?.isQwenCodeHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.qwenCodeHookStatus = $0 }, install: true)
    }

    func uninstallQwenCodeHooks() {
        guard !isRuntimeAcceptance else { return }
        updateCCForkHooks(manager: qwenCodeHookInstallationManager, name: "Qwen Code", agent: .qwenCode, isBusySetter: { [weak self] in self?.isQwenCodeHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.qwenCodeHookStatus = $0 }, install: false)
    }

    func installFactoryHooks() {
        guard !isRuntimeAcceptance else { return }
        updateCCForkHooks(manager: factoryHookInstallationManager, name: "Factory", agent: .factory, isBusySetter: { [weak self] in self?.isFactoryHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.factoryHookStatus = $0 }, install: true)
    }

    func uninstallFactoryHooks() {
        guard !isRuntimeAcceptance else { return }
        updateCCForkHooks(manager: factoryHookInstallationManager, name: "Factory", agent: .factory, isBusySetter: { [weak self] in self?.isFactoryHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.factoryHookStatus = $0 }, install: false)
    }

    func installCodebuddyHooks() {
        guard !isRuntimeAcceptance else { return }
        updateCCForkHooks(manager: codebuddyHookInstallationManager, name: "CodeBuddy", agent: .codebuddy, isBusySetter: { [weak self] in self?.isCodebuddyHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.codebuddyHookStatus = $0 }, install: true)
    }

    func uninstallCodebuddyHooks() {
        guard !isRuntimeAcceptance else { return }
        updateCCForkHooks(manager: codebuddyHookInstallationManager, name: "CodeBuddy", agent: .codebuddy, isBusySetter: { [weak self] in self?.isCodebuddyHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.codebuddyHookStatus = $0 }, install: false)
    }

    func installZcodeHooks() {
        guard !isRuntimeAcceptance else { return }
        updateCCForkHooks(manager: zcodeHookInstallationManager, name: "ZCode", agent: .zcode, isBusySetter: { [weak self] in self?.isZcodeHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.zcodeHookStatus = $0 }, install: true)
    }

    func uninstallZcodeHooks() {
        guard !isRuntimeAcceptance else { return }
        updateCCForkHooks(manager: zcodeHookInstallationManager, name: "ZCode", agent: .zcode, isBusySetter: { [weak self] in self?.isZcodeHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.zcodeHookStatus = $0 }, install: false)
    }

    func installWorkbuddyHooks() {
        guard !isRuntimeAcceptance else { return }
        updateCCForkHooks(manager: workbuddyHookInstallationManager, name: "WorkBuddy", agent: .workbuddy, isBusySetter: { [weak self] in self?.isWorkbuddyHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.workbuddyHookStatus = $0 }, install: true)
    }

    func uninstallWorkbuddyHooks() {
        guard !isRuntimeAcceptance else { return }
        updateCCForkHooks(manager: workbuddyHookInstallationManager, name: "WorkBuddy", agent: .workbuddy, isBusySetter: { [weak self] in self?.isWorkbuddyHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.workbuddyHookStatus = $0 }, install: false)
    }

    private func updateCCForkHooks(
        manager: any ClaudeFormatHookInstallationManaging,
        name: String,
        agent: AgentIdentifier,
        isBusySetter: @MainActor @escaping (Bool) -> Void,
        statusSetter: @MainActor @escaping (ClaudeHookInstallationStatus) -> Void,
        install: Bool
    ) {
        guard !isRuntimeAcceptance else { return }
        guard let hooksBinaryURL else {
            onStatusMessage?("Could not find a local OpenIslandHooks binary. Build the package first.")
            return
        }

        isBusySetter(true)
        onStatusMessage?(install ? "Installing \(name) hooks." : "Removing \(name) hooks.")

        Task { [weak self] in
            guard let self else { return }

            defer { isBusySetter(false) }

            do {
                let status = install
                    ? try manager.install(hooksBinaryURL: hooksBinaryURL)
                    : try manager.uninstall()
                statusSetter(status)
                self.intentStore.setIntent(install ? .installed : .uninstalled, for: agent)
                if status.managedHooksPresent {
                    self.onStatusMessage?("\(name) hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("\(name) hooks are not installed.")
                }
            } catch {
                self.onStatusMessage?("\(name) hook update failed: \(error.localizedDescription)")
            }
        }
    }

    func installOpenCodePlugin() {
        guard !isRuntimeAcceptance else { return }
        guard let pluginData = loadBundledOpenCodePlugin() else {
            onStatusMessage?("Could not find the bundled OpenCode plugin resource.")
            return
        }

        isOpenCodeSetupBusy = true
        onStatusMessage?("Installing OpenCode plugin.")

        Task { [weak self] in
            guard let self else { return }

            defer { self.isOpenCodeSetupBusy = false }

            do {
                let status = try self.openCodePluginInstallationManager.install(pluginSourceData: pluginData)
                self.openCodePluginStatus = status
                self.intentStore.setIntent(.installed, for: .openCode)
                if status.isInstalled {
                    self.onStatusMessage?("OpenCode plugin is installed. Restart OpenCode to activate.")
                } else {
                    self.onStatusMessage?("OpenCode plugin installation incomplete.")
                }
            } catch {
                self.onStatusMessage?("OpenCode plugin install failed: \(error.localizedDescription)")
            }
        }
    }

    func uninstallOpenCodePlugin() {
        guard !isRuntimeAcceptance else { return }
        isOpenCodeSetupBusy = true
        onStatusMessage?("Removing OpenCode plugin.")

        Task { [weak self] in
            guard let self else { return }

            defer { self.isOpenCodeSetupBusy = false }

            do {
                let status = try self.openCodePluginInstallationManager.uninstall()
                self.openCodePluginStatus = status
                self.intentStore.setIntent(.uninstalled, for: .openCode)
                self.onStatusMessage?("OpenCode plugin removed.")
            } catch {
                self.onStatusMessage?("OpenCode plugin removal failed: \(error.localizedDescription)")
            }
        }
    }

    func installCursorHooks() {
        guard !isRuntimeAcceptance else { return }
        guard let hooksBinaryURL else {
            onStatusMessage?("Could not find a local OpenIslandHooks binary. Build the package first.")
            return
        }

        updateCursorHooks(userMessage: "Installing Cursor hooks.", intent: .installed) { manager in
            try manager.install(hooksBinaryURL: hooksBinaryURL)
        }
    }

    func uninstallCursorHooks() {
        guard !isRuntimeAcceptance else { return }
        updateCursorHooks(userMessage: "Removing Cursor hooks.", intent: .uninstalled) { manager in
            try manager.uninstall()
        }
    }

    func installGeminiHooks() {
        guard !isRuntimeAcceptance else { return }
        guard let hooksBinaryURL else {
            onStatusMessage?("Could not find a local OpenIslandHooks binary. Build the package first.")
            return
        }

        updateGeminiHooks(userMessage: "Installing Gemini hooks.", intent: .installed) { manager in
            try manager.install(hooksBinaryURL: hooksBinaryURL)
        }
    }

    func uninstallGeminiHooks() {
        guard !isRuntimeAcceptance else { return }
        updateGeminiHooks(userMessage: "Removing Gemini hooks.", intent: .uninstalled) { manager in
            try manager.uninstall()
        }
    }

    func installKimiHooks() {
        guard !isRuntimeAcceptance else { return }
        guard let hooksBinaryURL else {
            onStatusMessage?("Could not find a local OpenIslandHooks binary. Build the package first.")
            return
        }

        updateKimiHooks(userMessage: "Installing Kimi hooks.", intent: .installed) { manager in
            try manager.install(hooksBinaryURL: hooksBinaryURL)
        }
    }

    func uninstallKimiHooks() {
        guard !isRuntimeAcceptance else { return }
        updateKimiHooks(userMessage: "Removing Kimi hooks.", intent: .uninstalled) { manager in
            try manager.uninstall()
        }
    }

    func installGrokHooks() {
        guard !isRuntimeAcceptance else { return }
        guard let hooksBinaryURL else {
            onStatusMessage?("Could not find a local OpenIslandHooks binary. Build the package first.")
            return
        }

        updateGrokHooks(userMessage: "Installing Grok hooks.", intent: .installed) { manager in
            try manager.install(hooksBinaryURL: hooksBinaryURL)
        }
    }

    func uninstallGrokHooks() {
        guard !isRuntimeAcceptance else { return }
        updateGrokHooks(userMessage: "Removing Grok hooks.", intent: .uninstalled) { manager in
            try manager.uninstall()
        }
    }

    func installPiExtension() {
        guard !isRuntimeAcceptance else { return }
        updatePiExtension(
            manager: piExtensionInstallationManager,
            agent: .pi,
            name: "Pi",
            status: \.piExtensionStatus,
            busy: \.isPiSetupBusy,
            install: true
        )
    }

    func uninstallPiExtension() {
        guard !isRuntimeAcceptance else { return }
        updatePiExtension(
            manager: piExtensionInstallationManager,
            agent: .pi,
            name: "Pi",
            status: \.piExtensionStatus,
            busy: \.isPiSetupBusy,
            install: false
        )
    }

    func installOhMyPiExtension() {
        guard !isRuntimeAcceptance else { return }
        updatePiExtension(
            manager: ohMyPiExtensionInstallationManager,
            agent: .ohMyPi,
            name: "Oh My Pi",
            status: \.ohMyPiExtensionStatus,
            busy: \.isOhMyPiSetupBusy,
            install: true
        )
    }

    func uninstallOhMyPiExtension() {
        guard !isRuntimeAcceptance else { return }
        updatePiExtension(
            manager: ohMyPiExtensionInstallationManager,
            agent: .ohMyPi,
            name: "Oh My Pi",
            status: \.ohMyPiExtensionStatus,
            busy: \.isOhMyPiSetupBusy,
            install: false
        )
    }

    private func updatePiExtension(
        manager: PiExtensionInstallationManager,
        agent: AgentIdentifier,
        name: String,
        status: ReferenceWritableKeyPath<HookInstallationCoordinator, PiExtensionInstallationStatus?>,
        busy: ReferenceWritableKeyPath<HookInstallationCoordinator, Bool>,
        install: Bool
    ) {
        guard !isRuntimeAcceptance else { return }
        let sourceData: Data?
        if install {
            sourceData = loadBundledPiExtension()
            guard sourceData != nil else {
                onStatusMessage?("Could not find the bundled Pi extension resource.")
                return
            }
        } else {
            sourceData = nil
        }

        self[keyPath: busy] = true
        onStatusMessage?(install ? "Installing \(name) extension." : "Removing \(name) extension.")
        Task { [weak self] in
            guard let self else { return }
            defer { self[keyPath: busy] = false }
            do {
                let updated = if let sourceData {
                    try manager.install(extensionSourceData: sourceData)
                } else {
                    try manager.uninstall()
                }
                self[keyPath: status] = updated
                self.intentStore.setIntent(install ? .installed : .uninstalled, for: agent)
                self.onStatusMessage?(
                    updated.isInstalled
                        ? "\(name) extension is installed. Restart \(name) or run /reload to activate."
                        : "\(name) extension removed."
                )
            } catch {
                self.onStatusMessage?("\(name) extension update failed: \(error.localizedDescription)")
            }
        }
    }

    func installClaudeUsageBridge() {
        guard !isRuntimeAcceptance else { return }
        updateClaudeUsageBridge(userMessage: "Installing Claude usage bridge.", intent: .installed) { manager in
            do {
                return try manager.install()
            } catch ClaudeStatusLineInstallationError.existingStatusLineConflict {
                // User already has a custom statusLine (e.g. claude-hud). Install as a
                // wrapper so their script keeps running and we still get rate_limits.
                return try manager.installAsWrapper()
            }
        }
    }

    func uninstallClaudeUsageBridge() {
        guard !isRuntimeAcceptance else { return }
        updateClaudeUsageBridge(userMessage: "Removing Claude usage bridge.", intent: .uninstalled) { manager in
            try manager.uninstall()
        }
    }

    // MARK: - Monitoring

    func startClaudeUsageMonitoringIfNeeded() {
        guard !isRuntimeAcceptance else { return }
        guard claudeUsageMonitorTask == nil else { return }

        claudeUsageMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                self.refreshClaudeUsageState()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func startCodexUsageMonitoringIfNeeded() {
        guard !isRuntimeAcceptance else { return }
        guard codexUsageMonitorTask == nil else { return }

        codexUsageMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                self.refreshCodexUsageState()
                try? await Task.sleep(for: .seconds(120))
            }
        }
    }

    // MARK: - Internal: readClaudeUsageState

    nonisolated func readClaudeUsageState(
        repairManagedBridgeIfNeeded: Bool
    ) throws -> (
        status: ClaudeStatusLineInstallationStatus,
        snapshot: ClaudeUsageSnapshot?,
        repairedManagedBridge: Bool
    ) {
        guard !isRuntimeAcceptance else { throw RuntimeAcceptanceConfiguration.ConfigurationError.unsafePath }
        let manager = ClaudeStatusLineInstallationManager()
        var status = try manager.status()
        var repairedManagedBridge = false

        if repairManagedBridgeIfNeeded && status.managedStatusLineNeedsRepair {
            status = try manager.install()
            repairedManagedBridge = true
        }

        let snapshot = try ClaudeUsageLoader.load()
        return (status, snapshot, repairedManagedBridge)
    }

    // MARK: - Private helpers

    private func updateCodexHooks(
        userMessage: String,
        intent: AgentHookIntent,
        operation: @escaping (CodexHookInstallationManager) throws -> CodexHookInstallationStatus
    ) {
        guard !isRuntimeAcceptance else { return }
        isCodexSetupBusy = true
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isCodexSetupBusy = false }

            do {
                let status = try operation(self.codexHookInstallationManager)
                self.codexHookStatus = status
                self.intentStore.setIntent(intent, for: .codex)
                if status.managedHooksPresent {
                    self.onStatusMessage?("Codex hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("Codex hooks are not installed.")
                }
            } catch {
                self.onStatusMessage?("Codex hook update failed: \(error.localizedDescription)")
            }
        }
    }

    private func updateClaudeHooks(
        userMessage: String,
        intent: AgentHookIntent,
        operation: @escaping (ClaudeHookInstallationManager) throws -> ClaudeHookInstallationStatus
    ) {
        guard !isRuntimeAcceptance else { return }
        isClaudeHookSetupBusy = true
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isClaudeHookSetupBusy = false }

            do {
                let status = try operation(self.claudeHookInstallationManager)
                self.claudeHookStatus = status
                self.intentStore.setIntent(intent, for: .claudeCode)
                if status.managedHooksPresent {
                    self.onStatusMessage?(status.hasClaudeIslandHooks
                        ? "Claude hooks are installed. claude-island hooks are also still present."
                        : "Claude hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("Claude hooks are not installed.")
                }
            } catch {
                self.onStatusMessage?("Claude hook update failed: \(error.localizedDescription)")
            }
        }
    }

    private func updateCursorHooks(
        userMessage: String,
        intent: AgentHookIntent,
        operation: @escaping (CursorHookInstallationManager) throws -> CursorHookInstallationStatus
    ) {
        guard !isRuntimeAcceptance else { return }
        isCursorHookSetupBusy = true
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isCursorHookSetupBusy = false }

            do {
                let status = try operation(self.cursorHookInstallationManager)
                self.cursorHookStatus = status
                self.intentStore.setIntent(intent, for: .cursor)
                if status.managedHooksPresent {
                    self.onStatusMessage?("Cursor hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("Cursor hooks are not installed.")
                }
            } catch {
                self.onStatusMessage?("Cursor hook update failed: \(error.localizedDescription)")
            }
        }
    }

    private func updateGeminiHooks(
        userMessage: String,
        intent: AgentHookIntent,
        operation: @escaping (GeminiHookInstallationManager) throws -> GeminiHookInstallationStatus
    ) {
        guard !isRuntimeAcceptance else { return }
        isGeminiHookSetupBusy = true
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isGeminiHookSetupBusy = false }

            do {
                let status = try operation(self.geminiHookInstallationManager)
                self.geminiHookStatus = status
                self.intentStore.setIntent(intent, for: .gemini)
                if status.managedHooksPresent {
                    self.onStatusMessage?("Gemini hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("Gemini hooks are not installed.")
                }
            } catch {
                self.onStatusMessage?("Gemini hook update failed: \(error.localizedDescription)")
            }
        }
    }

    private func updateKimiHooks(
        userMessage: String,
        intent: AgentHookIntent,
        operation: @escaping (KimiHookInstallationManager) throws -> KimiHookInstallationStatus
    ) {
        guard !isRuntimeAcceptance else { return }
        isKimiHookSetupBusy = true
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isKimiHookSetupBusy = false }

            do {
                let status = try operation(self.kimiHookInstallationManager)
                self.kimiHookStatus = status
                self.intentStore.setIntent(intent, for: .kimi)
                if status.managedHooksPresent {
                    self.onStatusMessage?("Kimi hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("Kimi hooks are not installed.")
                }
            } catch {
                self.onStatusMessage?("Kimi hook update failed: \(error.localizedDescription)")
            }
        }
    }

    private func updateGrokHooks(
        userMessage: String,
        intent: AgentHookIntent,
        operation: @escaping (GrokHookInstallationManager) throws -> GrokHookInstallationStatus
    ) {
        guard !isRuntimeAcceptance else { return }
        isGrokHookSetupBusy = true
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isGrokHookSetupBusy = false }

            do {
                let status = try operation(self.grokHookInstallationManager)
                self.grokHookStatus = status
                self.intentStore.setIntent(intent, for: .grok)
                if status.managedHooksPresent {
                    self.onStatusMessage?("Grok hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("Grok hooks are not installed.")
                }
            } catch {
                self.onStatusMessage?("Grok hook update failed: \(error.localizedDescription)")
            }
        }
    }

    private func updateClaudeUsageBridge(
        userMessage: String,
        intent: AgentHookIntent,
        operation: @escaping (ClaudeStatusLineInstallationManager) throws -> ClaudeStatusLineInstallationStatus
    ) {
        guard !isRuntimeAcceptance else { return }
        isClaudeUsageSetupBusy = true
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isClaudeUsageSetupBusy = false }

            do {
                let status = try operation(self.claudeStatusLineInstallationManager)
                self.claudeStatusLineStatus = status
                self.claudeUsageSnapshot = try ClaudeUsageLoader.load()
                self.intentStore.setIntent(intent, for: .claudeUsageBridge)
                if status.managedStatusLineInstalled {
                    if status.managedStatusLineIsWrapper {
                        self.onStatusMessage?("Claude usage bridge installed in wrapper mode — your existing statusLine is preserved. Start a Claude Code turn to refresh cached rate limits.")
                    } else {
                        self.onStatusMessage?("Claude usage bridge is installed. Start a Claude Code turn to refresh cached rate limits.")
                    }
                } else {
                    self.onStatusMessage?("Claude usage bridge is not installed.")
                }
            } catch {
                self.onStatusMessage?("Claude usage bridge update failed: \(error.localizedDescription)")
            }
        }
    }

    private func loadBundledOpenCodePlugin() -> Data? {
        // Use appResources which searches both Contents/Resources/ and .app root
        if let url = Bundle.appResources.url(forResource: "open-island-opencode", withExtension: "js") {
            return try? Data(contentsOf: url)
        }

        // Fallback: Bundle.main for Xcode builds
        if let url = Bundle.main.url(forResource: "open-island-opencode", withExtension: "js") {
            return try? Data(contentsOf: url)
        }

        return nil
    }

    private func loadBundledPiExtension() -> Data? {
        if let url = Bundle.appResources.url(forResource: "open-island-pi", withExtension: "ts") {
            return try? Data(contentsOf: url)
        }
        if let url = Bundle.main.url(forResource: "open-island-pi", withExtension: "ts") {
            return try? Data(contentsOf: url)
        }
        return nil
    }
}
