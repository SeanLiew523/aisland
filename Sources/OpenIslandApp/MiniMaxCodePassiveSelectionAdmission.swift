import Foundation

/// Both reads must independently admit the local mode, exact title and actual
/// source focus. Identity is the ID-bound, globally unique metadata mapping;
/// this is not an independent native-ID read from the renderer.
enum MiniMaxCodePassiveSelectionAdmission {
    static func verify<Element>(deadline: TimeInterval, clock: () -> TimeInterval,
        isCurrent: () -> Bool, readSelection: () -> (window: Element, titleControl: Element)?,
        equal: (Element, Element) -> Bool) -> Bool {
        guard clock() < deadline, isCurrent(), let first = readSelection(),
              clock() < deadline, isCurrent(), let second = readSelection(),
              equal(first.window, second.window), equal(first.titleControl, second.titleControl),
              clock() < deadline, isCurrent(), clock() < deadline else { return false }
        return true
    }
}
