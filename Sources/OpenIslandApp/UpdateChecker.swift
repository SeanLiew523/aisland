import Foundation
import Sparkle

@MainActor
@Observable
final class UpdateChecker: NSObject {
    static let releasesURL = URL(string: "https://github.com/SeanLiew523/aisland/releases")!
    enum Phase: Equatable {
        case idle, checking, available, downloading, extracting, installing, installed, upToDate, blocked, failed
    }
    private(set) var phase: Phase = .idle
    private(set) var latestVersion: String?
    private(set) var messageKey: String?
    private(set) var errorDetail: String?
    private(set) var downloadedBytes: UInt64 = 0
    private(set) var expectedBytes: UInt64 = 0
    private(set) var extractionProgress: Double = 0
    var canCheckForUpdates: Bool { ![.checking, .available, .downloading, .extracting, .installing].contains(phase) }
    var hasUpdate: Bool { phase == .available }
    var downloadProgress: Double? {
        expectedBytes > 0 ? min(1, Double(downloadedBytes) / Double(expectedBytes)) : nil
    }
    var canCancel: Bool { checkTask != nil || cancellation != nil || updateReply != nil }
    var canRetryTermination: Bool { retryTermination != nil }
    var releaseNotesURL: URL? { release?.htmlURL }
    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private var release: GitHubUpdateRelease?
    @ObservationIgnored private var updateReply: ((SPUUserUpdateChoice) -> Void)?
    @ObservationIgnored private var cancellation: (() -> Void)?
    @ObservationIgnored private var retryTermination: (() -> Void)?
    @ObservationIgnored private var checkGeneration = UUID()
    @ObservationIgnored private var installationAuthorized = false
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private let client: GitHubUpdateClient
    @ObservationIgnored private let bundle: Bundle

    init(client: GitHubUpdateClient = GitHubUpdateClient(), bundle: Bundle = .main) {
        self.client = client
        self.bundle = bundle
        super.init()
    }
    /// Checks are explicitly initiated from Settings; starting the app does not
    /// schedule a feed request or permit replacing a local development build.
    func startIfNeeded() {}

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        phase = .checking
        messageKey = nil
        errorDetail = nil
        latestVersion = nil
        release = nil
        installationAuthorized = false
        checkGeneration = UUID()
        let generation = checkGeneration
        checkTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == checkGeneration { checkTask = nil } }
            do {
                let candidate = try await client.latestRelease()
                guard generation == checkGeneration else { return }
                try Task.checkCancellation()
                guard let current = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                      let currentVersion = UpdateVersion(current), let next = UpdateVersion(candidate.version) else {
                    block("settings.update.invalidCurrentVersion")
                    return
                }
                latestVersion = candidate.version
                guard next > currentVersion else { phase = .upToDate; return }
                release = candidate
                guard UpdateInstallationConfiguration.isReady(bundle.infoDictionary ?? [:]) else {
                    block("settings.update.signingNotConfigured"); return
                }
                guard candidate.feedURL != nil else { block("settings.update.missingFeed"); return }
                if updater == nil {
                    let newUpdater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: self, delegate: self)
                    newUpdater.automaticallyChecksForUpdates = false
                    newUpdater.automaticallyDownloadsUpdates = false
                    try newUpdater.start()
                    newUpdater.clearFeedURLFromUserDefaults()
                    updater = newUpdater
                }
                updater?.checkForUpdates()
            } catch is CancellationError {
                guard generation == checkGeneration else { return }
                phase = .idle
            } catch {
                guard generation == checkGeneration else { return }
                fail((error as? GitHubUpdateError)?.messageKey ?? "settings.update.networkFailed", error: error)
            }
        }
    }
    /// The user authorizes downloading AND installing/relaunching with one click.
    func downloadAndInstall() {
        guard phase == .available, let reply = updateReply else { return }
        updateReply = nil
        installationAuthorized = true
        phase = .downloading
        downloadedBytes = 0
        expectedBytes = 0
        reply(.install)
    }
    func cancel() {
        checkGeneration = UUID()
        checkTask?.cancel()
        checkTask = nil
        let cancel = cancellation
        let reply = updateReply
        cancellation = nil
        updateReply = nil
        cancel?()
        reply?(.dismiss)
        phase = .idle
    }
    func retryRelaunch() { retryTermination?() }
    private func block(_ key: String) { phase = .blocked; messageKey = key }
    private func fail(_ key: String, error: Error? = nil) {
        phase = .failed; messageKey = key; errorDetail = error?.localizedDescription
    }
}

extension UpdateChecker: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? { release?.feedURL?.absoluteString }
    func allowedChannels(for updater: SPUUpdater) -> Set<String> { [] }
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }
    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool { false }
}

extension UpdateChecker: SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        phase = .checking; self.cancellation = cancellation
    }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        cancellation = nil
        guard let release, appcastItem.signingValidationStatus == .succeeded,
              !appcastItem.isInformationOnlyUpdate, !appcastItem.isMajorUpgrade,
              appcastItem.displayVersionString == release.version,
              let url = appcastItem.fileURL,
              release.archive(matching: url, length: appcastItem.contentLength) != nil else {
            block("settings.update.invalidFeed")
            reply(.dismiss)
            return
        }
        latestVersion = appcastItem.displayVersionString
        phase = .available
        updateReply = reply
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        // Metadata promised a newer release, so an empty/incompatible feed is a
        // delivery problem, never a claim that the installed app is current.
        block("settings.update.unavailableForSystem")
        acknowledgement()
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        fail("settings.update.installFailed", error: error)
        acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        phase = .downloading; downloadedBytes = 0; expectedBytes = 0; self.cancellation = cancellation
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { expectedBytes = expectedContentLength }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        let (total, overflow) = downloadedBytes.addingReportingOverflow(length)
        downloadedBytes = overflow ? UInt64.max : total
    }
    func showDownloadDidStartExtractingUpdate() {
        cancellation = nil; phase = .extracting; extractionProgress = 0
    }
    func showExtractionReceivedProgress(_ progress: Double) { extractionProgress = progress.isFinite ? max(0, min(1, progress)) : 0 }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard installationAuthorized else {
            phase = .available
            updateReply = reply
            return
        }
        phase = .installing
        reply(.install)
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        phase = .installing
        retryTermination = applicationTerminated ? nil : retryTerminatingApplication
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        phase = .installed; acknowledgement()
    }
    func dismissUpdateInstallation() {
        cancellation = nil; updateReply = nil; retryTermination = nil
        if [.checking, .available, .downloading, .extracting].contains(phase) { phase = .idle }
    }
}
