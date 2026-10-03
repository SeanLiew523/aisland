import AppKit
import SwiftUI
import OpenIslandCore

@MainActor
final class OpenIslandAppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    private let acceptanceConfiguration: RuntimeAcceptanceConfiguration?
    private let harnessLaunchConfiguration = HarnessLaunchConfiguration(environment: BloubTrialController.launchEnvironment)
    private lazy var bloubTrialController = BloubTrialController(model: model)
    private let welcomeStore: OnboardingPresentationStore
    private var presentedWelcomeLanguage: OnboardingLanguage?
    private let welcomeController = OnboardingWindowController()
    private let launchedAt = Date()
    private lazy var harnessRuntimeMonitor = HarnessRuntimeMonitor(launchedAt: launchedAt)

    override init() {
        do {
            let acceptance = try RuntimeAcceptanceConfiguration.current()
            let defaults = try acceptance?.isolatedPreferences() ?? .standard
            self.acceptanceConfiguration = acceptance
            self.welcomeStore = OnboardingPresentationStore(defaults: defaults)
            self.model = AppModel(acceptanceConfiguration: acceptance, intentDefaults: defaults)
        } catch {
            // No AppModel or production store/bridge is created on invalid
            // opted-in metadata. A distinct acceptance app fails closed.
            fputs("AIsland runtime acceptance configuration is invalid; startup stopped.\n", stderr)
            NSLog("AIsland runtime acceptance startup stopped: %@", String(reflecting: error))
            exit(EXIT_FAILURE)
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination(
            "AIsland should remain active while monitoring local agent sessions."
        )
        ProcessInfo.processInfo.disableSuddenTermination()
        NSApp.setActivationPolicy(model.showDockIcon ? .regular : .accessory)
        harnessRuntimeMonitor.recordMilestone("applicationDidFinishLaunching")

        DispatchQueue.main.async { [self] in
            harnessRuntimeMonitor.recordMilestone("bootstrapStarted")
            model.harnessRuntimeMonitor = harnessRuntimeMonitor
            harnessRuntimeMonitor.recordLog(model.lastActionMessage)

            model.ignoresPointerExitDuringHarness = harnessLaunchConfiguration.scenario != nil
            model.disablesOverlayEventMonitoringDuringHarness =
                harnessLaunchConfiguration.disablesOverlayEventMonitoring
            model.onStartupSetupReady = { [weak self] in self?.presentAutomaticWelcome() }
            model.replayWelcome = { [weak self] in self?.presentWelcome() }
            model.startIfNeeded(
                startBridge: harnessLaunchConfiguration.shouldStartBridge,
                shouldPerformBootAnimation: harnessLaunchConfiguration.shouldPerformBootAnimation,
                loadRuntimeState: harnessLaunchConfiguration.scenario == nil && acceptanceConfiguration == nil
            )
            harnessRuntimeMonitor.recordMilestone("modelStarted")

            if let scenario = harnessLaunchConfiguration.scenario {
                model.loadDebugSnapshot(
                    scenario.snapshot(),
                    presentOverlay: harnessLaunchConfiguration.presentOverlay
                )
            }

            // Hide all windows on launch — settings opens on demand only.
            OpenIslandAppDelegate.hideAllAppWindows()
            if BloubTrialController.isEnabled {
                bloubTrialController.show()
            }

            harnessRuntimeMonitor.recordMilestone("bootstrapCompleted")

            if let captureDelay = harnessLaunchConfiguration.captureDelay,
               harnessLaunchConfiguration.artifactDirectoryURL != nil {
                harnessRuntimeMonitor.recordMilestone(
                    "captureScheduled",
                    message: String(format: "%.3fs", captureDelay)
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + captureDelay) { [self] in
                    harnessRuntimeMonitor.recordMilestone("captureStarted")
                    try? HarnessArtifactRecorder.record(
                        configuration: harnessLaunchConfiguration,
                        model: model,
                        launchedAt: launchedAt,
                        runtimeMonitor: harnessRuntimeMonitor
                    )
                }
            }

            if let autoExitAfter = harnessLaunchConfiguration.autoExitAfter {
                harnessRuntimeMonitor.recordMilestone(
                    "autoExitScheduled",
                    message: String(format: "%.3fs", autoExitAfter)
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + autoExitAfter) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        recordWelcomeReceipt(event: .exited, exit: .termination,
                             language: presentedWelcomeLanguage ?? resolvedWelcomeLanguage())
        welcomeController.stop()
        NotificationSoundService.stop()
    }

    private static func hideAllAppWindows() {
        for window in NSApp.windows {
            window.orderOut(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if welcomeController.isPresenting { return false }
        if BloubTrialController.isEnabled { bloubTrialController.show() }
        else { model.showSettings() }
        return false
    }

    func showBloubTrial() { bloubTrialController.show() }

    private func resolvedWelcomeLanguage() -> OnboardingLanguage {
        OnboardingLanguage.resolve(
            manualLanguage: model.lang.language.rawValue,
            preferredLanguages: Locale.preferredLanguages
        )
    }

    private func recordWelcomeReceipt(
        event: RuntimeAcceptanceConfiguration.WelcomeEvent,
        exit: RuntimeAcceptanceConfiguration.WelcomeExit? = nil,
        language: OnboardingLanguage
    ) {
        guard let acceptanceConfiguration else { return }
        do {
            try acceptanceConfiguration.recordWelcome(
                event: event, exit: exit, language: language.rawValue,
                alreadyPresented: welcomeStore.alreadyPresented,
                firstLaunchCompleted: model.firstLaunchCompleted,
                preferredLanguages: Locale.preferredLanguages
            )
        } catch {
            model.lastActionMessage = "Welcome acceptance receipt could not be recorded."
        }
    }

    private func presentAutomaticWelcome() {
        guard !BloubTrialController.isEnabled, harnessLaunchConfiguration.scenario == nil,
              welcomeStore.claimAutomaticPresentation(
                migrationReady: model.hooks.intentStore.migrationVersion > 0,
                firstLaunchCompleted: model.firstLaunchCompleted
              ) else { return }
        recordWelcomeReceipt(event: .claimed, language: resolvedWelcomeLanguage())
        presentWelcome()
    }

    private func presentWelcome() {
        let language = resolvedWelcomeLanguage()
        let shown = welcomeController.present(
            language: language, initiallyMuted: model.isSoundMuted,
            hapticFeedbackEnabled: model.hapticFeedbackEnabled,
            completion: { [weak self] result in
                guard let self else { return }
                if result != .closed { self.model.firstLaunchCompleted = true }
                let exit: RuntimeAcceptanceConfiguration.WelcomeExit = switch result {
                case .completed: .completed
                case .skipped: .skipped
                case .closed: .closed
                }
                self.recordWelcomeReceipt(event: .exited, exit: exit, language: language)
                self.presentedWelcomeLanguage = nil
                if result != .closed { self.model.showOnboarding() }
            }
        )
        if shown {
            presentedWelcomeLanguage = language
            recordWelcomeReceipt(event: .shown, language: language)
        } else if let error = welcomeController.lastError {
            model.lastActionMessage = error
            model.showOnboarding()
        }
    }
}

@main
struct OpenIslandApp: App {
    @NSApplicationDelegateAdaptor(OpenIslandAppDelegate.self)
    private var appDelegate

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window(AppBrand.settingsWindowTitle, id: "settings") {
            SettingsWindowContent(model: appDelegate.model)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    if BloubTrialController.isEnabled { appDelegate.showBloubTrial() }
                    else {
                        openWindow(id: "settings")
                        appDelegate.model.showSettings()
                    }
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// Refreshes the `openWindow` registration each time the settings
/// window opens, keeping the closure current after window recreation.
private struct SettingsWindowContent: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SettingsView(model: model)
            .onAppear {
                guard !BloubTrialController.isEnabled else { return }
                model.openSettingsWindow = { [openWindow] in
                    openWindow(id: "settings")
                }
            }
    }
}
