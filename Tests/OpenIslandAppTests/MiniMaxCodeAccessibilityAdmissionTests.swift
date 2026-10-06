import Testing
@testable import OpenIslandApp

struct MiniMaxCodeAccessibilityAdmissionTests {
    @Test func coldRendererRequestsAccessibilityAndAnEnabledRendererDoesNotRepeatIt() {
        for initial in [nil, false, true] as [Bool?] {
            var enables = 0
            #expect(MiniMaxCodeAccessibilityAdmission.prepare(deadline: 3, clock: { 0 },
                isCurrent: { true }, isEnabled: { initial }, enable: { enables += 1; return true }))
            #expect(enables == (initial == true ? 0 : 1))
        }
    }
    @Test func changedSourceOrExpiredQueryNeverChangesTheRenderer() {
        var current = true, enables = 0
        var time = 0.0
        #expect(!MiniMaxCodeAccessibilityAdmission.prepare(deadline: 3, clock: { time },
            isCurrent: { current }, isEnabled: { current = false; return false },
            enable: { enables += 1; return true }))
        current = true
        #expect(!MiniMaxCodeAccessibilityAdmission.prepare(deadline: 3, clock: { time },
            isCurrent: { current }, isEnabled: { time = 3; return nil },
            enable: { enables += 1; return true }))
        #expect(enables == 0)
    }
    @Test func failedEnableOrSourceChangeDuringEnableDoesNotAdmitNavigation() {
        #expect(!MiniMaxCodeAccessibilityAdmission.prepare(deadline: 3, clock: { 0 },
            isCurrent: { true }, isEnabled: { false }, enable: { false }))
        var current = true
        #expect(!MiniMaxCodeAccessibilityAdmission.prepare(deadline: 3, clock: { 0 },
            isCurrent: { current }, isEnabled: { nil }, enable: { current = false; return true }))
    }
}
