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
}
