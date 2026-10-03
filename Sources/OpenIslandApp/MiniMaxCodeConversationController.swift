import AppKit
import ApplicationServices
import Foundation
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
              target.runtimeSourceVersion == "3.1.0" else { return .unavailable("runtime-metadata-unavailable") }
        guard ui.isAccessibilityAvailable() else { return .unavailable("accessibility-unavailable") }
        guard let source = ui.source(), source.bundleIdentifier == "com.minimax.agent", source.version == "3.1.0" else {
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
        case titleSurfaceRoots = "title-surface-roots"
        case titleBranchTitles = "title-branch-titles"
        case titleMenuMatches = "title-menu-matches"
        case titleMenuTimeout = "title-menu-timeout"
        case selectionTimeout = "selection-timeout"
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
        app.unhide(); app.activate(options: [.activateAllWindows])
        var expandedOnce = false
        while remaining(deadline) {
            guard let root = window(source) else { pause(deadline); continue }
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
                if let current = window(source), titleMenuButton(current, title: record.title, deadline: deadline) != nil {
                    return true
                }
                pause(deadline)
            }
            acceptanceLog(.titleMenuTimeout)
        }
        acceptanceLog(.selectionTimeout)
        return false
    }
    static func copyID(_ record: MiniMaxCodeConversationMetadata, _ source: MiniMaxCodeConversationUI.Source,
                       _ deadline: TimeInterval) -> String? {
        guard remaining(deadline), frontmost(source), let root = window(source),
              let more = titleMenuButton(root, title: record.title, deadline: deadline), press(more, deadline) else { return nil }
        guard let copy = waitForMenuLabel(["复制", "Copy"], source: source, deadline: deadline), press(copy, deadline),
              let copyID = waitForMenuLabel(["复制会话 ID", "Copy session ID"], source: source, deadline: deadline),
              frontmost(source), remaining(deadline) else { return nil }
        let pasteboard = NSPasteboard.general
        guard let snapshot = MiniMaxCodePasteboardSnapshot.capture(pasteboard), remaining(deadline),
              pasteboard.changeCount == snapshot.originalChangeCount, press(copyID, deadline) else { return nil }
        while remaining(deadline) {
            let producedCount = pasteboard.changeCount
            if producedCount != snapshot.originalChangeCount {
                defer { snapshot.restore(pasteboard, ifUnchangedSince: producedCount) }
                // Read only the bounded plain text produced by the explicit
                // public Copy session ID action; never log/persist clipboard.
                guard let data = pasteboard.data(forType: .string), data.count <= 512,
                      pasteboard.changeCount == producedCount,
                      let value = String(data: data, encoding: .utf8), value == record.sessionID else { return nil }
                return value
            }
            pause(deadline)
        }
        return nil
    }

    /// Public 3.1.0 title and global controls are separately nested. Locate
    /// their smallest shared group by the unique fixed IDE/terminal anchors and
    /// one exact static heading. Never accept a window/web/body scroll root.
    static func titleMenuButton(_ root: AXUIElement, title: String, deadline: TimeInterval) -> AXUIElement? {
        let visited = nodes(root, deadline)
        let choosers = visited.filter { role($0) == "AXButton" && ["选择 IDE", "Choose IDE"].contains(exactLabel($0) ?? "") }
        let terminals = visited.filter { role($0) == "AXButton" && ["打开终端", "Open terminal"].contains(exactLabel($0) ?? "") }
        guard choosers.count == 1, terminals.count == 1 else { return nil }
        var node = choosers[0]
        var topbar: AXUIElement?; var branch: [AXUIElement] = []; var heading: AXUIElement?
        for _ in 0..<8 where remaining(deadline) {
            guard let parent = value(node, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            node = unsafeDowncast(parent, to: AXUIElement.self)
            guard role(node) == "AXGroup", visited.contains(where: { CFEqual($0, node) }) else { return nil }
            let members = nodes(node, deadline, maximum: 129, depth: 8)
            guard members.count <= 128, remaining(deadline),
                  !members.contains(where: { ["AXScrollArea", "AXTextArea", "AXWebArea", "AXWindow"].contains(role($0) ?? "") }) else { return nil }
            guard members.contains(where: { CFEqual($0, terminals[0]) }) else { continue }
            let titles = members.filter { role($0) == "AXStaticText" && text($0) == title }
            acceptanceLog(.titleBranchTitles, count: titles.count, nodes: members.count, flag: remaining(deadline))
            if titles.isEmpty { continue }
            guard titles.count == 1 else { return nil }
            topbar = node; branch = members; heading = titles[0]; break
        }
        guard let topbar, let heading else { return nil }
        node = heading
        for _ in 0..<4 where remaining(deadline) {
            guard let parent = value(node, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            node = unsafeDowncast(parent, to: AXUIElement.self)
            guard branch.contains(where: { CFEqual($0, node) }), role(node) == "AXGroup" else { return nil }
            let nearby = nodes(node, deadline, maximum: 41, depth: 4)
            guard nearby.count <= 40, remaining(deadline) else { return nil }
            var buttons: [AXUIElement] = []
            for candidate in nearby where role(candidate) == "AXButton" && (exactLabel(candidate) ?? "").isEmpty && action(candidate, kAXPressAction) {
                if !buttons.contains(where: { CFEqual($0, candidate) }) { buttons.append(candidate) }
            }
            acceptanceLog(.titleMenuMatches, count: buttons.count, flag: remaining(deadline))
            if buttons.count == 1 { return buttons[0] }
            if buttons.count > 1 { return nil }
            if CFEqual(node, topbar) { break }
        }
        return nil
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

/// Clipboard bytes stay in memory. Restore only if no subsequent producer
/// changed the pasteboard; never overwrite a new user copy during navigation.
struct MiniMaxCodePasteboardSnapshot {
    let originalChangeCount: Int
    private let items: [NSPasteboardItem]
    static func capture(_ pasteboard: NSPasteboard) -> Self? {
        let count = pasteboard.changeCount
        let originals = pasteboard.pasteboardItems ?? []
        guard originals.count <= 16 else { return nil }
        var copies: [NSPasteboardItem] = []; var total = 0
        for original in originals {
            guard original.types.count <= 16 else { return nil }
            let item = NSPasteboardItem()
            for type in original.types {
                guard let data = original.data(forType: type) else { return nil }
                total += data.count
                guard total <= 1_048_576, item.setData(data, forType: type) else { return nil }
            }
            copies.append(item)
        }
        guard pasteboard.changeCount == count else { return nil }
        return Self(originalChangeCount: count, items: copies)
    }
    @discardableResult func restore(_ pasteboard: NSPasteboard, ifUnchangedSince changeCount: Int) -> Bool {
        guard pasteboard.changeCount == changeCount else { return false }
        pasteboard.clearContents()
        return items.isEmpty || pasteboard.writeObjects(items)
    }
}
