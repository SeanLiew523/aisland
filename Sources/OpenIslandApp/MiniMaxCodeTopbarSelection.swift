/// The observed 3.1.0 AX tree exposes three adjacent direct branches:
/// a one-text title group, its native menu button, and the IDE/terminal group.
/// Body descendants are never inputs to this policy.
enum MiniMaxCodeTopbarSelection {
    enum Branch {
        case title, menu, controls, other
    }
    static func menuIndex(in branches: [Branch]) -> Int? {
        guard branches.count <= 8 else { return nil }
        let controls = branches.indices.filter { branches[$0] == .controls }
        guard controls.count == 1, let index = controls.first, index >= 2,
              branches[index - 2] == .title, branches[index - 1] == .menu,
              branches.filter({ $0 == .title }).count == 1,
              branches.filter({ $0 == .menu }).count == 1 else { return nil }
        return index - 1
    }
    static func layoutParent<Element>(of item: Element, parent: (Element) -> Element?,
        isUnnamedGroup: (Element) -> Bool, children: (Element) -> [Element],
        equal: (Element, Element) -> Bool, hasTime: () -> Bool) -> Element? {
        var branch = item
        for _ in 0..<4 {
            guard hasTime(), let candidate = parent(branch), isUnnamedGroup(candidate) else { return nil }
            let siblings = children(candidate)
            if siblings.count == 1, equal(siblings[0], branch) { branch = candidate; continue }
            return candidate
        }
        return nil
    }
    static func leaf<Element>(of item: Element, isGroup: (Element) -> Bool,
        isUnnamed: (Element) -> Bool, children: (Element) -> [Element], hasTime: () -> Bool) -> Element? {
        var leaf = item
        for _ in 0..<4 {
            guard hasTime() else { return nil }
            guard isGroup(leaf) else { return leaf }
            guard isUnnamed(leaf) else { return nil }
            let members = children(leaf)
            guard members.count == 1 else { return nil }
            leaf = members[0]
        }
        return hasTime() && !isGroup(leaf) ? leaf : nil
    }

}
