import Testing
@testable import OpenIslandApp

struct MiniMaxCodeAccessibilityAdmissionTests {
    @Test func coldRendererRequestsAccessibilityAndAnEnabledRendererDoesNotRepeatIt() {
        for initial in [nil, false, true] as [Bool?] {
            var enables = 0, pauses = 0
            var time = 0.0
            #expect(MiniMaxCodeAccessibilityAdmission.prepare(deadline: 3, clock: { time },
                isCurrent: { true }, isEnabled: { time >= 2 ? true : initial },
                enable: { enables += 1; return true }, pause: { _ in time += 0.04; pauses += 1 }))
            #expect(enables == (initial == true ? 0 : 1))
            #expect(initial == true ? pauses == 0 : time >= 2.1)
        }
    }
    @Test func changedSourceOrExpiredQueryNeverChangesTheRenderer() {
        var current = true, enables = 0
        var time = 0.0
        #expect(!MiniMaxCodeAccessibilityAdmission.prepare(deadline: 3, clock: { time },
            isCurrent: { current }, isEnabled: { current = false; return false },
            enable: { enables += 1; return true }, pause: { _ in time += 0.04 }))
        current = true
        #expect(!MiniMaxCodeAccessibilityAdmission.prepare(deadline: 3, clock: { time },
            isCurrent: { current }, isEnabled: { time = 3; return nil },
            enable: { enables += 1; return true }, pause: { _ in time += 0.04 }))
        #expect(enables == 0)
    }
    @Test func failedEnableOrSourceChangeDuringEnableDoesNotAdmitNavigation() {
        #expect(!MiniMaxCodeAccessibilityAdmission.prepare(deadline: 3, clock: { 0 },
            isCurrent: { true }, isEnabled: { false }, enable: { false }, pause: { _ in }))
        var current = true
        #expect(!MiniMaxCodeAccessibilityAdmission.prepare(deadline: 3, clock: { 0 },
            isCurrent: { current }, isEnabled: { nil }, enable: { current = false; return true }, pause: { _ in }))
    }
    @Test func aSetterCannotSkipDebounceOrContinueAfterSourceRevocation() {
        var time = 0.0, enables = 0
        #expect(!MiniMaxCodeAccessibilityAdmission.prepare(deadline: 0.2, clock: { time },
            isCurrent: { true }, isEnabled: { false }, enable: { enables += 1; return true },
            pause: { _ in time += 0.04 }))
        #expect(enables == 1 && time >= 0.2)
        time = 0
        var current = true
        #expect(!MiniMaxCodeAccessibilityAdmission.prepare(deadline: 3, clock: { time },
            isCurrent: { current }, isEnabled: { false }, enable: { true },
            pause: { _ in time += 0.04; current = false }))
        #expect(time == 0.04)
    }
    @Test func aFalseOrUnavailableGetterCannotKeepTheSettledRequestWaitingForever() {
        for enabled in [false, nil] as [Bool?] {
            var time = 0.0, enables = 0
            #expect(MiniMaxCodeAccessibilityAdmission.prepare(deadline: 6, clock: { time },
                isCurrent: { true }, isEnabled: { enabled }, enable: { enables += 1; return true },
                pause: { _ in time += 0.04 }))
            #expect(enables == 1 && time >= 2.1 && time < 2.2)
        }
    }
}
