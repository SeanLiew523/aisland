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
                guard press(header, deadline) else { return false }
                expandedOnce = true
                pause(deadline); continue
            }
            // The observed native tree exposes a draggable project containing
            // its exact header button and child task buttons. DOM classes are
            // optional in Electron AX. Never widen this search to the sidebar.
            let rows = projectRows(header, title: record.title, deadline: deadline) ?? []
            if rows.isEmpty, bool(header, kAXExpandedAttribute) == nil, !expandedOnce {
                // Some Electron AX trees omit aria-expanded. One ordinary
                // project-header press may reveal its own child rows.
                guard press(header, deadline) else { return false }
                expandedOnce = true
                pause(deadline); continue
            }
            guard rows.count == 1, press(rows[0], deadline) else { return false }
            while remaining(deadline) {
                if let current = window(source), titleMenuButton(current, title: record.title, deadline: deadline) != nil {
                    return true
                }
                pause(deadline)
            }
        }
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

    /// This source-supported topbar is distinct from sidebar/body text. The
    /// verified Chinese UI is title text, adjacent unlabeled menu button,
    /// workspace opener, IDE chooser, terminal opener, then panel toggles.
    /// English captions come from bundled 3.1.0 locale chunk 88822.
    static func titleMenuButton(_ root: AXUIElement, title: String, deadline: TimeInterval) -> AXUIElement? {
        var matches: [AXUIElement] = []
        for group in nodes(root, deadline) {
            let children = elements(group, kAXChildrenAttribute)
            guard children.count >= 5,
                  children.contains(where: { role($0) == "AXButton" && ["选择 IDE", "Choose IDE"].contains(exactLabel($0) ?? "") }),
                  children.contains(where: { role($0) == "AXButton" && ["打开终端", "Open terminal"].contains(exactLabel($0) ?? "") }) else { continue }
            for index in 0..<(children.count - 1) where role(children[index]) == "AXStaticText" {
                let candidate = children[index + 1]
                guard role(candidate) == "AXButton", (exactLabel(candidate) ?? "").isEmpty,
                      text(children[index]) == title, action(candidate, kAXPressAction) else { continue }
                if !matches.contains(where: { CFEqual($0, candidate) }) { matches.append(candidate) }
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }
    static func projectHeaders(_ root: AXUIElement, path: String, deadline: TimeInterval) -> [AXUIElement] {
        nodes(root, deadline).filter {
            role($0) == "AXButton" && (exactLabel($0) ?? "").hasSuffix(", " + path)
                && action($0, kAXPressAction)
        }
    }
    static func projectRows(_ header: AXUIElement, title: String, deadline: TimeInterval) -> [AXUIElement]? {
        guard let label = exactLabel(header) else { return nil }
        var node = header
        // Exactly the observed header/container/draggable project ancestry.
        // A larger unnamed ancestor is never accepted as a project boundary.
        for _ in 0..<3 where remaining(deadline) {
            guard let parent = value(node, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            node = unsafeDowncast(parent, to: AXUIElement.self)
            let labelOfGroup = exactLabel(node) ?? ""
            let rendererGroup = classes(node).contains("space-y-px")
            guard rendererGroup || labelOfGroup == label || labelOfGroup.hasPrefix(label + " ") else { continue }
            let members = nodes(node, deadline, maximum: 500, depth: 8)
            guard members.contains(where: { CFEqual($0, header) }) else { return nil }
            let rows = members.filter {
                role($0) == "AXButton" && !CFEqual($0, header) && exactLabel($0) == title
                    && action($0, kAXPressAction)
            }
            if !rows.isEmpty || rendererGroup { return rows }
        }
        return nil
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
        let values = elements(root, kAXWindowsAttribute)
        // Multiple source windows require an explicit discriminator; don't
        // choose the first one or open/close a source window to manufacture it.
        return values.count == 1 ? values[0] : nil
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
        ((value(element, kAXValueAttribute) as? String) ?? (value(element, kAXTitleAttribute) as? String))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
