import AppKit
import ApplicationServices
import Foundation
import Darwin
import OpenIslandCore

enum MiniMaxCodeConversationFocusResult: Equatable, Sendable {
    case focused
    case unavailable(String)
}

struct MiniMaxCodeConversationUI: Sendable {
    struct Source: Equatable, Sendable {
        var bundleIdentifier: String
        var version: String
        var processID: pid_t
    }
    // Test UIs remain available by default; the production adapter checks TCC.
    var isAccessibilityAvailable: @Sendable () -> Bool = { true }
    var source: @Sendable () -> Source?
    var select: @Sendable (MiniMaxCodeConversationMetadata, Source, TimeInterval) -> Bool
    var copyActiveSessionID: @Sendable (MiniMaxCodeConversationMetadata, Source, TimeInterval) -> String?
    var isFrontmost: @Sendable (Source) -> Bool
}

/// Selects an existing sidebar item, then verifies its native ID through the
/// public task menu. Activation or a same-title heading alone is never success.
struct MiniMaxCodeConversationController: Sendable {
    private let ui: MiniMaxCodeConversationUI
    private let clock: @Sendable () -> TimeInterval
    private let timeout: TimeInterval
    init(ui: MiniMaxCodeConversationUI = MiniMaxCodeAXNavigation.ui,
         clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         timeout: TimeInterval = 3) {
        self.ui = ui; self.clock = clock; self.timeout = max(0, timeout)
    }
    func focus(target: JumpTarget) -> MiniMaxCodeConversationFocusResult {
        let deadline = clock() + timeout
        guard clock() < deadline else { return .unavailable("focus-timeout") }
        guard target.terminalApp == "MiniMax Code.app", let id = target.appConversationID,
              let path = target.runtimeMetadataDatabasePath,
              MiniMaxCodeCompatibility.supportsDesktop(target.runtimeSourceVersion) else { return .unavailable("runtime-metadata-unavailable") }
        guard ui.isAccessibilityAvailable() else { return .unavailable("accessibility-unavailable") }
        guard let source = ui.source(), source.bundleIdentifier == "com.minimax.agent", MiniMaxCodeCompatibility.supportsDesktop(source.version) else {
            return .unavailable("source-version-or-process-unavailable")
        }
        let reader = MiniMaxCodeNavigationMetadata(databasePath: path)
        let record: MiniMaxCodeConversationMetadata
        do {
            guard let value = try reader.conversation(sessionID: id, sourceVersion: source.version) else {
                return .unavailable("session-metadata-miss")
            }
            record = value
        } catch MiniMaxCodeNavigationMetadata.ReadError.ambiguousTitle { return .unavailable("ambiguous-session-title") }
        catch let error as MiniMaxCodeNavigationMetadata.ReadError {
            return .unavailable("session-metadata-" + error.rawValue)
        }
        catch { return .unavailable("session-metadata-unavailable") }
        guard clock() < deadline else { return .unavailable("focus-timeout") }
        guard ui.isAccessibilityAvailable() else { return .unavailable("accessibility-unavailable") }
        guard ui.select(record, source, deadline) else {
            return .unavailable(ui.isAccessibilityAvailable() ? "sidebar-conversation-unavailable" : "accessibility-unavailable")
        }
        guard clock() < deadline else { return .unavailable("focus-timeout") }
        guard ui.isAccessibilityAvailable() else { return .unavailable("accessibility-unavailable") }
        guard ui.copyActiveSessionID(record, source, deadline) == record.sessionID else {
            return .unavailable("active-session-id-unverified")
        }
        guard clock() < deadline else { return .unavailable("focus-timeout") }
        // Re-admit metadata after navigation: a concurrent rename, archive or
        // newly ambiguous title cannot turn an old snapshot into success.
        guard (try? reader.conversation(sessionID: id, sourceVersion: source.version)) == record else {
            return .unavailable("session-metadata-changed")
        }
        guard clock() < deadline, ui.source() == source, ui.isFrontmost(source) else {
            return .unavailable("app-not-frontmost")
        }
        return .focused
    }
}

/// An activation request returns before macOS necessarily changes the frontmost
/// process. Wait within the original navigation budget, without reactivating.
enum MiniMaxCodeActivationAdmission {
    static func wait(deadline: TimeInterval, clock: () -> TimeInterval,
                     available: () -> Bool, frontmost: () -> Bool,
                     pause: (TimeInterval) -> Void) -> Bool {
        while clock() < deadline {
            guard available() else { return false }
            if frontmost() { return clock() < deadline }
            pause(deadline)
        }
        return false
    }
}

/// Frontmost application is not proof that its admitted window receives keys.
/// Raise at most once before sidebar/Copy work; never reacquire focus mid-copy.
enum MiniMaxCodeWindowFocusAdmission {
    struct Result: Equatable {
        var raiseAttempted = false
        var raiseSucceeded = false
        var focused = false
    }
    static func wait(deadline: TimeInterval, clock: () -> TimeInterval,
                     isCurrent: () -> Bool, isFocused: () -> Bool,
                     supportsRaise: () -> Bool, raise: () -> Bool,
                     pause: (TimeInterval) -> Void) -> Result {
        var result = Result()
        guard clock() < deadline, isCurrent() else { return result }
        if isFocused() {
            result.focused = clock() < deadline && isCurrent()
            return result
        }
        guard clock() < deadline, isCurrent(), supportsRaise(),
              clock() < deadline, isCurrent() else { return result }
        result.raiseAttempted = true
        result.raiseSucceeded = raise()
        guard result.raiseSucceeded else { return result }
        while clock() < deadline {
            guard isCurrent() else { return result }
            if isFocused() {
                result.focused = clock() < deadline && isCurrent()
                return result
            }
            pause(deadline)
        }
        return result
    }
}

/// A focusable child may have AXFocused=true while its AXWindow does not.
/// Admit only a stable, actual application-reported focus element belonging to
/// the exact source PID/window; no main-window or activation-only substitute.
enum MiniMaxCodeFocusedElementAdmission {
    static func windowProof<Element>(element: Element, admittedWindow: Element,
                                     containingWindow: (Element) -> Element?, parent: (Element) -> Element?,
                                     isWindow: (Element) -> Bool, equal: (Element, Element) -> Bool,
                                     hasTime: () -> Bool) -> MiniMaxCodeCopyDiagnostic.WindowFocusProof {
        guard hasTime() else { return .ancestryUnavailable }
        if equal(element, admittedWindow) { return .windowSelf }
        if let window = containingWindow(element) { return equal(window, admittedWindow) ? .elementWindow : .differentWindow }
        var node = element
        var seen = [element]
        for _ in 0..<16 where hasTime() {
            guard let next = parent(node), !seen.contains(where: { equal($0, next) }) else { break }
            if equal(next, admittedWindow) { return .elementAncestry }
            if isWindow(next) { return .differentWindow }
            seen.append(next); node = next
        }
        return .ancestryUnavailable
    }
    static func verify<Element>(hasTime: () -> Bool, isCurrent: () -> Bool,
                                readFocus: () -> Element?, belongsToWindow: (Element) -> Bool,
                                equal: (Element, Element) -> Bool) -> Bool {
        guard hasTime(), isCurrent(), let focused = readFocus(),
              belongsToWindow(focused), hasTime(), isCurrent(),
              let latest = readFocus(), equal(focused, latest), belongsToWindow(latest),
              hasTime(), isCurrent(), hasTime() else { return false }
        return true
    }
}

/// Copy diagnostics contain only closed vocabulary and bounded numeric fields.
/// No source text, native ID/hash, pasteboard bytes, path or geometry is retained.
struct MiniMaxCodeCopyDiagnostic: Sendable {
    enum Stage: String, Sendable { case window, search, topbar, entry, title, menu, focus, arrow, item, label, clipboard, complete }
    enum Reason: String, Sendable {
        case windowFocused, windowFocusUnobserved, deadline, sourceNotFrontmost, windowUnavailable, titleUnavailable, menuAlreadyOpen
        case titlePressFailed, copyUnavailable, copyPressFailed, copyFocusUnobserved
        case inputUnavailable, focusChanged, arrowDispatched, itemUnavailable, clipboardUnavailable, clipboardChanged
        case labelActivationFailed, copyUnobserved, copyMismatch, lateCopy, verified
        case searchAlreadyOpen, searchButtonUnavailable, searchPressFailed, searchGroupUnavailable
        case searchFieldUnavailable, searchSetValueFailed, searchValueMismatch, searchResultsAmbiguous
        case searchResultPressFailed, searchTitleUnavailable, searchBudgetExpired, searchSelected
        case terminalButtonAmbiguous, topbarParentUnavailable, topbarChildrenInvalid, topbarPrefixInvalid, topbarVerified
    }
    enum Cleanup: String, Sendable { case unnecessary, unowned, focusChanged, unsupported, attempted, dispatched }
    var stage: Stage = .entry
    var reason: Reason = .deadline
    var cleanup: Cleanup = .unnecessary
    enum WindowFocusProof: String, Sendable {
        case unavailable, windowSelf, elementWindow, elementAncestry, focusChanged, differentProcess, differentWindow, ancestryUnavailable
    }
    var windowFocusProof: WindowFocusProof = .unavailable
    var focusWindowMatches = false
    var focusAncestorMatches = false
    var windowRaise = false
    var windowRaiseSucceeded = false
    var windowFocused = false
    var searchCount = 0
    var searchNodes = 0
    var focusPolls = 0
    var focusQueryError = 0
    var focusedRole = "unavailable"
    var focusEqual = false
    var frontmost = false
    var inputAvailable = false
    var copied = false
    var restored = false
    var deadlineExpired = false
    var entryBudgetMilliseconds = 0
    var elapsedMilliseconds = 0
    var line: String {
        let roles = ["AXMenuItem", "AXMenu", "AXButton", "AXStaticText", "AXGroup", "AXTextArea", "AXWebArea"]
        let role = roles.contains(focusedRole) ? focusedRole : "unavailable"
        func bounded(_ value: Int) -> Int { min(max(value, 0), 60_000) }
        return "stage=\(stage.rawValue) reason=\(reason.rawValue) cleanup=\(cleanup.rawValue) searchCount=\(bounded(searchCount)) searchNodes=\(bounded(searchNodes)) windowRaise=\(windowRaise) windowRaiseSucceeded=\(windowRaiseSucceeded) windowFocused=\(windowFocused) windowFocusProof=\(windowFocusProof.rawValue) focusWindowMatches=\(focusWindowMatches) focusAncestorMatches=\(focusAncestorMatches) focusPolls=\(bounded(focusPolls)) focusQueryError=\(min(max(focusQueryError, -25_220), 0)) focusedRole=\(role) focusEqual=\(focusEqual) frontmost=\(frontmost) inputAvailable=\(inputAvailable) copied=\(copied) restored=\(restored) deadlineExpired=\(deadlineExpired) entryBudgetMs=\(bounded(entryBudgetMilliseconds)) elapsedMs=\(bounded(elapsedMilliseconds))"
    }
}

/// A failed navigation may dismiss only its own menu while the exact menu
/// focus, source and window are still current. Never activate another app.
enum MiniMaxCodeCopyCleanupAdmission {
    static func permits(openedByNavigation: Bool, sameSource: Bool, sameWindow: Bool,
                        frontmost: Bool, focusBelongsToMenu: Bool, hasTime: Bool) -> Bool {
        openedByNavigation && sameSource && sameWindow && frontmost && focusBelongsToMenu && hasTime
    }
    static func cancelIfCurrent(isCurrent: () -> Bool, supportsCancel: () -> Bool,
                                cancel: () -> Bool) -> MiniMaxCodeCopyDiagnostic.Cleanup {
        guard isCurrent() else { return .focusChanged }
        guard supportsCancel() else { return .unsupported }
        // An action query can outlive a user's focus change. Re-admit immediately
        // before invoking the element-targeted cancel action.
        guard isCurrent() else { return .focusChanged }
        return cancel() ? .dispatched : .attempted
    }
}

enum MiniMaxCodeCopyDiagnosticRecorder {
    static let directory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/OpenIsland")
    static let markerName = ".minimax-copy-diagnostics-enabled"
    static let logName = "minimax-copy-diagnostics.log"
    static func isEnabled(directory: URL = directory, ownerUID: uid_t = getuid()) -> Bool {
        let directoryFD = openDirectory(directory, ownerUID: ownerUID)
        guard directoryFD >= 0 else { return false }
        defer { close(directoryFD) }
        let marker = openat(directoryFD, markerName, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard marker >= 0 else { return false }
        defer { close(marker) }
        return validFile(marker, ownerUID: ownerUID, empty: true)
    }
    static func record(_ diagnostic: MiniMaxCodeCopyDiagnostic, directory: URL = directory, ownerUID: uid_t = getuid()) {
        // Optional recorder never creates its directory or marker; no preference,
        // environment override or special acceptance bundle is required.
        let directoryFD = openDirectory(directory, ownerUID: ownerUID)
        guard directoryFD >= 0 else { return }
        defer { close(directoryFD) }
        let marker = openat(directoryFD, markerName, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard marker >= 0 else { return }
        defer { close(marker) }
        guard validFile(marker, ownerUID: ownerUID, empty: true) else { return }
        var log = openat(directoryFD, logName, O_WRONLY | O_APPEND | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if log < 0 && errno == ENOENT {
            log = openat(directoryFD, logName, O_WRONLY | O_APPEND | O_CREAT | O_EXCL | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        }
        guard log >= 0 else { return }
        defer { close(log) }
        guard flock(log, LOCK_EX | LOCK_NB) == 0 else { return }
        defer { flock(log, LOCK_UN) }
        let data = Data(("timestamp=\(Int(Date().timeIntervalSince1970)) " + diagnostic.line + "\n").utf8)
        var info = stat()
        guard validFile(log, ownerUID: ownerUID), validFile(marker, ownerUID: ownerUID, empty: true),
              fstat(log, &info) == 0, info.st_size >= 0, info.st_size <= 65_536 - data.count else { return }
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(log, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return }
                offset += count
            }
        }
    }
    private static func validFile(_ fd: Int32, ownerUID: uid_t, empty: Bool = false) -> Bool {
        var info = stat()
        return fstat(fd, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG && info.st_uid == ownerUID
            && info.st_nlink == 1 && (info.st_mode & 0o7777) == 0o600 && (!empty || info.st_size == 0)
    }
    private static func openDirectory(_ url: URL, ownerUID: uid_t) -> Int32 {
        guard url.isFileURL, let resolved = realpath(url.path, nil) else { return -1 }
        defer { free(resolved) }
        guard String(cString: resolved) == url.path else { return -1 }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return -1 }
        for component in url.path.split(separator: "/") {
            let next = openat(fd, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(fd)
            guard next >= 0 else { return -1 }
            fd = next
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_uid == 0 || info.st_uid == ownerUID else { close(fd); return -1 }
        }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == ownerUID else { close(fd); return -1 }
        return fd
    }
}

private enum MiniMaxCodeAXNavigation {
    private static let acceptanceDiagnosticsEnabled = Bundle.main.bundleIdentifier?
        .hasPrefix("dev.aisland.v011.acceptance.") == true
    private enum AcceptanceStage: String {
        case windowQuery = "window-query"
        case windowSnapshot = "window-snapshot"
        case windowCandidates = "window-candidates"
        case projectHeaders = "project-headers"
        case projectHeaderLabelUnavailable = "project-header-label-unavailable"
        case projectParent = "project-parent"
        case projectParentUnavailable = "project-parent-unavailable"
        case projectParentDeadline = "project-parent-deadline"
        case projectRows = "project-rows"
        case projectLeafRows = "project-leaf-rows"
        case projectHeaderPress = "project-header-press"
        case projectRowPress = "project-row-press"
        case titleMenuMatches = "title-menu-matches"
        case titleMenuTimeout = "title-menu-timeout"
        case copySubmenu = "copy-submenu"
        case copyKeyDelivery = "copy-key-delivery"
        case copyFocus = "copy-focus"
        case copyIDItem = "copy-id-item"
        case copyIDPress = "copy-id-press"
        case copyLabel = "copy-label"
        case pasteboardCapture = "pasteboard-capture"
        case pasteboardIdentity = "pasteboard-identity"
        case pasteboardRestore = "pasteboard-restore"
        case selectionTimeout = "selection-timeout"
        case activationEntry = "activation-entry"
        case activationRequest = "activation-request"
        case activationAdmission = "activation-admission"
        case copyEntryDeadline = "copy-entry-deadline"
        case copyEntryFrontmost = "copy-entry-frontmost"
        case copyEntryWindow = "copy-entry-window"
        case copyTitleButton = "copy-title-button"
        case copyTitlePress = "copy-title-press"
        case copyMenuItem = "copy-menu-item"
        case copyMenuPress = "copy-menu-press"
    }
    private enum DiagnosticRole: String {
        case group = "AXGroup", button = "AXButton", staticText = "AXStaticText"
        case textField = "AXTextField", textArea = "AXTextArea", heading = "AXHeading"
        case scrollArea = "AXScrollArea", webArea = "AXWebArea", toolbar = "AXToolbar"
        case list = "AXList", outline = "AXOutline", splitGroup = "AXSplitGroup"
        case menu = "AXMenu", menuItem = "AXMenuItem", other = "AXOther"
        case window = "AXWindow"
        init(_ value: String?) {
            self = Self(rawValue: value ?? "") ?? .other
        }
    }
    private enum DiagnosticWindowSubrole: String {
        case standard = "AXStandardWindow", dialog = "AXDialog", systemDialog = "AXSystemDialog"
        case floating = "AXFloatingWindow", systemFloating = "AXSystemFloatingWindow", other = "AXOther"
        init(_ value: String?) {
            self = Self(rawValue: value ?? "") ?? .other
        }
    }
    private static func acceptanceWindowLog(_ windows: [AXUIElement]) {
        // Ordinary bundles must not make these additional AX queries.
        guard acceptanceDiagnosticsEnabled else { return }
        var titleCandidates = 0, mainCandidates = 0, focusedCandidates = 0
        let sampled = windows.prefix(4)
        for (index, window) in sampled.enumerated() {
            let windowRole = DiagnosticRole(role(window))
            let subrole = DiagnosticWindowSubrole(value(window, kAXSubroleAttribute) as? String)
            let main = bool(window, kAXMainAttribute)
            let focused = bool(window, kAXFocusedAttribute)
            let minimized = bool(window, kAXMinimizedAttribute)
            let titleMatches = (value(window, kAXTitleAttribute) as? String) == "MiniMax Code"
            let canRaise = action(window, kAXRaiseAction)
            if windowRole == .window && titleMatches { titleCandidates += 1 }
            if main == true { mainCandidates += 1 }
            if focused == true { focusedCandidates += 1 }
            // Titles are compared in memory; all printed strings are closed enums.
            // AX booleans use -1 for unavailable, 0 for false, and 1 for true.
            NSLog("aisland_minimax_navigation stage=%@ index=%ld role=%@ subrole=%@ main=%ld focused=%ld minimized=%ld title_matches=%d can_raise=%d",
                  AcceptanceStage.windowSnapshot.rawValue, index + 1, windowRole.rawValue, subrole.rawValue,
                  main.map { $0 ? 1 : 0 } ?? -1, focused.map { $0 ? 1 : 0 } ?? -1,
                  minimized.map { $0 ? 1 : 0 } ?? -1, titleMatches ? 1 : 0, canRaise ? 1 : 0)
        }
        // These are diagnostic counts within the sample, not a selection policy.
        NSLog("aisland_minimax_navigation stage=%@ count=%ld sampled=%ld truncated=%d title_candidates=%ld main_candidates=%ld focused_candidates=%ld",
              AcceptanceStage.windowCandidates.rawValue, windows.count, sampled.count,
              sampled.count < windows.count ? 1 : 0, titleCandidates, mainCandidates, focusedCandidates)
    }
    private static func acceptanceLog(_ stage: AcceptanceStage, count: Int = 0,
                                      nodes: Int = 0, error: Int = 0, flag: Bool = false) {
        guard acceptanceDiagnosticsEnabled else { return }
        NSLog("aisland_minimax_navigation stage=%@ count=%ld nodes=%ld error=%ld flag=%d",
              stage.rawValue, count, nodes, error, flag ? 1 : 0)
    }
    private static func acceptanceParentLog(_ node: AXUIElement, header: AXUIElement, index: Int,
                                            classCount: Int, rendererGroup: Bool, eligible: Bool,
                                            containsHeader: Int, deadline: TimeInterval) {
        guard acceptanceDiagnosticsEnabled else { return }
        guard remaining(deadline) else {
            acceptanceLog(.projectParentDeadline, count: index); return
        }
        let parentRole = DiagnosticRole(role(node))
        let hasDescription = (value(node, kAXDescriptionAttribute) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasTitle = (value(node, kAXTitleAttribute) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let children = remaining(deadline) ? elements(node, kAXChildrenAttribute) : []
        var childRoles: [DiagnosticRole] = []
        for child in children.prefix(8) where remaining(deadline) {
            childRoles.append(DiagnosticRole(role(child)))
        }
        // Every printed role comes from a closed enum; never print AX free text.
        NSLog("aisland_minimax_navigation stage=%@ parent=%ld role=%@ description=%d title=%d classes=%ld renderer=%d eligible=%d contains_header=%ld direct_header=%d children=%ld sampled=%ld child_roles=%@ truncated=%d",
              AcceptanceStage.projectParent.rawValue, index, parentRole.rawValue, hasDescription ? 1 : 0, hasTitle ? 1 : 0,
              classCount, rendererGroup ? 1 : 0, eligible ? 1 : 0, containsHeader,
              children.contains(where: { CFEqual($0, header) }) ? 1 : 0,
              children.count, childRoles.count, childRoles.map(\.rawValue).joined(separator: ","),
              childRoles.count < children.count ? 1 : 0)
    }
    static let ui = MiniMaxCodeConversationUI(isAccessibilityAvailable: { AXIsProcessTrusted() }, source: source, select: select,
                                             copyActiveSessionID: copyID, isFrontmost: frontmost)
    static func source() -> MiniMaxCodeConversationUI.Source? {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "com.minimax.agent")
            .filter { !$0.isTerminated && $0.processIdentifier > 0 }
        guard applications.count == 1, let app = applications.first, let url = app.bundleURL,
              let bundle = Bundle(url: url), bundle.bundleIdentifier == "com.minimax.agent",
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return nil }
        return .init(bundleIdentifier: "com.minimax.agent", version: version, processID: app.processIdentifier)
    }
    static func app(_ source: MiniMaxCodeConversationUI.Source) -> NSRunningApplication? {
        guard let value = NSRunningApplication(processIdentifier: source.processID),
              value.bundleIdentifier == source.bundleIdentifier, !value.isTerminated else { return nil }
        return value
    }
    static func frontmost(_ source: MiniMaxCodeConversationUI.Source) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processID
    }
    static func select(_ record: MiniMaxCodeConversationMetadata, _ source: MiniMaxCodeConversationUI.Source,
                       _ deadline: TimeInterval) -> Bool {
        guard remaining(deadline), AXIsProcessTrusted(), let app = app(source) else { return false }
        // Jump work runs off-main. Ask LaunchServices to foreground the already
        // admitted source instance. NSRunningApplication.activate returned false
        // in the live accessory-app jump even on the AppKit thread. Opening the
        // existing application does not create a task or a second app instance.
        // Do not reactivate once copying has begun.
        let request: @Sendable () -> Bool = {
            guard remaining(deadline), AXIsProcessTrusted(), let current = self.app(source),
                  let bundleURL = current.bundleURL else { return false }
            if frontmost(source) { return true }
            current.unhide()
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = false
            configuration.promptsUserIfNeeded = false
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in }
            // Dispatch is not proof of activation: the bounded admission below
            // still requires this same source PID to become frontmost.
            return true
        }
        let requested = Thread.isMainThread ? request() : DispatchQueue.main.sync(execute: request)
        acceptanceLog(.activationRequest, flag: requested)
        guard requested else { return false }
        acceptanceLog(.activationEntry, flag: frontmost(source))
        let activated = MiniMaxCodeActivationAdmission.wait(deadline: deadline,
            clock: { ProcessInfo.processInfo.systemUptime },
            available: { AXIsProcessTrusted() && self.app(source) != nil },
            frontmost: { self.frontmost(source) }, pause: pause)
        acceptanceLog(.activationAdmission, flag: activated)
        guard activated, let admittedWindow = window(source) else { return false }
        let focusStarted = ProcessInfo.processInfo.systemUptime
        var windowDiagnostic = MiniMaxCodeCopyDiagnostic()
        let diagnosticEnabled = acceptanceDiagnosticsEnabled || MiniMaxCodeCopyDiagnosticRecorder.isEnabled()
        let windowAdmission = MiniMaxCodeWindowFocusAdmission.wait(deadline: deadline,
            clock: { ProcessInfo.processInfo.systemUptime }, isCurrent: {
                guard remaining(deadline), AXIsProcessTrusted(), self.source() == source, frontmost(source),
                      let current = window(source) else { return false }
                return CFEqual(current, admittedWindow)
            }, isFocused: {
                focusedElementBelongsToWindow(admittedWindow, source: source, deadline: deadline,
                                              diagnostic: &windowDiagnostic, diagnosticEnabled: diagnosticEnabled)
            }, supportsRaise: { action(admittedWindow, kAXRaiseAction) }, raise: {
                AXUIElementPerformAction(admittedWindow, kAXRaiseAction as CFString) == .success
            }, pause: pause)
        windowDiagnostic.stage = .window
        windowDiagnostic.reason = windowAdmission.focused ? .windowFocused : .windowFocusUnobserved
        windowDiagnostic.windowRaise = windowAdmission.raiseAttempted
        windowDiagnostic.windowRaiseSucceeded = windowAdmission.raiseSucceeded
        windowDiagnostic.windowFocused = windowAdmission.focused
        windowDiagnostic.frontmost = frontmost(source)
        windowDiagnostic.entryBudgetMilliseconds = Int(max(0, deadline - focusStarted) * 1000)
        windowDiagnostic.elapsedMilliseconds = Int(max(0, ProcessInfo.processInfo.systemUptime - focusStarted) * 1000)
        windowDiagnostic.deadlineExpired = !remaining(deadline)
        MiniMaxCodeCopyDiagnosticRecorder.record(windowDiagnostic)
        if acceptanceDiagnosticsEnabled { NSLog("aisland_minimax_window %@", windowDiagnostic.line) }
        guard windowAdmission.focused else { return false }
        if record.isDefaultWorkspace {
            return selectFromSearch(record, source: source, window: admittedWindow, deadline: deadline)
        }
        var expandedOnce = false
        while remaining(deadline) {
            guard AXIsProcessTrusted(), self.source() == source, frontmost(source),
                  let root = window(source), CFEqual(root, admittedWindow) else { return false }
            let headers = projectHeaders(root, path: record.projectWorkspacePath, deadline: deadline)
            guard headers.count == 1 else { return false }
            let header = headers[0]
            if bool(header, kAXExpandedAttribute) == false, !expandedOnce {
                let pressed = press(header, deadline)
                acceptanceLog(.projectHeaderPress, flag: pressed)
                guard pressed else { return false }
                expandedOnce = true
                pause(deadline); continue
            }
            // The observed native tree exposes a draggable project containing
            // its exact header button and child task buttons. DOM classes are
            // optional in Electron AX. Never widen this search to the sidebar.
            let rows = projectRows(header, title: record.title, deadline: deadline) ?? []
            acceptanceLog(.projectRows, count: rows.count, flag: remaining(deadline))
            if rows.isEmpty, bool(header, kAXExpandedAttribute) == nil, !expandedOnce {
                // Some Electron AX trees omit aria-expanded. One ordinary
                // project-header press may reveal its own child rows.
                let pressed = press(header, deadline)
                acceptanceLog(.projectHeaderPress, flag: pressed)
                guard pressed else { return false }
                expandedOnce = true
                pause(deadline); continue
            }
            guard rows.count == 1 else { return false }
            let pressed = press(rows[0], deadline)
            acceptanceLog(.projectRowPress, flag: pressed)
            guard pressed else { return false }
            while remaining(deadline) {
                guard AXIsProcessTrusted(), self.source() == source, frontmost(source),
                      let focusedWindow = window(source), CFEqual(focusedWindow, admittedWindow) else { return false }
                if titleMenuButton(focusedWindow, title: record.title, deadline: deadline) != nil {
                    return true
                }
                pause(deadline)
            }
            acceptanceLog(.titleMenuTimeout)
        }
        acceptanceLog(.selectionTimeout)
        return false
    }
    /// Default-workspace tasks have no path-labelled project header. Use the
    /// public local search, then retain the same copied native-ID verification.
    /// Never overwrite an already-open user search or select a command result.
    static func selectFromSearch(_ record: MiniMaxCodeConversationMetadata,
                                 source: MiniMaxCodeConversationUI.Source,
                                 window admittedWindow: AXUIElement, deadline: TimeInterval) -> Bool {
        let started = ProcessInfo.processInfo.systemUptime
        var diagnostic = MiniMaxCodeCopyDiagnostic()
        diagnostic.stage = .search
        diagnostic.reason = .searchBudgetExpired
        defer {
            diagnostic.frontmost = frontmost(source)
            diagnostic.deadlineExpired = !remaining(deadline)
            diagnostic.entryBudgetMilliseconds = Int(max(0, deadline - started) * 1000)
            diagnostic.elapsedMilliseconds = Int(max(0, ProcessInfo.processInfo.systemUptime - started) * 1000)
            MiniMaxCodeCopyDiagnosticRecorder.record(diagnostic)
        }
        func current() -> AXUIElement? {
            guard remaining(deadline), AXIsProcessTrusted(), self.source() == source,
                  frontmost(source), let root = window(source), CFEqual(root, admittedWindow) else { return nil }
            return root
        }
        func searchGroups(_ root: AXUIElement) -> [AXUIElement] {
            nodes(root, deadline).filter {
                role($0) == "AXGroup" && ["全局搜索", "Global search"].contains(exactLabel($0) ?? "")
            }
        }
        guard let root = current() else { return false }
        let initialGroups = searchGroups(root)
        diagnostic.searchCount = initialGroups.count
        guard initialGroups.isEmpty else { diagnostic.reason = .searchAlreadyOpen; return false }
        let buttons = nodes(root, deadline).filter {
            role($0) == "AXButton" && ["搜索", "Search"].contains(exactLabel($0) ?? "") && action($0, kAXPressAction)
        }
        diagnostic.searchCount = buttons.count
        guard buttons.count == 1 else { diagnostic.reason = .searchButtonUnavailable; return false }
        guard current() != nil, press(buttons[0], deadline) else { diagnostic.reason = .searchPressFailed; return false }
        defer {
            // Close only our own search, in the same source/window and budget.
            if let root = current() {
                let groups = searchGroups(root)
                if groups.count == 1 {
                    let close = nodes(groups[0], deadline, maximum: 256, depth: 8).filter {
                        role($0) == "AXButton" && ["关闭", "Close"].contains(exactLabel($0) ?? "") && action($0, kAXPressAction)
                    }
                    if close.count == 1, current() != nil { _ = press(close[0], deadline) }
                }
            }
        }
        var searched = false
        while let root = current() {
            let groups = searchGroups(root)
            if groups.isEmpty { pause(deadline); continue }
            diagnostic.searchCount = groups.count
            guard groups.count == 1 else { diagnostic.reason = .searchGroupUnavailable; return false }
            let members = nodes(groups[0], deadline, maximum: 256, depth: 8)
            diagnostic.searchNodes = members.count
            if !searched {
                let fields = members.filter {
                    role($0) == "AXTextField" && ["搜索任务或运行命令", "Search tasks or run commands"].contains(exactLabel($0) ?? "")
                }
                diagnostic.searchCount = fields.count
                guard fields.count == 1 else { diagnostic.reason = .searchFieldUnavailable; return false }
                guard current() != nil,
                      AXUIElementSetAttributeValue(fields[0], kAXValueAttribute as CFString, record.title as CFString) == .success else {
                    diagnostic.reason = .searchSetValueFailed; return false
                }
                searched = true
                pause(deadline); continue
            }
            let fields = members.filter { role($0) == "AXTextField" }
            diagnostic.searchCount = fields.count
            guard fields.count == 1, value(fields[0], kAXValueAttribute) as? String == record.title else {
                diagnostic.reason = .searchValueMismatch; return false
            }
            let results = members.filter { item in
                guard role(item) == "AXButton", exactLabel(item) == record.title, action(item, kAXPressAction),
                      let section = parent(item), members.contains(where: { CFEqual($0, section) }) else { return false }
                // Commands/settings use separate renderer sections. Read only
                // the direct section header, never another task or chat body.
                return elements(section, kAXChildrenAttribute).prefix(1).contains { header in
                    (role(header) == "AXStaticText" && ["搜索结果", "Search results"].contains(text(header) ?? "")) ||
                    (role(header) == "AXGroup" && elements(header, kAXChildrenAttribute).contains {
                        role($0) == "AXStaticText" && ["搜索结果", "Search results"].contains(text($0) ?? "")
                    })
                }
            }
            if results.isEmpty { pause(deadline); continue }
            diagnostic.searchCount = results.count
            guard results.count == 1 else { diagnostic.reason = .searchResultsAmbiguous; return false }
            guard current() != nil, press(results[0], deadline) else { diagnostic.reason = .searchResultPressFailed; return false }
            diagnostic.reason = .searchTitleUnavailable
            while let root = current() {
                if titleMenuButton(root, title: record.title, deadline: deadline, defaultWorkspace: true) != nil {
                    diagnostic.reason = .searchSelected; return true
                }
                pause(deadline)
            }
            return false
        }
        return false
    }
    static func copyID(_ record: MiniMaxCodeConversationMetadata, _ source: MiniMaxCodeConversationUI.Source,
                       _ deadline: TimeInterval) -> String? {
        let started = ProcessInfo.processInfo.systemUptime
        var diagnostic = MiniMaxCodeCopyDiagnostic()
        let diagnosticEnabled = acceptanceDiagnosticsEnabled || MiniMaxCodeCopyDiagnosticRecorder.isEnabled()
        diagnostic.entryBudgetMilliseconds = Int(max(0, deadline - started) * 1000)
        var ownedMenu: AXUIElement?
        var navigationWindow: AXUIElement?
        var dispatched = false
        defer {
            if !dispatched, let menu = ownedMenu, let root = navigationWindow {
                diagnostic.cleanup = cleanupOwnMenu(menu, window: root, source: source)
            } else if !dispatched { diagnostic.cleanup = .unowned }
            diagnostic.deadlineExpired = !remaining(deadline)
            diagnostic.elapsedMilliseconds = Int(max(0, ProcessInfo.processInfo.systemUptime - started) * 1000)
            MiniMaxCodeCopyDiagnosticRecorder.record(diagnostic)
            if acceptanceDiagnosticsEnabled { NSLog("aisland_minimax_copy %@", diagnostic.line) }
        }
        let inTime = remaining(deadline)
        acceptanceLog(.copyEntryDeadline, flag: inTime)
        guard inTime else { return nil }
        diagnostic.reason = .sourceNotFrontmost
        let inFront = frontmost(source)
        diagnostic.frontmost = inFront
        acceptanceLog(.copyEntryFrontmost, flag: inFront)
        guard inFront else { return nil }
        diagnostic.reason = .windowUnavailable
        let root = window(source)
        acceptanceLog(.copyEntryWindow, flag: root != nil)
        guard let root else { return nil }
        diagnostic.windowFocused = focusedElementBelongsToWindow(root, source: source, deadline: deadline,
                                                                  diagnostic: &diagnostic, diagnosticEnabled: diagnosticEnabled)
        guard diagnostic.windowFocused else { diagnostic.reason = .windowFocusUnobserved; return nil }
        navigationWindow = root
        diagnostic.stage = .title; diagnostic.reason = .titleUnavailable
        var menuAlreadyOpen = false
        let more = titleMenuButton(root, title: record.title, deadline: deadline, rejectOpenMenu: true,
                                   menuAlreadyOpen: &menuAlreadyOpen, defaultWorkspace: record.isDefaultWorkspace)
        if menuAlreadyOpen { diagnostic.reason = .menuAlreadyOpen }
        acceptanceLog(.copyTitleButton, flag: more != nil)
        guard let more else { return nil }
        diagnostic.reason = .titlePressFailed
        let titlePressed = press(more, deadline)
        acceptanceLog(.copyTitlePress, flag: titlePressed)
        guard titlePressed else { return nil }
        diagnostic.stage = .menu; diagnostic.reason = .copyUnavailable
        let copy = waitForMenuLabel(["复制", "Copy"], source: source, deadline: deadline)
        acceptanceLog(.copyMenuItem, flag: copy != nil)
        guard let copy else { return nil }
        ownedMenu = menuAncestor(copy, deadline: deadline)
        diagnostic.reason = .copyPressFailed
        let copyPressed = press(copy, deadline)
        acceptanceLog(.copyMenuPress, flag: copyPressed)
        guard copyPressed else { return nil }
        let opened = openCopySubmenu(copy, source: source, deadline: deadline, diagnostic: &diagnostic, diagnosticEnabled: diagnosticEnabled)
        acceptanceLog(.copySubmenu, flag: opened)
        guard opened else { return nil }
        diagnostic.stage = .item; diagnostic.reason = .itemUnavailable
        let item = waitForMenuLabel(["复制会话 ID", "Copy session ID"], source: source, deadline: deadline)
        acceptanceLog(.copyIDItem, flag: item != nil)
        guard let copyID = item, frontmost(source), remaining(deadline) else { return nil }
        diagnostic.stage = .clipboard; diagnostic.reason = .clipboardUnavailable
        let pasteboard = NSPasteboard.general
        let captured = MiniMaxCodePasteboardSnapshot.capture(pasteboard)
        acceptanceLog(.pasteboardCapture, flag: captured != nil)
        guard let snapshot = captured, remaining(deadline) else { return nil }
        diagnostic.reason = .clipboardChanged
        guard pasteboard.changeCount == snapshot.originalChangeCount else { return nil }
        diagnostic.stage = .label; diagnostic.reason = .labelActivationFailed
        let activated = activateCopyLabel(copyID, source: source, deadline: deadline,
                                          isPasteboardUnchanged: { pasteboard.changeCount == snapshot.originalChangeCount })
        acceptanceLog(.copyIDPress, flag: activated)
        guard activated else { return nil }
        dispatched = true
        diagnostic.stage = .clipboard; diagnostic.reason = .copyUnobserved
        // A dispatched asynchronous copy gets at least 300 ms of bounded cleanup
        // observation. A late exact result is restored but never reports success.
        let cleanupDeadline = max(deadline, ProcessInfo.processInfo.systemUptime + 0.3)
        repeat {
            if pasteboard.changeCount != snapshot.originalChangeCount {
                diagnostic.reason = .copyMismatch
                let result = snapshot.consumeMatchingCopy(pasteboard, expectedID: record.sessionID)
                acceptanceLog(.pasteboardIdentity, flag: result != nil)
                guard let result else { return nil }
                diagnostic.copied = true; diagnostic.restored = result.restored
                acceptanceLog(.pasteboardRestore, flag: result.restored)
                diagnostic.reason = .lateCopy
                guard remaining(deadline) else { return nil }
                diagnostic.stage = .complete; diagnostic.reason = .verified
                return result.sessionID
            }
            guard remaining(cleanupDeadline) else { break }
            pause(cleanupDeadline)
        } while remaining(cleanupDeadline)
        return nil
    }
    static func focusedElementBelongsToWindow(_ root: AXUIElement, source: MiniMaxCodeConversationUI.Source,
                                              deadline: TimeInterval, diagnostic: inout MiniMaxCodeCopyDiagnostic,
                                              diagnosticEnabled: Bool) -> Bool {
        let app = AXUIElementCreateApplication(source.processID)
        func current() -> Bool {
            guard remaining(deadline), AXIsProcessTrusted(), self.source() == source, frontmost(source),
                  let window = window(source), CFEqual(window, root) else { return false }
            return remaining(deadline)
        }
        func focus() -> AXUIElement? {
            var output: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &output)
            diagnostic.focusPolls += 1
            diagnostic.focusQueryError = Int(error.rawValue)
            guard error == .success, let output, CFGetTypeID(output) == AXUIElementGetTypeID() else {
                diagnostic.windowFocusProof = .unavailable
                return nil
            }
            let element = unsafeDowncast(output, to: AXUIElement.self)
            if diagnosticEnabled { diagnostic.focusedRole = DiagnosticRole(role(element)).rawValue }
            return element
        }
        let verified = MiniMaxCodeFocusedElementAdmission.verify(hasTime: { remaining(deadline) }, isCurrent: current,
            readFocus: focus, belongsToWindow: { element in
                var owner: pid_t = 0
                guard AXUIElementGetPid(element, &owner) == .success, owner == source.processID else {
                    diagnostic.windowFocusProof = .differentProcess
                    return false
                }
                // AXWindow is the documented parent shortcut. Bounded parent
                // metadata is used only when it is unavailable; no body is read.
                let proof = MiniMaxCodeFocusedElementAdmission.windowProof(element: element, admittedWindow: root,
                    containingWindow: { focused in
                        guard let containing = value(focused, kAXWindowAttribute),
                              CFGetTypeID(containing) == AXUIElementGetTypeID() else { return nil }
                        return unsafeDowncast(containing, to: AXUIElement.self)
                    }, parent: parent, isWindow: { role($0) == "AXWindow" },
                    equal: { CFEqual($0, $1) }, hasTime: { remaining(deadline) })
                diagnostic.windowFocusProof = proof
                diagnostic.focusWindowMatches = proof == .elementWindow
                diagnostic.focusAncestorMatches = proof == .elementAncestry
                return [.windowSelf, .elementWindow, .elementAncestry].contains(proof)
            }, equal: { first, latest in
                let same = CFEqual(first, latest)
                if !same { diagnostic.windowFocusProof = .focusChanged }
                return same
            })
        return verified
    }
    static func menuAncestor(_ element: AXUIElement, deadline: TimeInterval) -> AXUIElement? {
        var current = element
        for _ in 0..<8 where remaining(deadline) {
            if role(current) == "AXMenu" || classes(current).contains("ant-dropdown-menu") { return current }
            guard let next = parent(current) else { return nil }
            current = next
        }
        return nil
    }
    static func cleanupOwnMenu(_ menu: AXUIElement, window original: AXUIElement,
                               source: MiniMaxCodeConversationUI.Source) -> MiniMaxCodeCopyDiagnostic.Cleanup {
        // Cleanup has a separate fixed 120 ms budget; it cannot report navigation
        // success or reclaim focus. AXCancel is targeted to the admitted element.
        let deadline = ProcessInfo.processInfo.systemUptime + 0.12
        guard AXIsProcessTrusted(), self.source() == source, frontmost(source),
              let current = window(source), CFEqual(current, original),
              let focused = value(AXUIElementCreateApplication(source.processID), kAXFocusedUIElementAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return .focusChanged }
        let element = unsafeDowncast(focused, to: AXUIElement.self)
        var ancestor = element
        var belongs = false
        for _ in 0..<8 where remaining(deadline) {
            if CFEqual(ancestor, menu) { belongs = true; break }
            guard let next = parent(ancestor) else { break }
            ancestor = next
        }
        guard belongs,
              MiniMaxCodeCopyCleanupAdmission.permits(openedByNavigation: true, sameSource: self.source() == source,
                  sameWindow: true, frontmost: frontmost(source), focusBelongsToMenu: true, hasTime: remaining(deadline)) else {
            return .focusChanged
        }
        return MiniMaxCodeCopyCleanupAdmission.cancelIfCurrent(isCurrent: {
            guard remaining(deadline), AXIsProcessTrusted(), self.source() == source, frontmost(source),
                  let currentWindow = window(source), CFEqual(currentWindow, original),
                  let latest = value(AXUIElementCreateApplication(source.processID), kAXFocusedUIElementAttribute),
                  CFGetTypeID(latest) == AXUIElementGetTypeID(), CFEqual(latest, element) else { return false }
            return remaining(deadline)
        }, supportsCancel: { action(menu, kAXCancelAction) }, cancel: {
            AXUIElementPerformAction(menu, kAXCancelAction as CFString) == .success
        })
    }
    /// Desktop AXPress focuses the Copy item without opening its submenu.
    /// Use the standard right-arrow only for that exact focused menu item, in
    /// the admitted frontmost source process. No global keyboard shortcut.
    static func openCopySubmenu(_ copy: AXUIElement, source: MiniMaxCodeConversationUI.Source,
                                deadline: TimeInterval, diagnostic: inout MiniMaxCodeCopyDiagnostic, diagnosticEnabled: Bool) -> Bool {
        diagnostic.stage = .focus; diagnostic.reason = .copyFocusUnobserved
        if acceptanceDiagnosticsEnabled {
            NSLog("aisland_minimax_navigation stage=copy-guard role=%@ frontmost=%d trusted=%d remaining=%d",
                  DiagnosticRole(role(copy)).rawValue, frontmost(source) ? 1 : 0,
                  AXIsProcessTrusted() ? 1 : 0, remaining(deadline) ? 1 : 0)
        }
        guard remaining(deadline), AXIsProcessTrusted(), frontmost(source),
              role(copy) == "AXMenuItem" else { return false }
        // This item exposes AXShowMenu, but its success only focused Copy in
        // the live build; it did not expose the submenu. Verify keyboard focus
        // explicitly instead of treating an action return code as expansion.
        let app = AXUIElementCreateApplication(source.processID)
        var focusedCopy = false
        // AXPress updates the native menu focus asynchronously. Do not send
        // any input until the exact item is observed, within the same deadline.
        while remaining(deadline), AXIsProcessTrusted(), frontmost(source) {
            var focused: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused)
            diagnostic.focusPolls += 1; diagnostic.focusQueryError = Int(error.rawValue)
            if let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
                let element = unsafeDowncast(focused, to: AXUIElement.self)
                diagnostic.focusEqual = CFEqual(element, copy)
                // Ordinary navigation performs no additional AX role query.
                if diagnosticEnabled { diagnostic.focusedRole = DiagnosticRole(role(element)).rawValue }
                if diagnostic.focusEqual { focusedCopy = true; break }
            }
            pause(deadline)
        }
        acceptanceLog(.copyFocus, flag: focusedCopy)
        diagnostic.frontmost = frontmost(source)
        guard focusedCopy, remaining(deadline), diagnostic.frontmost else { return false }
        diagnostic.stage = .arrow; diagnostic.reason = .inputUnavailable
        // Deliver the ordinary menu arrow through WindowServer. This is one fixed
        // arrow on the exact focused Copy item, with no global shortcut and
        // no permission request. A user focus change cancels delivery.
        let canPost = CGPreflightPostEventAccess()
        diagnostic.inputAvailable = canPost
        acceptanceLog(.copyKeyDelivery, flag: canPost)
        guard canPost, let keyboard = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: keyboard, virtualKey: 124, keyDown: true),
              let up = CGEvent(keyboardEventSource: keyboard, virtualKey: 124, keyDown: false) else { return false }
        diagnostic.reason = .focusChanged
        guard frontmost(source), let current = value(app, kAXFocusedUIElementAttribute),
              CFGetTypeID(current) == AXUIElementGetTypeID(), CFEqual(unsafeDowncast(current, to: AXUIElement.self), copy) else { return false }
        down.flags = []; up.flags = []
        down.post(tap: .cgSessionEventTap); up.post(tap: .cgSessionEventTap)
        diagnostic.reason = .arrowDispatched
        pause(deadline)
        return remaining(deadline)
    }

    /// The public matrix Dropdown binds Copy's callback to its inner label div;
    /// AXPress on the outer ARIA menuitem only closes the menu. Click the exact
    /// admitted label with a fresh source-process hit test, never a guessed point.
    static func activateCopyLabel(_ item: AXUIElement, source: MiniMaxCodeConversationUI.Source,
                                  deadline: TimeInterval, isPasteboardUnchanged: () -> Bool) -> Bool {
        guard remaining(deadline), frontmost(source), AXIsProcessTrusted(), CGPreflightPostEventAccess(),
              role(item) == "AXMenuItem" else { return false }
        let members = nodes(item, deadline, maximum: 17, depth: 4)
        guard members.count <= 16, remaining(deadline) else { return false }
        let labels = members.filter { role($0) == "AXStaticText" && ["复制会话 ID", "Copy session ID"].contains(text($0) ?? "") }
        acceptanceLog(.copyLabel, count: labels.count, nodes: members.count, flag: remaining(deadline))
        guard labels.count == 1, let label = labels.first else { return false }
        let application = AXUIElementCreateApplication(source.processID)
        // Opening the renderer submenu animates its geometry. Fresh bounds and
        // hit identity must agree before clicking; wait within the same budget.
        while remaining(deadline), frontmost(source), isPasteboardUnchanged() {
            guard let pointValue = value(label, kAXPositionAttribute), CFGetTypeID(pointValue) == AXValueGetTypeID(),
                  let sizeValue = value(label, kAXSizeAttribute), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return false }
            var origin = CGPoint.zero; var size = CGSize.zero
            guard AXValueGetValue(unsafeDowncast(pointValue, to: AXValue.self), .cgPoint, &origin),
                  AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size),
                  origin.x.isFinite, origin.y.isFinite, size.width.isFinite, size.height.isFinite,
                  size.width > 0, size.height > 0 else { return false }
            let point = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
            var hit: AXUIElement?
            let hitResult = AXUIElementCopyElementAtPosition(application, Float(point.x), Float(point.y), &hit)
            let matches = hit.map { candidate in members.contains { CFEqual($0, candidate) } } ?? false
            acceptanceLog(.copyLabel, count: 3, error: Int(hitResult.rawValue), flag: matches)
            guard hitResult == .success else { return false }
            if let hit, matches {
                var owner: pid_t = 0
                guard AXUIElementGetPid(hit, &owner) == .success, owner == source.processID,
                      remaining(deadline), frontmost(source), isPasteboardUnchanged(),
                      let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
                      let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { return false }
                down.flags = []; up.flags = []
                down.setIntegerValueField(.mouseEventClickState, value: 1)
                up.setIntegerValueField(.mouseEventClickState, value: 1)
                down.post(tap: .cgSessionEventTap); up.post(tap: .cgSessionEventTap)
                return true
            }
            if acceptanceDiagnosticsEnabled {
                NSLog("aisland_minimax_navigation stage=copy-label-hit role=%@", DiagnosticRole(hit.flatMap { role($0) }).rawValue)
            }
            pause(deadline)
        }
        return false
    }

    /// Live 3.1.0 flattens title/menu/controls into adjacent direct children.
    /// Only the ten-node controls branch and one-text title branch are read;
    /// the shared panel's chat descendants cannot affect this lookup.
    static func titleMenuButton(_ root: AXUIElement, title: String, deadline: TimeInterval,
                                defaultWorkspace: Bool = false) -> AXUIElement? {
        var unused = false
        return titleMenuButton(root, title: title, deadline: deadline, rejectOpenMenu: false,
                               menuAlreadyOpen: &unused, defaultWorkspace: defaultWorkspace)
    }
    static func titleMenuButton(_ root: AXUIElement, title: String, deadline: TimeInterval,
                                rejectOpenMenu: Bool, menuAlreadyOpen: inout Bool,
                                defaultWorkspace: Bool = false) -> AXUIElement? {
        let visited = nodes(root, deadline)
        if rejectOpenMenu {
            menuAlreadyOpen = visited.contains { role($0) == "AXMenu" || classes($0).contains("ant-dropdown-menu") }
            guard !menuAlreadyOpen, remaining(deadline) else { return nil }
        }
        let choosers = visited.filter { role($0) == "AXButton" && ["选择 IDE", "Choose IDE"].contains(exactLabel($0) ?? "") }
        let terminals = visited.filter { role($0) == "AXButton" && ["打开终端", "Open terminal"].contains(exactLabel($0) ?? "") }
        if defaultWorkspace {
            var diagnostic = MiniMaxCodeCopyDiagnostic()
            diagnostic.stage = .topbar
            diagnostic.reason = .terminalButtonAmbiguous
            diagnostic.searchCount = terminals.count
            defer { MiniMaxCodeCopyDiagnosticRecorder.record(diagnostic) }
            guard terminals.count == 1 else { return nil }
            diagnostic.reason = .topbarParentUnavailable
            // Electron inserts unnamed one-child layout groups which the
            // flattened accessibility view omits. Ascend only this exact
            // terminal branch; never search a sidebar or body ancestor.
            guard let panel = MiniMaxCodeTopbarSelection.layoutParent(of: terminals[0], parent: parent,
                isUnnamedGroup: { role($0) == "AXGroup" && (exactLabel($0) ?? "").isEmpty },
                children: { elements($0, kAXChildrenAttribute) }, equal: { CFEqual($0, $1) },
                hasTime: { remaining(deadline) }) else { return nil }
            let children = elements(panel, kAXChildrenAttribute)
            diagnostic.searchNodes = children.count
            diagnostic.reason = .topbarChildrenInvalid
            guard children.count >= 3, children.count <= 8, remaining(deadline) else { return nil }
            func unwrapped(_ item: AXUIElement) -> AXUIElement? {
                MiniMaxCodeTopbarSelection.leaf(of: item, isGroup: { role($0) == "AXGroup" },
                    isUnnamed: { (exactLabel($0) ?? "").isEmpty },
                    children: { elements($0, kAXChildrenAttribute) }, hasTime: { remaining(deadline) })
            }
            // Inspect only the three adjacent topbar branches. Body siblings
            // remain opaque, and any multi-child wrapper is rejected.
            guard let heading = unwrapped(children[0]), let menu = unwrapped(children[1]),
                  let terminal = unwrapped(children[2]) else { return nil }
            diagnostic.focusedRole = role(heading) ?? "unavailable"
            diagnostic.focusEqual = text(heading) == title
            diagnostic.windowFocused = (exactLabel(menu) ?? "").isEmpty
            diagnostic.inputAvailable = action(menu, kAXPressAction)
            diagnostic.focusWindowMatches = CFEqual(terminal, terminals[0])
            diagnostic.reason = .topbarPrefixInvalid
            guard role(heading) == "AXStaticText", diagnostic.focusEqual,
                  role(menu) == "AXButton", diagnostic.windowFocused,
                  diagnostic.inputAvailable, diagnostic.focusWindowMatches,
                  MiniMaxCodeTopbarSelection.defaultWorkspaceMenuIndex(in:
                    [.title, .menu, .controls] + Array(repeating: .other, count: children.count - 3)) == 1 else { return nil }
            diagnostic.reason = .topbarVerified
            return menu
        }
        guard choosers.count == 1, terminals.count == 1,
              let controls = parent(choosers[0]), role(controls) == "AXGroup",
              let panel = parent(controls), role(panel) == "AXGroup", remaining(deadline) else { return nil }
        let controlMembers = nodes(controls, deadline, maximum: 17, depth: 4)
        guard controlMembers.count <= 16, remaining(deadline),
              controlMembers.contains(where: { CFEqual($0, choosers[0]) }),
              controlMembers.contains(where: { CFEqual($0, terminals[0]) }),
              !controlMembers.contains(where: { ["AXScrollArea", "AXTextArea", "AXWebArea", "AXWindow"].contains(role($0) ?? "") }) else { return nil }
        let children = elements(panel, kAXChildrenAttribute)
        guard children.count <= 8, remaining(deadline),
              children.contains(where: { CFEqual($0, controls) }) else { return nil }
        var branches: [MiniMaxCodeTopbarSelection.Branch] = []
        for child in children {
            guard remaining(deadline), let childParent = parent(child), CFEqual(childParent, panel) else { return nil }
            if CFEqual(child, controls) { branches.append(.controls); continue }
            if role(child) == "AXButton", (exactLabel(child) ?? "").isEmpty, action(child, kAXPressAction) {
                branches.append(.menu); continue
            }
            if role(child) == "AXGroup" {
                let titleChildren = elements(child, kAXChildrenAttribute)
                if titleChildren.count == 1, let heading = titleChildren.first,
                   role(heading) == "AXStaticText", text(heading) == title,
                   let headingParent = parent(heading), CFEqual(headingParent, child) {
                    branches.append(.title); continue
                }
            }
            branches.append(.other)
        }
        let index = MiniMaxCodeTopbarSelection.menuIndex(in: branches)
        acceptanceLog(.titleMenuMatches, count: index == nil ? 0 : 1, nodes: children.count, flag: remaining(deadline))
        guard let index, remaining(deadline) else { return nil }
        return children[index]
    }
    static func parent(_ element: AXUIElement) -> AXUIElement? {
        guard let value = value(element, kAXParentAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
    static func projectHeaders(_ root: AXUIElement, path: String, deadline: TimeInterval) -> [AXUIElement] {
        let visited = nodes(root, deadline)
        let matches = visited.filter {
            role($0) == "AXButton" && (exactLabel($0) ?? "").hasSuffix(", " + path)
                && action($0, kAXPressAction)
        }
        acceptanceLog(.projectHeaders, count: matches.count, nodes: visited.count, flag: remaining(deadline))
        return matches
    }
    static func projectRows(_ header: AXUIElement, title: String, deadline: TimeInterval) -> [AXUIElement]? {
        guard let label = exactLabel(header) else {
            acceptanceLog(.projectHeaderLabelUnavailable); return nil
        }
        var node = header
        // Exactly the observed header/container/draggable project ancestry.
        // A larger unnamed ancestor is never accepted as a project boundary.
        for index in 0..<3 where remaining(deadline) {
            guard let parent = value(node, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else {
                acceptanceLog(.projectParentUnavailable, count: index + 1); return nil
            }
            node = unsafeDowncast(parent, to: AXUIElement.self)
            let labelOfGroup = exactLabel(node) ?? ""
            let nodeClasses = classes(node)
            let rendererGroup = nodeClasses.contains("space-y-px")
            let eligible = rendererGroup || labelOfGroup == label || labelOfGroup.hasPrefix(label + " ")
            guard eligible else {
                acceptanceParentLog(node, header: header, index: index + 1, classCount: nodeClasses.count,
                                    rendererGroup: rendererGroup, eligible: false, containsHeader: -1, deadline: deadline)
                continue
            }
            let members = nodes(node, deadline, maximum: 500, depth: 8)
            let containsHeader = members.contains(where: { CFEqual($0, header) })
            acceptanceParentLog(node, header: header, index: index + 1, classCount: nodeClasses.count,
                                rendererGroup: rendererGroup, eligible: true, containsHeader: containsHeader ? 1 : 0,
                                deadline: deadline)
            guard containsHeader else { return nil }
            let rows = members.filter {
                role($0) == "AXButton" && !CFEqual($0, header) && exactLabel($0) == title
                    && action($0, kAXPressAction)
            }
            if !rows.isEmpty || rendererGroup {
                acceptanceLog(.projectRows, count: rows.count, flag: remaining(deadline))
                let leaves = leafRows(rows, within: members, root: node, deadline: deadline)
                acceptanceLog(.projectLeafRows, count: leaves?.count ?? 0, flag: leaves != nil)
                return leaves
            }
        }
        return nil
    }
    /// Electron gives the draggable task wrapper and its nested task button the
    /// same title and AXPress action. Remove only confirmed ancestor wrappers;
    /// two separate task buttons remain ambiguous. Every parent must stay in
    /// the already admitted project subtree and reach its root within 8 links.
    static func leafRows(_ rows: [AXUIElement], within members: [AXUIElement],
                         root: AXUIElement, deadline: TimeInterval) -> [AXUIElement]? {
        var unique: [AXUIElement] = []
        for row in rows where !unique.contains(where: { CFEqual($0, row) }) { unique.append(row) }
        guard unique.count > 1 else { return unique }
        var ancestors: [AXUIElement] = []
        for row in unique {
            var node = row; var chain: [AXUIElement] = [row]; var reachedRoot = false
            for _ in 0..<8 {
                guard remaining(deadline), let parent = value(node, kAXParentAttribute),
                      CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
                node = unsafeDowncast(parent, to: AXUIElement.self)
                guard members.contains(where: { CFEqual($0, node) }),
                      !chain.contains(where: { CFEqual($0, node) }) else { return nil }
                chain.append(node)
                if unique.contains(where: { CFEqual($0, node) }) { ancestors.append(node) }
                if CFEqual(node, root) { reachedRoot = true; break }
            }
            guard reachedRoot else { return nil }
        }
        return unique.filter { candidate in !ancestors.contains(where: { CFEqual($0, candidate) }) }
    }
    static func waitForMenuLabel(_ labels: [String], source: MiniMaxCodeConversationUI.Source,
                                 deadline: TimeInterval) -> AXUIElement? {
        while remaining(deadline) {
            if let root = window(source) {
                let menus = nodes(root, deadline).filter { role($0) == "AXMenu" || classes($0).contains("ant-dropdown-menu") }
                var matches: [AXUIElement] = []
                for menu in menus {
                    for item in nodes(menu, deadline) where ["AXMenuItem", "AXButton"].contains(role(item) ?? "") {
                        guard labels.contains(exactLabel(item) ?? ""), action(item, kAXPressAction) else { continue }
                        if !matches.contains(where: { CFEqual($0, item) }) { matches.append(item) }
                    }
                }
                if matches.count == 1 { return matches[0] }
                if matches.count > 1 { return nil }
            }
            pause(deadline)
        }
        return nil
    }
    static func window(_ source: MiniMaxCodeConversationUI.Source) -> AXUIElement? {
        let root = AXUIElementCreateApplication(source.processID)
        AXUIElementSetMessagingTimeout(root, 0.08)
        var output: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &output)
        let values = error == .success ? (output as? [AXUIElement] ?? []) : []
        acceptanceLog(.windowQuery, count: values.count, error: Int(error.rawValue), flag: error == .success)
        acceptanceWindowLog(values)
        // Live 3.1.0 exposes an auxiliary AXDialog beside its standard main
        // window. Admit one exact, non-minimized standard window only, then
        // require its project header and copied native session ID as before.
        guard values.count <= 8 else { return nil }
        let attributes = values.map {
            MiniMaxCodeWindowSelection.Attributes(role: role($0),
                subrole: value($0, kAXSubroleAttribute) as? String,
                title: value($0, kAXTitleAttribute) as? String,
                isMain: bool($0, kAXMainAttribute),
                isMinimized: bool($0, kAXMinimizedAttribute))
        }
        guard let index = MiniMaxCodeWindowSelection.mainIndex(in: attributes) else { return nil }
        return values[index]
    }
    static func nodes(_ root: AXUIElement, _ deadline: TimeInterval, maximum: Int = 4000, depth maximumDepth: Int = 48) -> [AXUIElement] {
        var queue: [(AXUIElement, Int)] = [(root, 0)]; var output: [AXUIElement] = []; var index = 0
        while index < queue.count, output.count < maximum, remaining(deadline) {
            let (node, depth) = queue[index]; index += 1; output.append(node)
            if depth < maximumDepth { queue += elements(node, kAXChildrenAttribute).map { ($0, depth + 1) } }
        }
        return output
    }
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var output: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &output) == .success else { return nil }
        return output
    }
    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] { value(element, attribute) as? [AXUIElement] ?? [] }
    static func role(_ element: AXUIElement) -> String? { value(element, kAXRoleAttribute) as? String }
    /// Electron uses Title for some native button/container labels and Description
    /// for others. Preserve exact label text; Value belongs to body/static text,
    /// and must never become a button label or project boundary.
    static func exactLabel(_ element: AXUIElement) -> String? {
        for attribute in [kAXDescriptionAttribute, kAXTitleAttribute] {
            if let label = value(element, attribute) as? String,
               !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return label
            }
        }
        return nil
    }
    static func text(_ element: AXUIElement) -> String? {
        for attribute in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            if let text = value(element, attribute) as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? { value(element, attribute) as? Bool }
    static func classes(_ element: AXUIElement) -> [String] { value(element, "AXDOMClassList") as? [String] ?? [] }
    static func action(_ element: AXUIElement, _ name: String) -> Bool {
        var output: CFArray?
        return AXUIElementCopyActionNames(element, &output) == .success && (output as? [String] ?? []).contains(name)
    }
    static func press(_ element: AXUIElement, _ deadline: TimeInterval) -> Bool {
        remaining(deadline) && AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }
    static func remaining(_ deadline: TimeInterval) -> Bool { ProcessInfo.processInfo.systemUptime < deadline }
    static func pause(_ deadline: TimeInterval) { Thread.sleep(forTimeInterval: max(0, min(0.04, deadline - ProcessInfo.processInfo.systemUptime))) }
}
