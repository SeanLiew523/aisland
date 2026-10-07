import AppKit
import Testing
@testable import OpenIslandApp

struct MiniMaxCodeCopyLabelGeometryTests {
    @Test func aTransientHitMustSettleBeforeItCanBeClicked() {
        var geometry = MiniMaxCodeCopyLabelGeometry()
        let initial = CGRect(x: 10, y: 20, width: 100, height: 20)
        let final = initial.offsetBy(dx: 0, dy: 25)
        let trace = [(initial, 0), (initial, 0.04), (final, 0.1), (final, 0.2),
                     (final, 0.3), (final.offsetBy(dx: 1, dy: 0), 0.31)]
        let admitted = trace.map { geometry.observe($0.0, at: $0.1) }
        #expect(admitted == [false, false, false, false, true, false])
    }
    @Test func invalidGeometryRevokesPreviouslyStableBounds() {
        var geometry = MiniMaxCodeCopyLabelGeometry()
        let valid = CGRect(x: 10, y: 20, width: 100, height: 20)
        let trace = [(valid, 0.0), (valid, 1), (.zero, 2), (valid, 3), (valid, 4)]
        let admitted = trace.map { geometry.observe($0.0, at: $0.1) }
        #expect(admitted == [false, true, false, false, true])
    }
    @Test func detachedTextUsesOnlyItsVisiblePaddingZeroMenuItem() {
        let window = CGRect(x: 100, y: 200, width: 1000, height: 800)
        let item = CGRect(x: 500, y: 400, width: 200, height: 30)
        let label = CGRect(x: 550, y: 405, width: 100, height: 20)
        #expect(MiniMaxCodeCopyLabelGeometry.clickBounds(label: label, item: item, window: window) == label)
        #expect(MiniMaxCodeCopyLabelGeometry.clickBounds(label: label.offsetBy(dx: -550, dy: -405),
            item: item, window: window) == item)
        #expect(MiniMaxCodeCopyLabelGeometry.clickBounds(label: nil, item: item, window: window) == item)
        #expect(MiniMaxCodeCopyLabelGeometry.clickBounds(label: label, item: .zero, window: window) == nil)
        #expect(MiniMaxCodeCopyLabelGeometry.clickBounds(label: label, item: item.offsetBy(dx: -500, dy: -400),
            window: window) == nil)
    }
}
