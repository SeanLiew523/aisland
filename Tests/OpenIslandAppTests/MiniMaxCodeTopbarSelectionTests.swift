import Testing
@testable import OpenIslandApp

struct MiniMaxCodeTopbarSelectionTests {
    @Test func ordinaryDefaultWorkspaceUsesOnlyTheDirectTopbarPrefix() {
        #expect(MiniMaxCodeTopbarSelection.defaultWorkspaceMenuIndex(in: [.title, .menu, .controls, .other, .other, .other]) == 1)
        #expect(MiniMaxCodeTopbarSelection.defaultWorkspaceMenuIndex(in: [.other, .title, .menu, .controls]) == nil)
        #expect(MiniMaxCodeTopbarSelection.defaultWorkspaceMenuIndex(in: [.title, .other, .menu, .controls]) == nil)
        #expect(MiniMaxCodeTopbarSelection.defaultWorkspaceMenuIndex(in: [.title, .menu, .controls, .menu]) == nil)
        #expect(MiniMaxCodeTopbarSelection.defaultWorkspaceMenuIndex(in: [.title, .menu, .controls] + Array(repeating: .other, count: 6)) == nil)
    }
    @Test func chatContentDoesNotBecomeATitleBranch() {
        #expect(MiniMaxCodeTopbarSelection.menuIndex(in: [.other, .title, .menu, .controls, .other, .other]) == 2)
        #expect(MiniMaxCodeTopbarSelection.menuIndex(in: [.other, .other, .menu, .controls, .other]) == nil)
    }
    @Test func ambiguousControlsTitleOrMenuRejectSelection() {
        #expect(MiniMaxCodeTopbarSelection.menuIndex(in: [.title, .menu, .controls, .controls]) == nil)
        #expect(MiniMaxCodeTopbarSelection.menuIndex(in: [.title, .menu, .controls, .title]) == nil)
        #expect(MiniMaxCodeTopbarSelection.menuIndex(in: [.title, .menu, .controls, .menu]) == nil)
    }
    @Test func changedSiblingOrderIsNotGuessed() {
        #expect(MiniMaxCodeTopbarSelection.menuIndex(in: [.title, .other, .menu, .controls]) == nil)
        #expect(MiniMaxCodeTopbarSelection.menuIndex(in: [.menu, .title, .controls]) == nil)
        #expect(MiniMaxCodeTopbarSelection.menuIndex(in: [.controls, .title, .menu]) == nil)
    }
    @Test func emptyOrUnboundedChildrenRejectSelection() {
        #expect(MiniMaxCodeTopbarSelection.menuIndex(in: []) == nil)
        #expect(MiniMaxCodeTopbarSelection.menuIndex(in: [.title, .menu, .controls] + Array(repeating: .other, count: 6)) == nil)
    }
}
