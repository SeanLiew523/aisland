import Testing
@testable import OpenIslandApp

struct MiniMaxCodeTopbarSelectionTests {
    @Test func omittedLayoutGroupsRemainBoundedToTheExactTerminalBranch() {
        let children = [10: [1], 20: [10], 30: [2, 3, 20, 99]]
        let parents = [1: 10, 10: 20, 20: 30]
        func panel(named: Set<Int> = [], hasTime: Bool = true) -> Int? {
            MiniMaxCodeTopbarSelection.layoutParent(of: 1, parent: { parents[$0] },
                isUnnamedGroup: { children[$0] != nil && !named.contains($0) },
                children: { children[$0] ?? [] }, equal: ==, hasTime: { hasTime })
        }
        #expect(panel() == 30)
        #expect(panel(named: [20]) == nil)
        #expect(panel(hasTime: false) == nil)
        let leaf = MiniMaxCodeTopbarSelection.leaf(of: 20, isGroup: { children[$0] != nil },
            isUnnamed: { _ in true }, children: { children[$0] ?? [] }, hasTime: { true })
        #expect(leaf == 1)
        #expect(MiniMaxCodeTopbarSelection.leaf(of: 30, isGroup: { children[$0] != nil },
            isUnnamed: { _ in true }, children: { children[$0] ?? [] }, hasTime: { true }) == nil)
        #expect(MiniMaxCodeTopbarSelection.layoutParent(of: 1, parent: { _ in 1 },
            isUnnamedGroup: { _ in true }, children: { [$0] }, equal: ==, hasTime: { true }) == nil)
    }
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
