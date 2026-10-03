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
}
