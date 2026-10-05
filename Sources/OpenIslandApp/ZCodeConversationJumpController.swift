import AppKit
import ApplicationServices
import CryptoKit
import Foundation
import SQLite3

struct ZCodeConversationRecord: Equatable, Sendable {
    let id: String
    let title: String
    let workspacePath: String
}

/// Read-only access to ZCode's task index. ZCode writes the same stable
/// `sess_*` identifier into hook payloads and the `tasks.task_id` column, so
/// this is the missing bridge between an Open Island session and the title
/// rendered in ZCode's conversation sidebar.
struct ZCodeTaskIndex: Sendable {
    let databasePath: String

    init(databasePath: String = ZCodeTaskIndex.defaultDatabasePath()) {
        self.databasePath = databasePath
    }

    static func defaultDatabasePath() -> String {
        NSHomeDirectory() + "/.zcode/v2/tasks-index.sqlite"
    }

    func conversation(id: String) -> ZCodeConversationRecord? {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else { return nil }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databasePath, &database, flags, nil) == SQLITE_OK,
              let database else {
            if database != nil {
                sqlite3_close(database)
            }
            return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 100)

        let sql = """
        SELECT title, workspace_path
        FROM tasks
        WHERE task_id = ? AND deleted = 0
        ORDER BY updated_at DESC
        LIMIT 1;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        let heldID = normalizedID.withCString { strdup($0) }
        defer { free(heldID) }
        sqlite3_bind_text(statement, 1, heldID, -1, nil)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let titleValue = sqlite3_column_text(statement, 0),
              let workspaceValue = sqlite3_column_text(statement, 1) else {
            return nil
        }

        let title = String(cString: titleValue).trimmingCharacters(in: .whitespacesAndNewlines)
        let workspacePath = String(cString: workspaceValue)
        guard !title.isEmpty else { return nil }

        return ZCodeConversationRecord(
            id: normalizedID,
            title: title,
            workspacePath: workspacePath
        )
    }

    /// A standalone task has a workspace directory but no matching project
    /// section in the sidebar. Only allow a title lookup outside its project
    /// when the local index proves that title identifies this one task.
    func hasUniqueTitle(for conversation: ZCodeConversationRecord) -> Bool {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
                == SQLITE_OK,
              let database else {
            if database != nil { sqlite3_close(database) }
            return false
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 100)

        let sql = "SELECT task_id, workspace_path FROM tasks WHERE TRIM(title) = ? AND deleted = 0;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return false }
        defer { sqlite3_finalize(statement) }
        let heldTitle = conversation.title.withCString { strdup($0) }
        defer { free(heldTitle) }
        sqlite3_bind_text(statement, 1, heldTitle, -1, nil)

        var found = false
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return found }
            guard result == SQLITE_ROW,
                  let id = sqlite3_column_text(statement, 0),
                  let workspace = sqlite3_column_text(statement, 1),
                  String(cString: id) == conversation.id,
                  String(cString: workspace) == conversation.workspacePath else {
                return false
            }
            found = true
        }
    }
}

enum ZCodeConversationFocusResult: Equatable, Sendable {
    case focused
    case unavailable(String)
}

/// Only metadata from a failed, explicitly requested navigation is retained.
/// Attribute values can contain URLs or IDs, so retain hashes rather than text.
struct ZCodeNavigationDiagnostic: Equatable, Sendable {
    struct Element: Equatable, Sendable {
        var attributeNames: [String]
        var identityHashes: [String: String]
        var identityMatches: [String: Bool]
        var hasPressAction: Bool
        var hasTaskClass: Bool
        var hasSelectedClass: Bool

        init(attributeNames: [String], identityValues: [String: String], targetID: String,
             hasPressAction: Bool = false, hasTaskClass: Bool = false, hasSelectedClass: Bool = false) {
            self.hasPressAction = hasPressAction
            self.hasTaskClass = hasTaskClass
            self.hasSelectedClass = hasSelectedClass
            self.attributeNames = attributeNames.filter {
                $0.hasPrefix("AX") && $0.count <= 80
                    && $0.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
            }.sorted().prefix(64).map { $0 }
            let allowed = ["AXIdentifier", "AXDOMIdentifier", "AXURL"]
            let values = identityValues.filter { allowed.contains($0.key) && $0.value.utf8.count <= 4_096 }
            identityHashes = values.mapValues { ZCodeNavigationDiagnostic.hash($0) }
            identityMatches = values.mapValues { $0 == targetID }
        }
    }

    var targetHash: String
    var rowCount: Int
    var selectedRowCount: Int
    var headingMatches: Bool
    var row: Element?
    var content: Element?
    var matchingLabelCount = 0
    var labelAncestors: [Element] = []
    var samplingExpired = false

    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var line: String {
        func describe(_ element: Element?) -> String {
            guard let element else { return "missing" }
            let values = element.identityHashes.keys.sorted().map { key in
                "\(key):\(element.identityHashes[key] ?? ""):equal=\(element.identityMatches[key] == true)"
            }.joined(separator: ",")
            return "press=\(element.hasPressAction);taskClass=\(element.hasTaskClass);selectedClass=\(element.hasSelectedClass);attrs=\(element.attributeNames.joined(separator: ","));identities=\(values)"
        }
        let ancestors = labelAncestors.prefix(4).map { describe($0) }.joined(separator: " | ")
        return "reason=active-content-unverified targetHash=\(targetHash) rows=\(rowCount) selected=\(selectedRowCount) labels=\(matchingLabelCount) headingMatches=\(headingMatches) samplingExpired=\(samplingExpired) row=[\(describe(row))] content=[\(describe(content))] labelAncestors=[\(ancestors)]"
    }
}

/// Opt-in copy-stage data has a fixed vocabulary; it never retains AX text,
/// pasteboard values, source paths, or raw session IDs.
struct ZCodeCopyDiagnostic: Equatable, Sendable {
    enum Stage: String, Sendable { case header, menu, item, clipboard, identity, complete }
    enum Reason: String, Sendable {
        case sourceUnavailable, headerAmbiguous, menuAlreadyOpen, headerPressFailed
        case menuUnavailable, menuAmbiguous, itemAmbiguous, itemUnavailable
        case itemNotPressable, itemDisabled, sourceOrWindowChanged, deadlineExpired
        case clipboardUnavailable, clipboardChanged, itemPressFailed
        case copyUnobserved, copyMismatchOrRestoreFailed, selectedRowUnverified, taskIndexChanged, verified
    }
    var targetHash: String
    var stage: Stage = .header
    var reason: Reason = .sourceUnavailable
    var headerCount = 0
    var menuCount = 0
    var itemCount = 0
    var valueMatches = false
    var titleMatches = false
    var descriptionMatches = false
    var itemRole: String?
    var hasPressAction = false
    var enabled: Bool?
    var deadlineExpired = false
    var menuBudgetExpired = false
    var cancelAttempted = false
    var cancelSucceeded = false

    var line: String {
        let allowedRoles = ["AXMenuItem", "AXStaticText", "AXButton", "AXPopUpButton", "AXMenu"]
        let role = itemRole.flatMap { allowedRoles.contains($0) ? $0 : nil } ?? "unavailable"
        let enabledText = enabled.map { String($0) } ?? "unavailable"
        return "reason=copy-stage-\(reason.rawValue) targetHash=\(targetHash) stage=\(stage.rawValue) headers=\(min(max(headerCount, 0), 5000)) menus=\(min(max(menuCount, 0), 5000)) items=\(min(max(itemCount, 0), 5000)) valueMatches=\(valueMatches) titleMatches=\(titleMatches) descriptionMatches=\(descriptionMatches) itemRole=\(role) press=\(hasPressAction) enabled=\(enabledText) deadlineExpired=\(deadlineExpired) menuBudgetExpired=\(menuBudgetExpired) cancelAttempted=\(cancelAttempted) cancelSucceeded=\(cancelSucceeded)"
    }
}

enum ZCodeCopyMenuContract {
    static func matchesCopyLabel(_ text: String?) -> Bool {
        guard let text else { return false }
        return ["复制会话 ID", "Copy session ID"].contains(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    static func isCopyItem(value: String?, title: String?, description: String?) -> Bool {
        [value, title, description].contains(where: matchesCopyLabel)
    }
    static func permitsCancel(openedByNavigation: Bool, sameSource: Bool, sameWindow: Bool,
                              sourceFrontmost: Bool, hasTime: Bool, menuCount: Int,
                              hasCancelAction: Bool) -> Bool {
        openedByNavigation && sameSource && sameWindow && sourceFrontmost && hasTime
            && menuCount == 1 && hasCancelAction
    }
}

/// The menu can close before Chromium restores its sidebar AX nodes.
/// Wait only for observations; never repeat the copy action or touch clipboard.
enum ZCodePostCopyIdentityGate {
    struct Sample {
        var menuClosed: Bool
        var rowCount: Int
        var selectedRowCount: Int
    }
    enum Result: Equatable { case verified, unverified, sourceOrWindowChanged, taskIndexChanged, deadlineExpired }

    static func wait(copiedID: String?, targetID: String, restored: Bool,
                     before deadline: TimeInterval, clock: () -> TimeInterval,
                     sleep: (TimeInterval) -> Void, contextIsCurrent: () -> Bool,
                     metadataIsCurrent: () -> Bool, sample: () -> Sample) -> Result {
        guard restored, !targetID.isEmpty, copiedID == targetID else { return .unverified }
        while clock() < deadline {
            guard contextIsCurrent() else { return .sourceOrWindowChanged }
            let state = sample()
            guard clock() < deadline else { return .deadlineExpired }
            guard contextIsCurrent() else { return .sourceOrWindowChanged }
            if state.menuClosed, ZCodeSidebarContract.verifiesIdentity(
                rowCount: state.rowCount, selectedRowCount: state.selectedRowCount,
                copiedID: copiedID, targetID: targetID) {
                guard metadataIsCurrent() else { return .taskIndexChanged }
                // Metadata and AX queries can consume the remaining budget or
                // overlap a source/window change; re-admit after both queries.
                guard clock() < deadline else { return .deadlineExpired }
                guard contextIsCurrent() else { return .sourceOrWindowChanged }
                return .verified
            }
            let remaining = deadline - clock()
            if remaining > 0 { sleep(min(0.02, remaining)) }
        }
        return .deadlineExpired
    }
}

/// Injected metadata-only UI boundary; fixture tests never launch ZCode.
struct ZCodeConversationUI: Sendable {
    struct Source: Equatable, Sendable {
        var processID: pid_t
        var version: String
    }
    var isAccessibilityAvailable: @Sendable () -> Bool
    var source: @Sendable () -> Source?
    var select: @Sendable (ZCodeConversationRecord, Source, TimeInterval) -> Bool
    var copyActiveSessionID: @Sendable (ZCodeConversationRecord, Source, TimeInterval) -> String?
    var isFrontmost: @Sendable (Source) -> Bool
    var isCurrentWindow: @Sendable () -> Bool = { true }
}

/// Public renderer row contracts: both variants bind Enter/Space to their own
/// task ID. A plain list item need not expose AXPress in Chromium.
enum ZCodeSidebarContract {
    // Chromium exposes aria-haspopup menu buttons as AXPopUpButton on macOS.
    // Their header scope and AXPress action are still required by the caller.
    static func isHeaderMenuRole(_ role: String?) -> Bool {
        role == "AXButton" || role == "AXPopUpButton"
    }

    static func isTaskRow(classes: [String]) -> Bool {
        classes.contains("group/task-item") || classes.contains("group/task-row")
    }
    static func permitsEnter(classes: [String], focusSettable: Bool, exactFocus: Bool,
                             sourceFrontmost: Bool) -> Bool {
        isTaskRow(classes: classes) && focusSettable && exactFocus && sourceFrontmost
    }
    static func verifiesIdentity(rowCount: Int, selectedRowCount: Int, copiedID: String?, targetID: String) -> Bool {
        rowCount == 1 && selectedRowCount == 1 && !targetID.isEmpty && copiedID == targetID
    }
}

/// Focuses a ZCode conversation without reopening its workspace. ZCode 3.14
/// does not route conversation IDs through its URL scheme, but its task index
/// and Chromium accessibility tree expose enough stable information to press
/// the exact existing sidebar entry and verify the native ID via its public header menu.
struct ZCodeConversationJumpController: Sendable {
    typealias Sleeper = @Sendable (TimeInterval) -> Void
    typealias MonotonicClock = @Sendable () -> TimeInterval

    private let taskIndex: ZCodeTaskIndex
    private let ui: ZCodeConversationUI?
    private let sleeper: Sleeper
    private let clock: MonotonicClock
    private let focusTimeout: TimeInterval
    private let metadataDiagnosticsEnabled: @Sendable () -> Bool
    private let metadataDiagnostics: @Sendable (ZCodeNavigationDiagnostic) -> Void
    private let copyDiagnostics: @Sendable (ZCodeCopyDiagnostic) -> Void

    init(
        taskIndex: ZCodeTaskIndex = ZCodeTaskIndex(),
        ui: ZCodeConversationUI? = nil,
        sleeper: @escaping Sleeper = { Thread.sleep(forTimeInterval: $0) },
        clock: @escaping MonotonicClock = { ProcessInfo.processInfo.systemUptime },
        focusTimeout: TimeInterval = 3,
        metadataDiagnosticsEnabled: @escaping @Sendable () -> Bool = Self.defaultMetadataDiagnosticsEnabled,
        metadataDiagnostics: @escaping @Sendable (ZCodeNavigationDiagnostic) -> Void = Self.writeMetadataDiagnostic,
        copyDiagnostics: @escaping @Sendable (ZCodeCopyDiagnostic) -> Void = Self.writeCopyDiagnostic
    ) {
        self.taskIndex = taskIndex
        self.ui = ui
        self.sleeper = sleeper
        self.clock = clock
        self.focusTimeout = max(0, focusTimeout)
        self.metadataDiagnosticsEnabled = metadataDiagnosticsEnabled
        self.metadataDiagnostics = metadataDiagnostics
        self.copyDiagnostics = copyDiagnostics
    }

    func focus(conversationID: String) -> ZCodeConversationFocusResult {
        let deadline = clock() + focusTimeout
        guard let conversation = taskIndex.conversation(id: conversationID) else {
            return .unavailable("task-index-miss")
        }
        guard hasTimeRemaining(before: deadline) else {
            return .unavailable("focus-timeout")
        }
        guard ui?.isAccessibilityAvailable() ?? AXIsProcessTrusted() else {
            return .unavailable("accessibility-unavailable")
        }
        guard let source = ui?.source() ?? (ui == nil ? runningSource() : nil),
              source.version == "3.14.4", source.processID > 0 else {
            return .unavailable("source-version-or-process-unavailable")
        }
        let selected = ui.map { $0.select(conversation, source, deadline) }
            ?? select(conversation, source: source, before: deadline)
        guard selected else { return .unavailable("sidebar-conversation-miss") }
        guard hasTimeRemaining(before: deadline) else { return .unavailable("focus-timeout") }
        guard currentSource() == source, isFrontmost(source) else { return .unavailable("source-changed") }
        let navigationWindow = ui == nil ? NSRunningApplication(processIdentifier: source.processID)
            .flatMap { firstWindow(of: $0) } : nil
        let copied = ui.map { $0.copyActiveSessionID(conversation, source, deadline) }
            ?? copyActiveSessionID(conversation, source: source, before: deadline)
        guard copied == conversation.id else {
            if ui == nil, metadataDiagnosticsEnabled(),
               let application = NSRunningApplication(processIdentifier: source.processID),
               let window = firstWindow(of: application) {
                recordFailedNavigation(conversation, window: window,
                    allowsStandaloneLookup: taskIndex.hasUniqueTitle(for: conversation))
            }
            return .unavailable("active-session-id-unverified")
        }
        guard hasTimeRemaining(before: deadline) else { return .unavailable("focus-timeout") }
        guard taskIndex.conversation(id: conversation.id) == conversation else {
            return .unavailable("task-index-changed")
        }
        let sameWindow: Bool
        if let ui { sameWindow = ui.isCurrentWindow() }
        else if let navigationWindow, let application = NSRunningApplication(processIdentifier: source.processID),
                let current = firstWindow(of: application) { sameWindow = CFEqual(navigationWindow, current) }
        else { sameWindow = false }
        guard currentSource() == source, isFrontmost(source), sameWindow else {
            return .unavailable("source-or-window-changed")
        }
        return .focused
    }

    private func currentSource() -> ZCodeConversationUI.Source? {
        if let ui { return ui.source() }
        return runningSource()
    }

    private func runningSource() -> ZCodeConversationUI.Source? {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.zcode.app")
            .filter { $0.processIdentifier > 0 }
        guard apps.count == 1, let app = apps.first, let url = app.bundleURL,
              let version = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return nil }
        return .init(processID: app.processIdentifier, version: version)
    }

    private func isFrontmost(_ source: ZCodeConversationUI.Source) -> Bool {
        ui?.isFrontmost(source) ?? (NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processID)
    }

    private func select(_ conversation: ZCodeConversationRecord, source: ZCodeConversationUI.Source,
                        before deadline: TimeInterval) -> Bool {
        guard currentSource() == source,
              let application = NSRunningApplication(processIdentifier: source.processID) else { return false }
        // Electron may report an empty AXWindows array while ZCode is in the
        // background. Activation must happen before window lookup; waiting on
        // the hidden app alone never makes the accessibility window appear.
        application.unhide()
        guard hasTimeRemaining(before: deadline) else {
            return false
        }
        application.activate(options: [.activateAllWindows])
        guard let window = waitForWindow(of: application, before: deadline) else { return false }

        guard raise(window: window, before: deadline) else {
            return false
        }

        let workspaceName = URL(fileURLWithPath: conversation.workspacePath).lastPathComponent
        let allowsStandaloneLookup = taskIndex.hasUniqueTitle(for: conversation)
        ensureProjectsView(in: window, before: deadline)
        guard let projectsWindow = waitForWindow(of: application, before: deadline) else { return false }
        expandProjectIfNeeded(named: workspaceName, in: projectsWindow, before: deadline)

        if let expandedWindow = waitForWindow(of: application, before: deadline),
           pressConversation(
               title: conversation.title,
               workspaceName: workspaceName,
               allowsStandaloneLookup: allowsStandaloneLookup,
               in: expandedWindow,
               before: deadline
           ),
           waitUntilConversationRowIsSelected(
               title: conversation.title,
               workspaceName: workspaceName,
               allowsStandaloneLookup: allowsStandaloneLookup,
               application: application,
               before: deadline
           ) {
            return verifyForeground(of: application, before: deadline) == .focused
        }

        // ZCode initially renders only a bounded number of conversations for
        // larger projects. Reveal additional pages and retry after each DOM
        // update. Re-resolve every AX element because Chromium node handles
        // become stale when the sidebar rerenders.
        for _ in 0..<20 where hasTimeRemaining(before: deadline) {
            guard let currentWindow = waitForWindow(of: application, before: deadline),
                  pressShowMore(
                    forProjectNamed: workspaceName,
                    allowsStandaloneLookup: allowsStandaloneLookup,
                    in: currentWindow,
                    before: deadline
                  ) else {
                break
            }
            sleep(0.08, before: deadline)
            if let revealedWindow = waitForWindow(of: application, before: deadline),
               pressConversation(
                   title: conversation.title,
                   workspaceName: workspaceName,
                   allowsStandaloneLookup: allowsStandaloneLookup,
                   in: revealedWindow,
                   before: deadline
               ),
               waitUntilConversationRowIsSelected(
                   title: conversation.title,
                   workspaceName: workspaceName,
                   allowsStandaloneLookup: allowsStandaloneLookup,
                   application: application,
                   before: deadline
               ) {
                return verifyForeground(of: application, before: deadline) == .focused
            }
        }

        if metadataDiagnosticsEnabled(), let window = firstWindow(of: application) {
            recordFailedNavigation(conversation, window: window, allowsStandaloneLookup: allowsStandaloneLookup)
        }
        return false
    }

    private func verifyForeground(
        of application: NSRunningApplication,
        before deadline: TimeInterval
    ) -> ZCodeConversationFocusResult {
        // Activation is asynchronous. Selecting the correct sidebar item
        // alone does not prove that the user can see the resulting window.
        for attempt in 0..<30 where hasTimeRemaining(before: deadline) {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier {
                return .focused
            }
            if attempt < 29 { sleep(0.05, before: deadline) }
        }
        return .unavailable("app-not-frontmost")
    }

    private func pressConversation(
        title: String,
        workspaceName: String,
        allowsStandaloneLookup: Bool,
        in root: AXUIElement,
        before deadline: TimeInterval
    ) -> Bool {
        guard hasTimeRemaining(before: deadline),
              let taskItem = conversationItem(
                titled: title,
                workspaceName: workspaceName,
                allowsStandaloneLookup: allowsStandaloneLookup,
                in: root,
                before: deadline
              ),
              hasTimeRemaining(before: deadline) else {
            return false
        }
        if hasAction(kAXPressAction as CFString, on: taskItem) {
            return AXUIElementPerformAction(taskItem, kAXPressAction as CFString) == .success
        }
        // Enter is legal only for this precise public row, after its own focus
        // has been observed in the admitted frontmost source process.
        guard let source = currentSource(), source.version == "3.14.4", isFrontmost(source),
              AXIsProcessTrusted(), CGPreflightPostEventAccess() else { return false }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(taskItem, kAXFocusedAttribute as CFString, &settable) == .success,
              settable.boolValue,
              AXUIElementSetAttributeValue(taskItem, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else { return false }
        let app = AXUIElementCreateApplication(source.processID)
        guard let focused = copyElementValue(of: app, attribute: kAXFocusedUIElementAttribute as CFString),
              ZCodeSidebarContract.permitsEnter(classes: domClasses(of: taskItem), focusSettable: true,
                exactFocus: CFEqual(focused, taskItem), sourceFrontmost: isFrontmost(source)),
              hasTimeRemaining(before: deadline), currentSource() == source,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false) else { return false }
        down.flags = []; up.flags = []
        down.postToPid(source.processID); up.postToPid(source.processID)
        return hasTimeRemaining(before: deadline)
    }

    private func copyActiveSessionID(_ conversation: ZCodeConversationRecord,
                                     source: ZCodeConversationUI.Source,
                                     before deadline: TimeInterval) -> String? {
        var diagnostic = ZCodeCopyDiagnostic(targetHash: ZCodeNavigationDiagnostic.hash(conversation.id))
        var openedMenu: AXUIElement?
        var menuWasOpened = false
        var copyDispatched = false
        var navigationWindow: AXUIElement?
        func sourceAndWindowAreCurrent() -> Bool {
            guard currentSource() == source, isFrontmost(source),
                  let original = navigationWindow,
                  let application = NSRunningApplication(processIdentifier: source.processID),
                  let current = firstWindow(of: application) else { return false }
            return CFEqual(current, original)
        }
        defer {
            // Cancel only the unique menu observed after our own header press.
            // Never extend the navigation deadline or send global Escape.
            if !copyDispatched, let menu = openedMenu {
                let current = sourceAndWindowAreCurrent()
                let menus = current && hasTimeRemaining(before: deadline) ? navigationWindow.map {
                    descendants(of: $0, before: deadline).filter {
                        copyStringValue(of: $0, attribute: kAXRoleAttribute as CFString) == "AXMenu"
                    }
                } ?? [] : []
                let sameMenu = menus.count == 1 && CFEqual(menus[0], menu)
                let hasCancel = hasAction(kAXCancelAction as CFString, on: menu)
                if ZCodeCopyMenuContract.permitsCancel(openedByNavigation: menuWasOpened,
                    sameSource: currentSource() == source, sameWindow: sameMenu && sourceAndWindowAreCurrent(),
                    sourceFrontmost: isFrontmost(source), hasTime: hasTimeRemaining(before: deadline),
                    menuCount: sameMenu ? 1 : 0, hasCancelAction: hasCancel) {
                    diagnostic.cancelAttempted = true
                    diagnostic.cancelSucceeded = AXUIElementPerformAction(menu, kAXCancelAction as CFString) == .success
                }
            }
            diagnostic.deadlineExpired = !hasTimeRemaining(before: deadline)
            if diagnostic.deadlineExpired, diagnostic.reason != .verified { diagnostic.reason = .deadlineExpired }
            if metadataDiagnosticsEnabled() { copyDiagnostics(diagnostic) }
        }
        guard hasTimeRemaining(before: deadline), currentSource() == source, isFrontmost(source),
              let application = NSRunningApplication(processIdentifier: source.processID),
              let window = firstWindow(of: application) else { return nil }
        navigationWindow = window
        let nodes = descendants(of: window, before: deadline)
        // A pre-existing menu is not ours to inspect, copy from, or dismiss.
        guard !nodes.contains(where: { copyStringValue(of: $0, attribute: kAXRoleAttribute as CFString) == "AXMenu" }) else {
            diagnostic.reason = .menuAlreadyOpen; return nil
        }
        let buttons = nodes.filter { node in
            guard ZCodeSidebarContract.isHeaderMenuRole(copyStringValue(of: node, attribute: kAXRoleAttribute as CFString)),
                  [displayedText(of: node), copyStringValue(of: node, attribute: kAXDescriptionAttribute as CFString)]
                    .compactMap({ $0 }).contains(where: { ["更多", "More"].contains($0) }),
                  hasAction(kAXPressAction as CFString, on: node) else { return false }
            return nearestAncestor(of: node, maximumLevels: 8, before: deadline) {
                domClasses(of: $0).contains("@container/workspace-header")
            } != nil
        }
        diagnostic.headerCount = buttons.count
        diagnostic.reason = .headerAmbiguous
        guard buttons.count == 1 else { return nil }
        diagnostic.reason = .sourceOrWindowChanged
        guard sourceAndWindowAreCurrent(), hasTimeRemaining(before: deadline) else { return nil }
        diagnostic.reason = .headerPressFailed
        guard AXUIElementPerformAction(buttons[0], kAXPressAction as CFString) == .success else { return nil }
        menuWasOpened = true
        diagnostic.stage = .menu
        diagnostic.reason = .menuUnavailable
        var copyItem: AXUIElement?
        // Reserve a small portion of the existing budget to cancel an opened
        // menu on failure. This does not lengthen the total focus deadline.
        let menuDeadline = deadline - 0.08
        while hasTimeRemaining(before: menuDeadline) {
            diagnostic.reason = .sourceOrWindowChanged
            guard sourceAndWindowAreCurrent() else { return nil }
            let menus = descendants(of: window, before: menuDeadline).filter {
                copyStringValue(of: $0, attribute: kAXRoleAttribute as CFString) == "AXMenu"
            }
            diagnostic.menuCount = menus.count
            diagnostic.reason = menus.count > 1 ? .menuAmbiguous : .menuUnavailable
            guard menus.count <= 1 else { return nil }
            if let menu = menus.first {
                openedMenu = menu
                diagnostic.stage = .item
                var matches: [AXUIElement] = []
                for node in descendants(of: menu, before: menuDeadline) {
                    let value = copyStringValue(of: node, attribute: kAXValueAttribute as CFString)
                    let title = copyStringValue(of: node, attribute: kAXTitleAttribute as CFString)
                    let description = copyStringValue(of: node, attribute: kAXDescriptionAttribute as CFString)
                    guard ZCodeCopyMenuContract.isCopyItem(value: value, title: title, description: description) else { continue }
                    diagnostic.valueMatches = diagnostic.valueMatches || ZCodeCopyMenuContract.matchesCopyLabel(value)
                    diagnostic.titleMatches = diagnostic.titleMatches || ZCodeCopyMenuContract.matchesCopyLabel(title)
                    diagnostic.descriptionMatches = diagnostic.descriptionMatches || ZCodeCopyMenuContract.matchesCopyLabel(description)
                    diagnostic.itemRole = copyStringValue(of: node, attribute: kAXRoleAttribute as CFString)
                    let item = diagnostic.itemRole == "AXMenuItem" ? node : nearestAncestor(of: node, maximumLevels: 4, before: menuDeadline) {
                        copyStringValue(of: $0, attribute: kAXRoleAttribute as CFString) == "AXMenuItem"
                    }
                    // The actionable item must belong to the one menu we opened.
                    if let item, let parentMenu = nearestAncestor(of: item, maximumLevels: 8, before: menuDeadline, matching: {
                        copyStringValue(of: $0, attribute: kAXRoleAttribute as CFString) == "AXMenu"
                    }), CFEqual(parentMenu, menu), !matches.contains(where: { CFEqual($0, item) }) { matches.append(item) }
                }
                diagnostic.itemCount = matches.count
                diagnostic.reason = matches.count > 1 ? .itemAmbiguous : .itemUnavailable
                guard matches.count <= 1 else { return nil }
                if let item = matches.first {
                    diagnostic.itemRole = copyStringValue(of: item, attribute: kAXRoleAttribute as CFString)
                    diagnostic.hasPressAction = hasAction(kAXPressAction as CFString, on: item)
                    diagnostic.enabled = copyBoolValue(of: item, attribute: kAXEnabledAttribute as CFString)
                    diagnostic.reason = .itemNotPressable
                    guard diagnostic.hasPressAction else { return nil }
                    diagnostic.reason = .itemDisabled
                    if diagnostic.enabled == true { copyItem = item; break }
                }
            }
            sleep(0.02, before: menuDeadline)
        }
        diagnostic.menuBudgetExpired = !hasTimeRemaining(before: menuDeadline)
        guard let copyItem else { return nil }
        diagnostic.reason = .sourceOrWindowChanged
        guard sourceAndWindowAreCurrent(), hasTimeRemaining(before: deadline) else { return nil }
        diagnostic.stage = .clipboard
        diagnostic.reason = .clipboardUnavailable
        let board = NSPasteboard.general
        guard let snapshot = MiniMaxCodePasteboardSnapshot.capture(board) else { return nil }
        diagnostic.reason = .clipboardChanged
        guard board.changeCount == snapshot.originalChangeCount else { return nil }
        diagnostic.reason = .sourceOrWindowChanged
        guard sourceAndWindowAreCurrent(), hasTimeRemaining(before: deadline) else { return nil }
        diagnostic.reason = .itemDisabled
        guard copyBoolValue(of: copyItem, attribute: kAXEnabledAttribute as CFString) == true,
              hasAction(kAXPressAction as CFString, on: copyItem) else { return nil }
        diagnostic.reason = .sourceOrWindowChanged
        guard sourceAndWindowAreCurrent(), hasTimeRemaining(before: deadline) else { return nil }
        diagnostic.reason = .clipboardChanged
        guard board.changeCount == snapshot.originalChangeCount else { return nil }
        diagnostic.reason = .itemPressFailed
        guard AXUIElementPerformAction(copyItem, kAXPressAction as CFString) == .success else { return nil }
        copyDispatched = true
        diagnostic.reason = .copyUnobserved
        // Keep the existing bounded transaction and exact-ID-only restoration.
        let cleanupDeadline = max(deadline, clock() + 0.3)
        while hasTimeRemaining(before: cleanupDeadline) {
            if board.changeCount != snapshot.originalChangeCount {
                diagnostic.reason = .copyMismatchOrRestoreFailed
                guard let result = snapshot.consumeMatchingCopy(board, expectedID: conversation.id), result.restored else { return nil }
                diagnostic.reason = .sourceOrWindowChanged
                guard hasTimeRemaining(before: deadline), sourceAndWindowAreCurrent() else { return nil }
                diagnostic.stage = .identity
                diagnostic.reason = .selectedRowUnverified
                let workspace = URL(fileURLWithPath: conversation.workspacePath).lastPathComponent
                let verification = ZCodePostCopyIdentityGate.wait(copiedID: result.sessionID,
                    targetID: conversation.id, restored: result.restored, before: deadline,
                    clock: clock, sleep: sleeper, contextIsCurrent: sourceAndWindowAreCurrent,
                    metadataIsCurrent: { taskIndex.conversation(id: conversation.id) == conversation }, sample: {
                        // Reacquire live AX nodes on every poll in the same
                        // admitted window. A menu obscures the body briefly.
                        let menuClosed = !descendants(of: window, before: deadline).contains {
                            copyStringValue(of: $0, attribute: kAXRoleAttribute as CFString) == "AXMenu"
                        }
                        guard menuClosed else { return .init(menuClosed: false, rowCount: 0, selectedRowCount: 0) }
                        let row = conversationItem(titled: conversation.title, workspaceName: workspace,
                            allowsStandaloneLookup: taskIndex.hasUniqueTitle(for: conversation), in: window, before: deadline)
                        return .init(menuClosed: true, rowCount: row == nil ? 0 : 1,
                            selectedRowCount: row.map { domClasses(of: $0).contains("bg-selected") ? 1 : 0 } ?? 0)
                    })
                switch verification {
                case .verified: break
                case .sourceOrWindowChanged: diagnostic.reason = .sourceOrWindowChanged; return nil
                case .taskIndexChanged: diagnostic.reason = .taskIndexChanged; return nil
                case .deadlineExpired: diagnostic.reason = .deadlineExpired; return nil
                case .unverified: return nil
                }
                diagnostic.stage = .complete
                diagnostic.reason = .verified
                return result.sessionID
            }
            sleep(0.02, before: cleanupDeadline)
        }
        return nil
    }

    private func waitUntilConversationRowIsSelected(
        title: String,
        workspaceName: String,
        allowsStandaloneLookup: Bool,
        application: NSRunningApplication,
        before deadline: TimeInterval
    ) -> Bool {
        // Electron temporarily removes its AXWindow while navigating between
        // conversations. Reacquire the window and DOM nodes on every poll;
        // stale Chromium elements can otherwise make a completed transition
        // look like a miss or, worse, a false success.
        for attempt in 0..<60 where hasTimeRemaining(before: deadline) {
            if let window = firstWindow(of: application),
               let item = conversationItem(
                titled: title,
                workspaceName: workspaceName,
                allowsStandaloneLookup: allowsStandaloneLookup,
                in: window,
                before: deadline
               ),
               domClasses(of: item).contains("bg-selected") {
                return true
            }
            if attempt < 59 {
                sleep(0.05, before: deadline)
            }
        }
        return false
    }

    private static let diagnosticMarker = "/tmp/aisland-zcode-metadata-diagnostics-enabled"
    private static let diagnosticLog = "/tmp/aisland-zcode-metadata-diagnostics.log"

    private static func defaultMetadataDiagnosticsEnabled() -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: diagnosticMarker)[.type] as? FileAttributeType) == .typeRegular
    }

    private static func writeMetadataDiagnostic(_ diagnostic: ZCodeNavigationDiagnostic) {
        writeDiagnosticLine(diagnostic.line)
    }

    private static func writeCopyDiagnostic(_ diagnostic: ZCodeCopyDiagnostic) {
        writeDiagnosticLine(diagnostic.line)
    }

    private static func writeDiagnosticLine(_ line: String) {
        guard defaultMetadataDiagnosticsEnabled() else { return }
        let descriptor = open(diagnosticLog, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(), info.st_size < 65_536 else { return }
        let data = Data((line + "\n").utf8)
        guard info.st_size + off_t(data.count) <= 65_536, fchmod(descriptor, 0o600) == 0 else { return }
        _ = data.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
    }

    private func recordFailedNavigation(
        _ conversation: ZCodeConversationRecord,
        window: AXUIElement,
        allowsStandaloneLookup: Bool
    ) {
        // A separate small diagnostic budget must not extend navigation polling.
        let deadline = clock() + 0.15
        let workspace = URL(fileURLWithPath: conversation.workspacePath).lastPathComponent
        let container = projectContainer(named: workspace, in: window, before: deadline)
            ?? (allowsStandaloneLookup ? window : nil)
        let rows = container.map { taskItems(titled: conversation.title, in: $0, before: deadline) } ?? []
        let selected = rows.filter { domClasses(of: $0).contains("bg-selected") }
        let sampledNodes = descendants(of: window, before: deadline)
        let content = sampledNodes.first {
            copyStringValue(of: $0, attribute: kAXDOMIdentifierAttribute as CFString) == "conversation"
        }
        let labels = sampledNodes.filter {
            copyStringValue(of: $0, attribute: kAXRoleAttribute as CFString) == "AXStaticText"
                && displayedText(of: $0) == conversation.title
        }
        func metadata(_ element: AXUIElement?) -> ZCodeNavigationDiagnostic.Element? {
            guard let element else { return nil }
            var names: CFArray?
            _ = AXUIElementCopyAttributeNames(element, &names)
            var values: [String: String] = [:]
            for key in ["AXIdentifier", "AXDOMIdentifier", "AXURL"] {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success {
                    if let text = value as? String { values[key] = text }
                    else if let url = value as? URL { values[key] = url.absoluteString }
                }
            }
            let classes = domClasses(of: element)
            return .init(attributeNames: names as? [String] ?? [], identityValues: values, targetID: conversation.id,
                         hasPressAction: hasAction(kAXPressAction as CFString, on: element),
                         hasTaskClass: ZCodeSidebarContract.isTaskRow(classes: classes), hasSelectedClass: classes.contains("bg-selected"))
        }
        var labelAncestors: [ZCodeNavigationDiagnostic.Element] = []
        if var current = labels.first {
            for _ in 0..<4 where hasTimeRemaining(before: deadline) {
                guard let parent = copyElementValue(of: current, attribute: kAXParentAttribute as CFString),
                      let sample = metadata(parent) else { break }
                labelAncestors.append(sample)
                current = parent
            }
        }
        metadataDiagnostics(.init(
            targetHash: ZCodeNavigationDiagnostic.hash(conversation.id), rowCount: rows.count,
            selectedRowCount: selected.count,
            headingMatches: content.map { hasConversationHeading(conversation.title, in: $0, before: deadline) } ?? false,
            row: metadata(selected.first ?? rows.first), content: metadata(content),
            matchingLabelCount: labels.count, labelAncestors: labelAncestors,
            samplingExpired: !hasTimeRemaining(before: deadline)
        ))
    }

    private func ensureProjectsView(in root: AXUIElement, before deadline: TimeInterval) {
        for element in descendants(of: root, before: deadline) {
            guard displayedText(of: element) == "项目" || displayedText(of: element) == "Projects",
                  let tab = nearestAncestor(
                      of: element,
                      maximumLevels: 3,
                      before: deadline,
                      matching: { candidate in
                          let role = copyStringValue(
                              of: candidate,
                              attribute: kAXRoleAttribute as CFString
                          )
                          return (role == "AXTab" || role == "AXRadioButton")
                              && hasAction(kAXPressAction as CFString, on: candidate)
                      }
                  ) else {
                continue
            }
            if hasTimeRemaining(before: deadline),
               copyBoolValue(of: tab, attribute: kAXSelectedAttribute as CFString) != true {
                _ = AXUIElementPerformAction(tab, kAXPressAction as CFString)
                sleep(0.08, before: deadline)
            }
            return
        }
    }

    private func expandProjectIfNeeded(
        named workspaceName: String,
        in root: AXUIElement,
        before deadline: TimeInterval
    ) {
        guard hasTimeRemaining(before: deadline),
              !workspaceName.isEmpty,
              let button = projectButton(named: workspaceName, in: root, before: deadline),
              copyBoolValue(of: button, attribute: kAXExpandedAttribute as CFString) != true else {
            return
        }
        if AXUIElementPerformAction(button, kAXPressAction as CFString) == .success {
            sleep(0.08, before: deadline)
        }
    }

    private func pressShowMore(
        forProjectNamed workspaceName: String,
        allowsStandaloneLookup: Bool,
        in root: AXUIElement,
        before deadline: TimeInterval
    ) -> Bool {
        guard hasTimeRemaining(before: deadline) else {
            return false
        }

        let projectContainer = projectContainer(named: workspaceName, in: root, before: deadline)
        guard projectContainer != nil || allowsStandaloneLookup else { return false }
        // In the standalone Tasks list there is no project header. Avoid
        // guessing which pagination control to press if several are visible.
        var candidates: [AXUIElement] = []

        for element in descendants(of: projectContainer ?? root, before: deadline) {
            guard displayedText(of: element) == "显示更多" || displayedText(of: element) == "Show more",
                  let pressable = nearestPressableAncestor(
                    of: element,
                    maximumLevels: 2,
                    before: deadline
                  ),
                  hasTimeRemaining(before: deadline) else {
                continue
            }
            if !candidates.contains(where: { CFEqual($0, pressable) }) { candidates.append(pressable) }
        }
        guard candidates.count == 1, hasTimeRemaining(before: deadline) else { return false }
        return AXUIElementPerformAction(candidates[0], kAXPressAction as CFString) == .success
    }

    private func projectButton(
        named workspaceName: String,
        in root: AXUIElement,
        before deadline: TimeInterval
    ) -> AXUIElement? {
        var matches: [AXUIElement] = []
        for element in descendants(of: root, before: deadline)
        where displayedText(of: element) == workspaceName {
            if let button = nearestAncestor(
                of: element,
                maximumLevels: 3,
                before: deadline,
                matching: { candidate in
                    copyStringValue(of: candidate, attribute: kAXRoleAttribute as CFString) == "AXButton"
                        && hasAction(kAXPressAction as CFString, on: candidate)
                }
            ) {
                if !matches.contains(where: { CFEqual($0, button) }) { matches.append(button) }
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private func projectContainer(
        named workspaceName: String,
        in root: AXUIElement,
        before deadline: TimeInterval
    ) -> AXUIElement? {
        guard let button = projectButton(named: workspaceName, in: root, before: deadline) else {
            return nil
        }
        return nearestAncestor(of: button, maximumLevels: 3, before: deadline) { candidate in
            domClasses(of: candidate).contains("space-y-2")
        }
    }

    private func taskItem(
        titled title: String,
        in projectContainer: AXUIElement,
        before deadline: TimeInterval
    ) -> AXUIElement? {
        let items = taskItems(titled: title, in: projectContainer, before: deadline)
        return items.count == 1 ? items[0] : nil
    }

    private func conversationItem(
        titled title: String,
        workspaceName: String,
        allowsStandaloneLookup: Bool,
        in root: AXUIElement,
        before deadline: TimeInterval
    ) -> AXUIElement? {
        if let container = projectContainer(named: workspaceName, in: root, before: deadline) {
            return taskItem(titled: title, in: container, before: deadline)
        }
        guard allowsStandaloneLookup else { return nil }
        let candidates = taskItems(titled: title, in: root, before: deadline)
        return candidates.count == 1 ? candidates[0] : nil
    }

    private func taskItems(
        titled title: String,
        in root: AXUIElement,
        before deadline: TimeInterval
    ) -> [AXUIElement] {
        var items: [AXUIElement] = []
        for element in descendants(of: root, before: deadline)
        where copyStringValue(of: element, attribute: kAXRoleAttribute as CFString) == "AXStaticText"
            && displayedText(of: element) == title {
            if let item = nearestAncestor(
                of: element,
                maximumLevels: 8,
                before: deadline,
                matching: { candidate in
                    ZCodeSidebarContract.isTaskRow(classes: domClasses(of: candidate))
                }
            ) {
                if !items.contains(where: { CFEqual($0, item) }) { items.append(item) }
            }
        }
        return items
    }

    private func hasConversationHeading(
        _ title: String,
        in root: AXUIElement,
        before deadline: TimeInterval
    ) -> Bool {
        descendants(of: root, before: deadline).contains { element in
            guard copyStringValue(of: element, attribute: kAXRoleAttribute as CFString) == "AXHeading",
                  displayedText(of: element) == title else {
                return false
            }
            return nearestAncestor(of: element, maximumLevels: 4, before: deadline) { candidate in
                copyStringValue(of: candidate, attribute: kAXDOMIdentifierAttribute as CFString)
                    == "conversation"
            } != nil
        }
    }

    private func domClasses(of element: AXUIElement) -> [String] {
        copyStringArrayValue(of: element, attribute: "AXDOMClassList" as CFString) ?? []
    }

    private func descendants(of root: AXUIElement, before deadline: TimeInterval) -> [AXUIElement] {
        let maximumNodes = 5_000
        let maximumDepth = 64
        var result: [AXUIElement] = []
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var nextIndex = 0

        while nextIndex < queue.count,
              result.count < maximumNodes,
              hasTimeRemaining(before: deadline) {
            let (element, depth) = queue[nextIndex]
            nextIndex += 1
            result.append(element)
            guard depth < maximumDepth,
                  let children = copyElementArrayValue(
                    of: element,
                    attribute: kAXChildrenAttribute as CFString
                  ) else {
                continue
            }
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
        return result
    }

    private func nearestPressableAncestor(
        of element: AXUIElement,
        maximumLevels: Int,
        before deadline: TimeInterval
    ) -> AXUIElement? {
        nearestAncestor(of: element, maximumLevels: maximumLevels, before: deadline) { candidate in
            hasAction(kAXPressAction as CFString, on: candidate)
        }
    }

    private func nearestAncestor(
        of element: AXUIElement,
        maximumLevels: Int,
        before deadline: TimeInterval,
        matching predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        var current = element
        for _ in 0..<maximumLevels where hasTimeRemaining(before: deadline) {
            guard let parent = copyElementValue(
                of: current,
                attribute: kAXParentAttribute as CFString
            ) else {
                return nil
            }
            if predicate(parent) {
                return parent
            }
            current = parent
        }
        return nil
    }

    private func hasAction(_ action: CFString, on element: AXUIElement) -> Bool {
        var value: CFArray?
        guard AXUIElementCopyActionNames(element, &value) == .success,
              let actions = value as? [String] else {
            return false
        }
        return actions.contains(action as String)
    }

    private func displayedText(of element: AXUIElement) -> String? {
        let text = copyStringValue(of: element, attribute: kAXValueAttribute as CFString)
            ?? copyStringValue(of: element, attribute: kAXTitleAttribute as CFString)
        return text?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copyStringValue(of element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func copyBoolValue(of element: AXUIElement, attribute: CFString) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? Bool
    }

    private func copyStringArrayValue(of element: AXUIElement, attribute: CFString) -> [String]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? [String]
    }

    private func copyElementValue(of element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func copyElementArrayValue(of element: AXUIElement, attribute: CFString) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private func raise(window: AXUIElement, before deadline: TimeInterval) -> Bool {
        guard hasTimeRemaining(before: deadline) else { return false }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return hasTimeRemaining(before: deadline)
    }

    private func waitForWindow(
        of application: NSRunningApplication,
        before deadline: TimeInterval
    ) -> AXUIElement? {
        for attempt in 0..<30 where hasTimeRemaining(before: deadline) {
            if let window = firstWindow(of: application) {
                return window
            }
            if attempt < 29 {
                sleep(0.05, before: deadline)
            }
        }
        return nil
    }

    private func hasTimeRemaining(before deadline: TimeInterval) -> Bool {
        clock() < deadline
    }

    private func sleep(_ interval: TimeInterval, before deadline: TimeInterval) {
        let remaining = deadline - clock()
        guard remaining > 0 else { return }
        sleeper(min(interval, remaining))
    }

    private func firstWindow(of application: NSRunningApplication) -> AXUIElement? {
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        if let focused = copyElementValue(of: applicationElement, attribute: kAXFocusedWindowAttribute as CFString) {
            return focused
        }
        return copyElementArrayValue(
            of: applicationElement,
            attribute: kAXWindowsAttribute as CFString
        )?.first
    }
}
