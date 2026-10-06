import Foundation
import Testing
@testable import OpenIslandApp

struct MiniMaxCodePassiveSelectionAdmissionTests {
    @Test func pageAndWindowMustRemainTheSameAcrossBothReads() {
        var reads = 0
        func verify(_ replacement: (window: String, titleControl: String)?) -> Bool {
            reads = 0
            return MiniMaxCodePassiveSelectionAdmission.verify(deadline: 6, clock: { 1 },
                isCurrent: { true }, readSelection: {
                    reads += 1
                    return reads == 1 ? ("window", "title") : replacement
                }, equal: ==)
        }
        #expect(verify(("window", "title")) && reads == 2)
        #expect(!verify(("replacement", "title")))
        #expect(!verify(("window", "another title control")))
        #expect(!verify(nil)) // Local mode, exact title or actual window focus failed.
    }

    @Test func revokedSourceAndDeadlineStopFurtherReads() {
        var reads = 0
        var time: TimeInterval = 0
        #expect(!MiniMaxCodePassiveSelectionAdmission.verify(deadline: 6, clock: { time },
            isCurrent: { reads == 0 }, readSelection: { () -> (window: String, titleControl: String)? in
                reads += 1; return ("window", "title")
            }, equal: { $0 == $1 }))
        #expect(reads == 1)
        reads = 0
        #expect(!MiniMaxCodePassiveSelectionAdmission.verify(deadline: 6, clock: { time },
            isCurrent: { true }, readSelection: { () -> (window: String, titleControl: String)? in
                reads += 1; time = 6; return ("window", "title")
            }, equal: { $0 == $1 }))
        #expect(reads == 1)
    }
}
