import AppKit
import SwiftUI
import OpenIslandCore

@MainActor
final class OpenIslandAppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private let harnessLaunchConfiguration = HarnessLaunchConfiguration(environment: BloubTrialController.launchEnvironment)
    private lazy var bloubTrialController = BloubTrialController(model: model)
    private let welcomeStore = OnboardingPresentationStore()
    private let welcomeController = OnboardingWindowController()
    private let launchedAt = Date()
    private lazy var harnessRuntimeMonitor = HarnessRuntimeMonitor(launchedAt: launchedAt)

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
                loadRuntimeState: harnessLaunchConfiguration.scenario == nil
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

    private func presentAutomaticWelcome() {
        guard !BloubTrialController.isEnabled, harnessLaunchConfiguration.scenario == nil,
              welcomeStore.claimAutomaticPresentation(
                migrationReady: model.hooks.intentStore.migrationVersion > 0,
                firstLaunchCompleted: model.firstLaunchCompleted
              ) else { return }
        presentWelcome()
    }

    private func presentWelcome() {
        let language = OnboardingLanguage.resolve(
            manualLanguage: model.lang.language.rawValue,
            preferredLanguages: Locale.preferredLanguages
        )
        if !welcomeController.present(
            language: language, initiallyMuted: model.isSoundMuted,
            hapticFeedbackEnabled: model.hapticFeedbackEnabled,
            completion: { [weak self] result in
                guard let self, result != .closed else { return }
                self.model.firstLaunchCompleted = true
                self.model.showOnboarding()
            }
        ), let error = welcomeController.lastError {
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
