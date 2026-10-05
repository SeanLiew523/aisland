import Foundation
import Testing
@testable import OpenIslandApp

struct MiniMaxCodeWindowSelectionTests {
    private var main: MiniMaxCodeWindowSelection.Attributes {
        .init(role: "AXWindow", subrole: "AXStandardWindow", title: "MiniMax Code",
              isMain: true, isMinimized: false)
    }
    @Test func auxiliaryDialogDoesNotBlockUniqueMainWindow() {
        let dialog = MiniMaxCodeWindowSelection.Attributes(role: "AXWindow", subrole: "AXDialog",
            title: "Auxiliary", isMain: false, isMinimized: false)
        #expect(MiniMaxCodeWindowSelection.mainIndex(in: [dialog, main]) == 1)
        #expect(MiniMaxCodeWindowSelection.mainIndex(in: [main, dialog]) == 0)
    }
    @Test func duplicateStandardTitlesRemainAmbiguous() {
        var other = main; other.isMain = false
        #expect(MiniMaxCodeWindowSelection.mainIndex(in: [main, other]) == nil)
        #expect(MiniMaxCodeWindowSelection.mainIndex(in: [main, main]) == nil)
    }
    @Test func missingOrMinimizedMainWindowIsNotAdmitted() {
        for state in [nil, false] as [Bool?] {
            var window = main; window.isMain = state
            #expect(MiniMaxCodeWindowSelection.mainIndex(in: [window]) == nil)
        }
        for state in [nil, true] as [Bool?] {
            var window = main; window.isMinimized = state
            #expect(MiniMaxCodeWindowSelection.mainIndex(in: [window]) == nil)
        }
    }
    @Test func wrongTitleRoleAndUnboundedWindowListFailClosed() {
        var window = main; window.title = "Quick Input"
        #expect(MiniMaxCodeWindowSelection.mainIndex(in: [window]) == nil)
        window = main; window.subrole = "AXDialog"
        #expect(MiniMaxCodeWindowSelection.mainIndex(in: [window]) == nil)
        window = main; window.role = nil
        #expect(MiniMaxCodeWindowSelection.mainIndex(in: [window]) == nil)
        #expect(MiniMaxCodeWindowSelection.mainIndex(in: []) == nil)
        #expect(MiniMaxCodeWindowSelection.mainIndex(in: Array(repeating: main, count: 9)) == nil)
    }
    @Test func frontmostButUnfocusedWindowIsRaisedExactlyOnceBeforeAdmission() {
        var time: TimeInterval = 0
        var raises = 0; var pauses = 0
        let result = MiniMaxCodeWindowFocusAdmission.wait(deadline: 3, clock: { time }, isCurrent: { true },
            isFocused: { pauses == 3 }, supportsRaise: { true }, raise: { raises += 1; return true },
            pause: { _ in pauses += 1; time += 0.04 })
        #expect(result == .init(raiseAttempted: true, raiseSucceeded: true, focused: true))
        #expect(raises == 1 && pauses == 3 && time < 3)
    }
    @Test func alreadyFocusedWindowNeverRaisesOrWaits() {
        var raises = 0; var pauses = 0
        let result = MiniMaxCodeWindowFocusAdmission.wait(deadline: 3, clock: { 0 }, isCurrent: { true },
            isFocused: { true }, supportsRaise: { true }, raise: { raises += 1; return true },
            pause: { _ in pauses += 1 })
        #expect(result.focused && !result.raiseAttempted && raises == 0 && pauses == 0)
    }
    @Test func sourceWindowOrForegroundChangeCancelsWithoutReactivation() {
        var time: TimeInterval = 0
        var raises = 0; var pauses = 0
        let result = MiniMaxCodeWindowFocusAdmission.wait(deadline: 3, clock: { time },
            isCurrent: { pauses == 0 }, isFocused: { false }, supportsRaise: { true },
            raise: { raises += 1; return true }, pause: { _ in pauses += 1; time += 0.04 })
        #expect(!result.focused && raises == 1 && pauses == 1)
        var current = true
        raises = 0
        let changedDuringCapabilityQuery = MiniMaxCodeWindowFocusAdmission.wait(deadline: 3, clock: { 0 },
            isCurrent: { current }, isFocused: { false }, supportsRaise: { current = false; return true },
            raise: { raises += 1; return true }, pause: { _ in })
        #expect(!changedDuringCapabilityQuery.focused && !changedDuringCapabilityQuery.raiseAttempted && raises == 0)
    }
    @Test func timeoutUnsupportedAndFailedRaiseNeverAdmitOrRepeat() {
        var time: TimeInterval = 0
        var raises = 0
        let timedOut = MiniMaxCodeWindowFocusAdmission.wait(deadline: 0.12, clock: { time }, isCurrent: { true },
            isFocused: { false }, supportsRaise: { true }, raise: { raises += 1; return true },
            pause: { _ in time += 0.04 })
        #expect(!timedOut.focused && raises == 1 && time >= 0.12)
        raises = 0
        let expired = MiniMaxCodeWindowFocusAdmission.wait(deadline: 0, clock: { 0 }, isCurrent: { true },
            isFocused: { false }, supportsRaise: { true }, raise: { raises += 1; return true }, pause: { _ in })
        #expect(!expired.focused && raises == 0)
        let unsupported = MiniMaxCodeWindowFocusAdmission.wait(deadline: 3, clock: { 0 }, isCurrent: { true },
            isFocused: { false }, supportsRaise: { false }, raise: { raises += 1; return true }, pause: { _ in })
        #expect(!unsupported.focused && !unsupported.raiseAttempted && raises == 0)
        let failed = MiniMaxCodeWindowFocusAdmission.wait(deadline: 3, clock: { 0 }, isCurrent: { true },
            isFocused: { false }, supportsRaise: { true }, raise: { raises += 1; return false }, pause: { _ in })
        #expect(!failed.focused && failed.raiseAttempted && !failed.raiseSucceeded && raises == 1)
    }

    @Test func actualFocusedChildIsRequiredAndStableWithinAdmittedWindow() {
        var focused: Int? = 10
        var reads = 0
        func read() -> Int? { reads += 1; return focused }
        #expect(MiniMaxCodeFocusedElementAdmission.verify(hasTime: { true }, isCurrent: { true },
            readFocus: read, belongsToWindow: { $0 == 10 }, equal: { (first: Int, second: Int) in first == second }))
        #expect(reads == 2)
        focused = nil; reads = 0
        #expect(!MiniMaxCodeFocusedElementAdmission.verify(hasTime: { true }, isCurrent: { true },
            readFocus: read, belongsToWindow: { _ in true }, equal: { (first: Int, second: Int) in first == second }))
        #expect(reads == 1) // Main/frontmost/Raise cannot replace missing focus.
        focused = 11; reads = 0
        #expect(!MiniMaxCodeFocusedElementAdmission.verify(hasTime: { true }, isCurrent: { true },
            readFocus: read, belongsToWindow: { $0 == 10 }, equal: { (first: Int, second: Int) in first == second }))
        #expect(reads == 1) // Focus in another window/process is not admitted.
    }
    @Test func focusChangesAndExpiredQueriesCancelBeforeAdmission() {
        var reads = 0
        #expect(!MiniMaxCodeFocusedElementAdmission.verify(hasTime: { true }, isCurrent: { true },
            readFocus: { reads += 1; return reads }, belongsToWindow: { _ in true }, equal: { (first: Int, second: Int) in first == second }))
        #expect(reads == 2)
        var current = true
        reads = 0
        #expect(!MiniMaxCodeFocusedElementAdmission.verify(hasTime: { true }, isCurrent: { current },
            readFocus: { reads += 1; return 10 as Int }, belongsToWindow: { _ in current = false; return true }, equal: { (first: Int, second: Int) in first == second }))
        #expect(reads == 1)
        var time: TimeInterval = 0
        #expect(!MiniMaxCodeFocusedElementAdmission.verify(hasTime: { time < 3 }, isCurrent: { true },
            readFocus: { 10 as Int }, belongsToWindow: { _ in time = 3; return true }, equal: { (first: Int, second: Int) in first == second }))
    }

    @Test func stableFocusMovedToAnotherWindowIsRejectedOnRecheck() {
        var membershipQueries = 0
        #expect(!MiniMaxCodeFocusedElementAdmission.verify(hasTime: { true }, isCurrent: { true },
            readFocus: { 10 as Int }, belongsToWindow: { _ in membershipQueries += 1; return membershipQueries == 1 }, equal: { (first: Int, second: Int) in first == second }))
        #expect(membershipQueries == 2)
    }

    @Test func focusedWindowShortcutAndBoundedParentsUseExactIdentity() {
        func proof(window: Int?, parents: [Int: Int] = [:], windows: Set<Int> = [99], time: Bool = true)
            -> MiniMaxCodeCopyDiagnostic.WindowFocusProof {
            MiniMaxCodeFocusedElementAdmission.windowProof(element: 1, admittedWindow: 99,
                containingWindow: { _ in window }, parent: { parents[$0] }, isWindow: { windows.contains($0) },
                equal: { (first: Int, second: Int) in first == second }, hasTime: { time })
        }
        #expect(proof(window: 99) == .elementWindow)
        #expect(proof(window: 98, parents: [1: 99]) == .differentWindow) // Never override a conflicting shortcut.
        #expect(proof(window: nil, parents: [1: 2, 2: 99]) == .elementAncestry)
        #expect(proof(window: nil, parents: [1: 98, 98: 99], windows: [98, 99]) == .differentWindow)
        #expect(proof(window: nil, parents: [1: 2, 2: 1]) == .ancestryUnavailable)
        #expect(proof(window: nil) == .ancestryUnavailable)
        #expect(proof(window: 99, time: false) == .ancestryUnavailable)
        #expect(MiniMaxCodeFocusedElementAdmission.windowProof(element: 99, admittedWindow: 99,
            containingWindow: { _ in nil }, parent: { _ in nil }, isWindow: { _ in true }, equal: { (first: Int, second: Int) in first == second },
            hasTime: { true }) == .windowSelf)
    }
    @Test func ancestryBoundAndExpiredParentReadsRemainUnavailable() {
        let inside = MiniMaxCodeFocusedElementAdmission.windowProof(element: 0, admittedWindow: 16,
            containingWindow: { _ in nil }, parent: { $0 + 1 }, isWindow: { $0 == 16 }, equal: { (first: Int, second: Int) in first == second }, hasTime: { true })
        #expect(inside == .elementAncestry)
        let outside = MiniMaxCodeFocusedElementAdmission.windowProof(element: 0, admittedWindow: 17,
            containingWindow: { _ in nil }, parent: { $0 + 1 }, isWindow: { $0 == 17 }, equal: { (first: Int, second: Int) in first == second }, hasTime: { true })
        #expect(outside == .ancestryUnavailable)
        var remaining = true
        let expired = MiniMaxCodeFocusedElementAdmission.windowProof(element: 0, admittedWindow: 2,
            containingWindow: { _ in nil }, parent: { value in remaining = false; return value + 1 },
            isWindow: { $0 == 2 }, equal: { (first: Int, second: Int) in first == second }, hasTime: { remaining })
        #expect(expired == .ancestryUnavailable)
    }

}
