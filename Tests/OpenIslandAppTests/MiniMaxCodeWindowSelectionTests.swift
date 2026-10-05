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

}
