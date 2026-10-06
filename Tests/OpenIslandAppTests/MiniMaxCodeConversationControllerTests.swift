import AppKit
import Foundation
import SQLite3
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

struct MiniMaxCodeConversationControllerTests {
    @Test func defaultWorkspaceRequiresPassiveSelectionAndForeground() throws {
        let fixture = try ControllerFixture(); defer { fixture.dispose() }
        try fixture.exec("UPDATE local_runtime_sessions SET is_default_workspace=1, session_kind='conversation', project_id=5")
        #expect(fixture.controller.focus(target: fixture.target) == .focused)
        fixture.selectionVerified = false
        #expect(fixture.controller.focus(target: fixture.target) == .unavailable("active-session-selection-unverified"))
        fixture.selectionVerified = true; fixture.frontmost = false
        #expect(fixture.controller.focus(target: fixture.target) == .unavailable("app-not-frontmost"))
    }
    @Test func reviewedPatchUpgradeRetainsConversationAndPassiveSelectionGate() throws {
        let fixture = try ControllerFixture(); defer { fixture.dispose() }
        fixture.sourceVersion = "3.1.1"
        #expect(fixture.controller.focus(target: fixture.target) == .focused)
        var target = fixture.target; target.runtimeSourceVersion = "3.1.1"
        #expect(fixture.controller.focus(target: target) == .focused)
        fixture.selectionVerified = false
        #expect(fixture.controller.focus(target: target) == .unavailable("active-session-selection-unverified"))
    }

    @Test func initialActivationWaitsForForegroundWithinOriginalBudget() {
        var time: TimeInterval = 0
        var pauses = 0
        let admitted = MiniMaxCodeActivationAdmission.wait(deadline: 3, clock: { time },
            available: { true }, frontmost: { pauses == 4 },
            pause: { _ in pauses += 1; time += 0.04 })
        #expect(admitted && pauses == 4 && time < 3)
        pauses = 0
        #expect(MiniMaxCodeActivationAdmission.wait(deadline: 3, clock: { time },
            available: { true }, frontmost: { true }, pause: { _ in pauses += 1 }))
        #expect(pauses == 0)
    }

    @Test func activationTimeoutAndRevokedAccessNeverAdmitVerification() {
        var time: TimeInterval = 0
        #expect(!MiniMaxCodeActivationAdmission.wait(deadline: 0.12, clock: { time },
            available: { true }, frontmost: { false }, pause: { _ in time += 0.04 }))
        var pauses = 0
        time = 0
        #expect(!MiniMaxCodeActivationAdmission.wait(deadline: 3, clock: { time },
            available: { pauses == 0 }, frontmost: { false },
            pause: { _ in pauses += 1; time += 0.04 }))
        #expect(pauses == 1)
        time = 3
        #expect(!MiniMaxCodeActivationAdmission.wait(deadline: 3, clock: { time },
            available: { true }, frontmost: { true }, pause: { _ in pauses += 1 }))
        #expect(pauses == 1)
    }

    @Test func accessibilityUnavailableStopsBeforeSourceOrUIActions() throws {
        let fixture = try ControllerFixture(); defer { fixture.dispose() }
        fixture.accessibilityAvailable = false
        #expect(fixture.controller.focus(target: fixture.target) == .unavailable("accessibility-unavailable"))
        #expect(fixture.sourceCount == 0)
        #expect(fixture.selectCount == 0 && fixture.activationCount == 0 && fixture.verificationCount == 0)
    }

    @Test func accessibilityRevokedDuringSelectionStopsBeforeVerification() throws {
        let fixture = try ControllerFixture(); defer { fixture.dispose() }
        fixture.onSelect = { fixture.accessibilityAvailable = false }
        #expect(fixture.controller.focus(target: fixture.target) == .unavailable("accessibility-unavailable"))
        #expect(fixture.verificationCount == 0)
        fixture.accessibilityAvailable = true; fixture.selected = false
        #expect(fixture.controller.focus(target: fixture.target) == .unavailable("accessibility-unavailable"))
    }

    @Test func exactSessionIdentityAndForegroundAreBothRequired() throws {
        let fixture = try ControllerFixture(); defer { fixture.dispose() }
        #expect(fixture.controller.focus(target: fixture.target) == .focused)
        #expect(fixture.selectCount == 1 && fixture.verificationCount == 1)
        fixture.selectionVerified = false
        #expect(fixture.controller.focus(target: fixture.target) == .unavailable("active-session-selection-unverified"))
        fixture.selectionVerified = true; fixture.frontmost = false
        #expect(fixture.controller.focus(target: fixture.target) == .unavailable("app-not-frontmost"))
    }

    @Test func activationAloneAndUnverifiedPageAreNeverSuccess() throws {
        let fixture = try ControllerFixture(); defer { fixture.dispose() }
        fixture.selected = false
        #expect(fixture.controller.focus(target: fixture.target) == .unavailable("sidebar-conversation-unavailable"))
        #expect(fixture.verificationCount == 0)
        fixture.selected = true; fixture.selectionVerified = false
        #expect(fixture.controller.focus(target: fixture.target) == .unavailable("active-session-selection-unverified"))
    }

    @Test func admissionAndActualRunningSourceMustAgree() throws {
        let fixture = try ControllerFixture(); defer { fixture.dispose() }
        var target = fixture.target; target.runtimeMetadataDatabasePath = nil
        #expect(fixture.controller.focus(target: target) == .unavailable("runtime-metadata-unavailable"))
        target = fixture.target; target.runtimeSourceVersion = "3.2.0"
        #expect(fixture.controller.focus(target: target) == .unavailable("runtime-metadata-unavailable"))
        target = fixture.target; target.terminalApp = "MiniMax Code CLI"
        #expect(fixture.controller.focus(target: target) == .unavailable("runtime-metadata-unavailable"))
        fixture.sourceVersion = "3.2.0"
        #expect(fixture.controller.focus(target: fixture.target) == .unavailable("source-version-or-process-unavailable"))
        #expect(fixture.selectCount == 0)
    }

    @Test func staleMetadataDuplicateTitleAndReplacedProcessFailClosed() throws {
        let fixture = try ControllerFixture(); defer { fixture.dispose() }
        fixture.onVerify = { try? fixture.exec("UPDATE local_runtime_sessions SET title='renamed'") }
        #expect(fixture.controller.focus(target: fixture.target) == .unavailable("session-metadata-changed"))
        fixture.onVerify = nil
        try fixture.exec("INSERT INTO local_runtime_sessions SELECT 'second',title,workspace_dir,project_workspace_dir,68,visibility,archived,columnar_version,is_default_workspace,parent_session_id,session_kind FROM local_runtime_sessions")
        #expect(fixture.controller.focus(target: fixture.target) == .unavailable("ambiguous-session-title"))
        try fixture.exec("DELETE FROM local_runtime_sessions WHERE session_id='second'")
        fixture.onVerify = { fixture.processID = 99 }
        #expect(fixture.controller.focus(target: fixture.target) == .unavailable("app-not-frontmost"))
    }

    @Test func timeoutsPreventFurtherSideEffects() throws {
        let fixture = try ControllerFixture(); defer { fixture.dispose() }
        #expect(MiniMaxCodeConversationController(ui: fixture.ui, timeout: 0).focus(target: fixture.target) == .unavailable("focus-timeout"))
        #expect(fixture.selectCount == 0)
        fixture.onSelect = { fixture.time = 4 }
        #expect(MiniMaxCodeConversationController(ui: fixture.ui, clock: { fixture.time }, timeout: 3).focus(target: fixture.target) == .unavailable("focus-timeout"))
        #expect(fixture.verificationCount == 0)
    }

    @Test func coldSelectionHasTimeForPassiveVerificationButCannotExtendItsDeadline() throws {
        let fixture = try ControllerFixture(); defer { fixture.dispose() }
        fixture.onSelect = { fixture.time = 3.4 }
        let controller = MiniMaxCodeConversationController(ui: fixture.ui, clock: { fixture.time })
        #expect(controller.focus(target: fixture.target) == .focused)
        #expect(fixture.verificationCount == 1)
        fixture.time = 0
        fixture.onVerify = { fixture.time = 6 }
        #expect(controller.focus(target: fixture.target) == .unavailable("focus-timeout"))
    }

    @Test func clipboardRestoresAllTypesAndPreservesAConcurrentProducer() throws {
        let board = NSPasteboard(name: .init("aisland-minimax-nav-test-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        let item = NSPasteboardItem()
        let custom = NSPasteboard.PasteboardType("org.aisland.synthetic")
        #expect(item.setString("synthetic original", forType: .string))
        #expect(item.setData(Data([0,1,2,255]), forType: custom))
        board.clearContents(); #expect(board.writeObjects([item]))
        let snapshot = try #require(MiniMaxCodePasteboardSnapshot.capture(board))
        board.clearContents(); #expect(board.setString("observed", forType: .string))
        let produced = board.changeCount
        #expect(snapshot.restore(board, ifUnchangedSince: produced))
        #expect(board.string(forType: .string) == "synthetic original")
        #expect(board.data(forType: custom) == Data([0,1,2,255]))
        let next = try #require(MiniMaxCodePasteboardSnapshot.capture(board))
        board.clearContents(); board.setString("copy-session-id", forType: .string)
        let beforeUserCopy = board.changeCount
        board.clearContents(); board.setString("synthetic concurrent user copy", forType: .string)
        #expect(!next.restore(board, ifUnchangedSince: beforeUserCopy))
        #expect(board.string(forType: .string) == "synthetic concurrent user copy")
    }

    @Test func clipboardCaptureHasABoundedSizeAndSupportsAnEmptyBoard() throws {
        let board = NSPasteboard(name: .init("aisland-minimax-nav-test-" + UUID().uuidString))
        defer { board.releaseGlobally() }; board.clearContents()
        let empty = try #require(MiniMaxCodePasteboardSnapshot.capture(board))
        board.setString("observed", forType: .string)
        #expect(empty.restore(board, ifUnchangedSince: board.changeCount))
        #expect((board.pasteboardItems ?? []).isEmpty)
        board.setData(Data(repeating: 0, count: 1_048_577), forType: .init("org.aisland.synthetic"))
        #expect(MiniMaxCodePasteboardSnapshot.capture(board) == nil)
    }
}

// Each test owns this fixture; controller callbacks run synchronously. The
// unchecked annotation permits injected @Sendable callbacks without globals.
private final class ControllerFixture: @unchecked Sendable {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("minimax-controller-" + UUID().uuidString)
    var db: OpaquePointer?
    var selectionVerified = true
    var selected = true
    var frontmost = true
    var accessibilityAvailable = true
    var sourceVersion = "3.1.0"
    var processID: pid_t = 10
    var time: TimeInterval = 0
    var selectCount = 0
    var sourceCount = 0
    var activationCount = 0
    var verificationCount = 0
    var onSelect: (@Sendable () -> Void)?
    var onVerify: (@Sendable () -> Void)?
    var path: String { directory.appendingPathComponent("v2/sqlite/runtime-state.sqlite").path }
    var target: JumpTarget { .init(terminalApp: "MiniMax Code.app", workspaceName: "Synthetic workspace", paneTitle: "Synthetic task", appConversationID: "observed", runtimeMetadataDatabasePath: path, runtimeSourceVersion: "3.1.0") }
    var ui: MiniMaxCodeConversationUI {
        .init(isAccessibilityAvailable: { self.accessibilityAvailable },
              source: { self.sourceCount += 1; return .init(bundleIdentifier: "com.minimax.agent", version: self.sourceVersion, processID: self.processID) },
              select: { _, _, _ in self.selectCount += 1; self.activationCount += 1; self.onSelect?(); return self.selected },
              verifyActiveSelection: { _, _, _ in self.verificationCount += 1; self.onVerify?(); return self.selectionVerified },
              isFrontmost: { _ in self.frontmost })
    }
    var controller: MiniMaxCodeConversationController { .init(ui: ui) }
    init() throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw FixtureError.sqlite }
        try exec("""
        CREATE TABLE local_runtime_sessions(session_id TEXT PRIMARY KEY,title TEXT,workspace_dir TEXT,project_workspace_dir TEXT,
        project_id INTEGER,visibility TEXT,archived INTEGER,columnar_version INTEGER,is_default_workspace INTEGER,parent_session_id TEXT,session_kind TEXT);
        INSERT INTO local_runtime_sessions VALUES('observed','Synthetic task','/tmp/synthetic-workspace','/tmp/synthetic-workspace',67,'visible',0,3,0,NULL,'task');
        """)
    }
    func exec(_ sql: String) throws { guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw FixtureError.sqlite } }
    func dispose() { sqlite3_close(db); db = nil; try? FileManager.default.removeItem(at: directory) }
    enum FixtureError: Error { case sqlite }
}
