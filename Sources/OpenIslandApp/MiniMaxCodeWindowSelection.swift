/// Desktop 3.1.0 exposes a standard main window and may also expose auxiliary
/// dialogs. A matching title alone is insufficient; login/onboarding can use
/// the same public title. Project and native-session checks follow selection.
enum MiniMaxCodeWindowSelection {
    struct Attributes {
        var role: String?
        var subrole: String?
        var title: String?
        var isMain: Bool?
        var isMinimized: Bool?
    }

    static func mainIndex(in windows: [Attributes]) -> Int? {
        guard !windows.isEmpty, windows.count <= 8 else { return nil }
        let candidates = windows.indices.filter {
            windows[$0].role == "AXWindow"
                && windows[$0].subrole == "AXStandardWindow"
                && windows[$0].title == "MiniMax Code"
        }
        guard candidates.count == 1, let index = candidates.first,
              windows[index].isMain == true, windows[index].isMinimized == false else { return nil }
        return index
    }
}
