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
}
