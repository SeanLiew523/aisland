import Foundation

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

    static func waitForMainWindow<Element>(deadline: TimeInterval, clock: () -> TimeInterval,
        isCurrent: () -> Bool, readWindow: () -> Element?, pause: (TimeInterval) -> Void) -> Element? {
        while clock() < deadline {
            guard isCurrent() else { return nil }
            if let window = readWindow() { return clock() < deadline && isCurrent() ? window : nil }
            pause(deadline)
        }
        return nil
    }

    static func mainIndex(in windows: [Attributes]) -> Int? {
        guard let index = standardIndex(in: windows),
              windows[index].isMain == true, windows[index].isMinimized == false else { return nil }
        return index
    }

    /// A minimized window can lose AXMain while its application stays frontmost.
    /// This candidate permits restoration only; navigation still requires mainIndex.
    static func minimizedIndex(in windows: [Attributes]) -> Int? {
        guard let index = standardIndex(in: windows), windows[index].isMinimized == true else { return nil }
        return index
    }

    private static func standardIndex(in windows: [Attributes]) -> Int? {
        guard !windows.isEmpty, windows.count <= 8 else { return nil }
        let candidates = windows.indices.filter {
            windows[$0].role == "AXWindow"
                && windows[$0].subrole == "AXStandardWindow"
                && windows[$0].title == "MiniMax Code"
        }
        guard candidates.count == 1, let index = candidates.first else { return nil }
        return index
    }
}

/// Restore one exact minimized source window before admitting navigation. A
/// successful setter is not proof: await the same strict main window afterward.
enum MiniMaxCodeWindowRestoration {
    struct Result<Element> {
        var window: Element?
        var attempted = false
        var succeeded = false
    }
    static func wait<Element>(deadline: TimeInterval, clock: () -> TimeInterval,
        isCurrent: () -> Bool, readMainWindow: () -> Element?, readMinimizedWindow: () -> Element?,
        canRestore: (Element) -> Bool, restore: (Element) -> Bool,
        equal: (Element, Element) -> Bool, pause: (TimeInterval) -> Void) -> Result<Element> {
        var result = Result<Element>()
        var restoredWindow: Element?
        while clock() < deadline {
            guard isCurrent() else { return result }
            if let window = readMainWindow() {
                guard clock() < deadline, isCurrent(),
                      restoredWindow.map({ equal(window, $0) }) ?? true else { return result }
                result.window = window
                return result
            }
            guard clock() < deadline, isCurrent() else { return result }
            if !result.attempted, let candidate = readMinimizedWindow() {
                guard clock() < deadline, isCurrent(), canRestore(candidate),
                      clock() < deadline, isCurrent(), let current = readMinimizedWindow(),
                      equal(candidate, current), clock() < deadline, isCurrent() else { return result }
                result.attempted = true
                result.succeeded = restore(candidate)
                guard result.succeeded, clock() < deadline, isCurrent() else { return result }
                restoredWindow = candidate
            }
            pause(deadline)
        }
        return result
    }
}
