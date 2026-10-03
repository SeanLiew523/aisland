import Testing
@testable import OpenIslandApp

struct OnboardingMandatoryPlaybackTests {
    @Test func firstLaunchOnlyAllowsTheNaturalEnding() {
        let mode = OnboardingPlaybackMode.autoMandatory
        #expect(!mode.permitsManualExit)
        for time in [0.0, 6.0, 13.9, 21.99, 22.0, 30.0] {
            #expect(!mode.permitsFinish(.skipped, elapsed: time))
            #expect(!mode.permitsFinish(.closed, elapsed: time))
            #expect(mode.permitsFinish(.completed, elapsed: time) == (time >= 22))
        }
        #expect(mode.exitForKey(keyCode: 53, command: false, characters: nil) == nil)
        #expect(mode.exitForKey(keyCode: 13, command: true, characters: "w") == nil)
    }

    @Test func explicitReplayAllowsCloseButHasNoSkipOrEarlyCompletion() {
        let mode = OnboardingPlaybackMode.explicitReplay
        #expect(mode.permitsManualExit)
        #expect(mode.permitsFinish(.closed, elapsed: 0))
        #expect(!mode.permitsFinish(.skipped, elapsed: 0))
        #expect(!mode.permitsFinish(.completed, elapsed: 21.99))
        #expect(mode.permitsFinish(.completed, elapsed: 22))
        #expect(mode.exitForKey(keyCode: 53, command: false, characters: nil) == .closed)
        #expect(mode.exitForKey(keyCode: 13, command: true, characters: "w") == .closed)
        #expect(mode.exitForKey(keyCode: 13, command: false, characters: "w") == nil)
        #expect(mode.exitForKey(keyCode: 49, command: false, characters: " ") == nil)
    }
}
