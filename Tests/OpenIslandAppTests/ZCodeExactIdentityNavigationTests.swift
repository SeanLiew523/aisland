import AppKit
import Foundation
import SQLite3
import Testing
@testable import OpenIslandApp

struct ZCodeExactIdentityNavigationTests {
    final class Fixture: @unchecked Sendable {
        let root: URL
        let index: ZCodeTaskIndex
        private let lock = NSLock()
        private var current = ZCodeConversationUI.Source(processID: 412, version: "3.14.4")
        private var selected = true
        private var copied: String? = "sess_exact"
        private var frontmost = true
        private var sameWindow = true
        private var copies = 0
        var afterCopy: (@Sendable () -> Void)?
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("zcode-exact-fixture-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            index = .init(databasePath: root.appendingPathComponent("tasks.sqlite").path)
            try execute("CREATE TABLE tasks (task_id TEXT, title TEXT, workspace_path TEXT, updated_at INTEGER, deleted INTEGER); INSERT INTO tasks VALUES ('sess_exact', 'Indexed native title', '/fixture/project', 1, 0);")
        }
        deinit { try? FileManager.default.removeItem(at: root) }
        func execute(_ sql: String) throws {
            var db: OpaquePointer?
            guard sqlite3_open(index.databasePath, &db) == SQLITE_OK, let db else { throw CocoaError(.fileReadUnknown) }
            defer { sqlite3_close(db) }
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        }
        func configure(version: String? = nil, pid: pid_t? = nil, selected: Bool? = nil,
                       copied: String? = nil, frontmost: Bool? = nil, sameWindow: Bool? = nil) {
            lock.withLock {
                if let version { current.version = version }
                if let pid { current.processID = pid }
                if let selected { self.selected = selected }
                if let copied { self.copied = copied }
                if let frontmost { self.frontmost = frontmost }
                if let sameWindow { self.sameWindow = sameWindow }
            }
        }
        var copyCount: Int { lock.withLock { copies } }
        var ui: ZCodeConversationUI {
            .init(isAccessibilityAvailable: { true }, source: { self.lock.withLock { self.current } },
                select: { record, _, _ in record.id == "sess_exact" && self.lock.withLock { self.selected } },
                copyActiveSessionID: { _, _, _ in
                    let result = self.lock.withLock { self.copies += 1; return self.copied }
                    self.afterCopy?(); return result
                }, isFrontmost: { _ in self.lock.withLock { self.frontmost } },
                isCurrentWindow: { self.lock.withLock { self.sameWindow } })
        }
        func focus() -> ZCodeConversationFocusResult {
            ZCodeConversationJumpController(taskIndex: index, ui: ui, clock: { 0 }).focus(conversationID: "sess_exact")
        }
    }

    @Test func genericHeadingDoesNotBlockExactCurrentHeaderID() throws {
        // No heading is supplied by the adapter: identity, row selection and
        // re-admission are sufficient even when the UI displays “New task”.
        let fixture = try Fixture()
        #expect(fixture.focus() == .focused)
        #expect(fixture.copyCount == 1)
    }
    @Test func wrongCurrentIDCannotValidateEvenAfterExactSidebarSelection() throws {
        let fixture = try Fixture(); fixture.configure(copied: "sess_other")
        #expect(fixture.focus() == .unavailable("active-session-id-unverified"))
    }
    @Test func unsupportedSourceVersionNeverSelectsOrCopies() throws {
        let fixture = try Fixture(); fixture.configure(version: "3.15.0")
        #expect(fixture.focus() == .unavailable("source-version-or-process-unavailable"))
        #expect(fixture.copyCount == 0)
    }
    @Test func failedRowSelectionDoesNotOpenCurrentHeaderMenu() throws {
        let fixture = try Fixture(); fixture.configure(selected: false)
        #expect(fixture.focus() == .unavailable("sidebar-conversation-miss"))
        #expect(fixture.copyCount == 0)
    }
    @Test func sourceProcessReplacementDuringCopyInvalidatesResult() throws {
        let fixture = try Fixture(); fixture.afterCopy = { [weak fixture] in fixture?.configure(pid: 413) }
        #expect(fixture.focus() == .unavailable("source-or-window-changed"))
    }
    @Test func sourceVersionChangeDuringCopyInvalidatesResult() throws {
        let fixture = try Fixture(); fixture.afterCopy = { [weak fixture] in fixture?.configure(version: "3.15.0") }
        #expect(fixture.focus() == .unavailable("source-or-window-changed"))
    }
    @Test func focusOrWindowChangeDuringCopyInvalidatesResult() throws {
        for window in [false, true] {
            let fixture = try Fixture()
            fixture.afterCopy = { [weak fixture] in fixture?.configure(frontmost: window, sameWindow: !window) }
            #expect(fixture.focus() == .unavailable("source-or-window-changed"))
        }
    }
    @Test func concurrentMetadataRenameInvalidatesCopiedID() throws {
        let fixture = try Fixture()
        fixture.afterCopy = { [weak fixture] in try? fixture?.execute("UPDATE tasks SET title='Renamed' WHERE task_id='sess_exact';") }
        #expect(fixture.focus() == .unavailable("task-index-changed"))
    }
    @Test func bothRendererRowsRequireExactFocusedSourceForEnter() {
        for classes in [["group/task-item"], ["group/task-row"]] {
            #expect(ZCodeSidebarContract.isTaskRow(classes: classes))
            #expect(ZCodeSidebarContract.permitsEnter(classes: classes, focusSettable: true, exactFocus: true, sourceFrontmost: true))
            #expect(!ZCodeSidebarContract.permitsEnter(classes: classes, focusSettable: false, exactFocus: true, sourceFrontmost: true))
            #expect(!ZCodeSidebarContract.permitsEnter(classes: classes, focusSettable: true, exactFocus: false, sourceFrontmost: true))
            #expect(!ZCodeSidebarContract.permitsEnter(classes: classes, focusSettable: true, exactFocus: true, sourceFrontmost: false))
        }
        #expect(!ZCodeSidebarContract.isTaskRow(classes: ["cursor-pointer"]))
    }
    @Test func nativePopupHeaderMenuIsAdmittedWithoutAdmittingOtherRoles() {
        // Build 57 selected the correct body but never copied the current ID:
        // its real More control was AXPopUpButton rather than AXButton.
        #expect(ZCodeSidebarContract.isHeaderMenuRole("AXPopUpButton"))
        #expect(ZCodeSidebarContract.isHeaderMenuRole("AXButton"))
        for role in [nil, "AXMenuItem", "AXStaticText", "AXGroup"] as [String?] {
            #expect(!ZCodeSidebarContract.isHeaderMenuRole(role))
        }
    }
    @Test func exactCopyLabelUsesAllNativeAttributesWithoutValueMaskingTitle() {
        #expect(ZCodeCopyMenuContract.isCopyItem(value: "", title: "Copy session ID", description: nil))
        #expect(ZCodeCopyMenuContract.isCopyItem(value: nil, title: nil, description: "复制会话 ID"))
        #expect(ZCodeCopyMenuContract.isCopyItem(value: "  复制会话 ID\n", title: nil, description: nil))
        for label in [nil, "Copy task ID", "Copy session ID…", "Copy session ID sess_fixture", "复制会话 ID 私有内容"] as [String?] {
            #expect(!ZCodeCopyMenuContract.isCopyItem(value: label, title: label, description: label))
        }
    }
    @Test func cancellationRequiresOurUniqueMenuAndUnchangedAdmittedContext() {
        #expect(ZCodeCopyMenuContract.permitsCancel(openedByNavigation: true, sameSource: true,
            sameWindow: true, sourceFrontmost: true, hasTime: true, menuCount: 1, hasCancelAction: true))
        for missingGuard in 0..<6 {
            #expect(!ZCodeCopyMenuContract.permitsCancel(openedByNavigation: missingGuard != 0,
                sameSource: missingGuard != 1, sameWindow: missingGuard != 2,
                sourceFrontmost: missingGuard != 3, hasTime: missingGuard != 4,
                menuCount: 1, hasCancelAction: missingGuard != 5))
        }
        for count in [0, 2] {
            #expect(!ZCodeCopyMenuContract.permitsCancel(openedByNavigation: true, sameSource: true,
                sameWindow: true, sourceFrontmost: true, hasTime: true, menuCount: count, hasCancelAction: true))
        }
    }
    @Test func copyDiagnosticRetainsOnlyFixedMetadataAndHashedTarget() {
        let target = "sess_private-fixture"
        var diagnostic = ZCodeCopyDiagnostic(targetHash: ZCodeNavigationDiagnostic.hash(target))
        diagnostic.stage = .item; diagnostic.reason = .itemDisabled
        diagnostic.itemRole = "Private menu content\nAXRole"
        diagnostic.headerCount = -10; diagnostic.menuCount = 99999
        diagnostic.descriptionMatches = true; diagnostic.enabled = false
        diagnostic.menuBudgetExpired = true
        let line = diagnostic.line
        #expect(line.contains("reason=copy-stage-itemDisabled"))
        #expect(line.contains("stage=item"))
        #expect(line.contains("headers=0 menus=5000"))
        #expect(line.contains("descriptionMatches=true itemRole=unavailable"))
        #expect(line.contains("enabled=false"))
        #expect(line.contains("menuBudgetExpired=true"))
        #expect(!line.contains(target)); #expect(!line.contains("Private menu content"))
        #expect(!line.contains("\n"))
    }
    @Test func exactCopiedIDAfterDeadlineCannotCountAsFocused() throws {
        final class Clock: @unchecked Sendable {
            let lock = NSLock()
            var time: TimeInterval = 0
            func read() -> TimeInterval { lock.withLock { time } }
            func expire() { lock.withLock { time = 3 } }
        }
        let fixture = try Fixture(); let clock = Clock()
        fixture.afterCopy = { clock.expire() }
        let controller = ZCodeConversationJumpController(taskIndex: fixture.index, ui: fixture.ui, clock: { clock.read() })
        #expect(controller.focus(conversationID: "sess_exact") == .unavailable("focus-timeout"))
        #expect(fixture.copyCount == 1)
    }
    @Test func duplicateOrUnselectedRowsCannotVerifyExactID() {
        #expect(!ZCodeSidebarContract.verifiesIdentity(rowCount: 2, selectedRowCount: 1, copiedID: "sess_exact", targetID: "sess_exact"))
        #expect(!ZCodeSidebarContract.verifiesIdentity(rowCount: 1, selectedRowCount: 0, copiedID: "sess_exact", targetID: "sess_exact"))
        #expect(!ZCodeSidebarContract.verifiesIdentity(rowCount: 1, selectedRowCount: 1, copiedID: "sess_other", targetID: "sess_exact"))
        #expect(!ZCodeSidebarContract.verifiesIdentity(rowCount: 1, selectedRowCount: 1, copiedID: nil, targetID: "sess_exact"))
    }
    @Test func privateFixtureClipboardRestoresExactIDAndPreservesForeignProducer() throws {
        let board = NSPasteboard(name: .init("aisland-zcode-fixture-\(UUID())"))
        defer { board.releaseGlobally() }
        board.clearContents(); board.setString("fixture-original", forType: .string)
        let snapshot = try #require(MiniMaxCodePasteboardSnapshot.capture(board))
        board.clearContents(); board.setString("sess_exact", forType: .string)
        let result = try #require(snapshot.consumeMatchingCopy(board, expectedID: "sess_exact"))
        #expect(result.restored)
        #expect(board.string(forType: .string) == "fixture-original")
        let next = try #require(MiniMaxCodePasteboardSnapshot.capture(board))
        board.clearContents(); board.setString("concurrent-fixture-copy", forType: .string)
        #expect(next.consumeMatchingCopy(board, expectedID: "sess_exact") == nil)
        #expect(board.string(forType: .string) == "concurrent-fixture-copy")
    }
}
