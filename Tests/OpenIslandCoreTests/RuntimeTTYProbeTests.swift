import Foundation
import Testing
@testable import OpenIslandCore

struct RuntimeTTYProbeTests {
    @Test func jsonPipeWrappersResolveClosestControllingTTYWithoutReadingStdin() {
        var queried: [Int32] = []
        let rows: [Int32: String] = [100: "100 90 ??", 90: "90 80 ??", 80: "80 70 ttys031", 70: "70 1 ttys099"]
        let tty = RuntimeTTYProbe.resolve(startPID: 100, query: { pid, timeout in
            queried.append(pid); #expect(timeout > 0 && timeout <= 0.2)
            return rows[pid]
        }, now: { 0 })
        #expect(tty == "/dev/ttys031")
        #expect(queried == [100, 90, 80])
    }
    @Test func ownControllingTTYWinsEvenWhenParentHasAnotherTerminal() {
        var queried: [Int32] = []
        #expect(RuntimeTTYProbe.resolve(startPID: 100, query: { pid, _ in
            queried.append(pid); return "100 90 /dev/ttys002"
        }, now: { 0 }) == "/dev/ttys002")
        #expect(queried == [100])
    }
    @Test func eighthHopIsIncludedButNinthHopIsNeverQueried() {
        for ttyPID: Int32 in [13, 12] {
            var queried: [Int32] = []
            let tty = RuntimeTTYProbe.resolve(startPID: 20, query: { pid, _ in
                queried.append(pid); return "\(pid) \(pid - 1) \(pid == ttyPID ? "ttys005" : "??")"
            }, now: { 0 })
            #expect(queried == [20, 19, 18, 17, 16, 15, 14, 13])
            #expect(tty == (ttyPID == 13 ? "/dev/ttys005" : nil))
        }
    }
    @Test func cyclesInitAndVanishedOrMismatchedProcessesStopTheSearch() {
        for row in ["100 100 ??", "100 1 ??", "100 0 ??", "other", "101 90 ttys004"] {
            var calls = 0
            #expect(RuntimeTTYProbe.resolve(startPID: 100, query: { _, _ in calls += 1; return row }, now: { 0 }) == nil)
            #expect(calls == 1)
        }
        var calls = 0
        #expect(RuntimeTTYProbe.resolve(startPID: 100, query: { _, _ in calls += 1; return nil }, now: { 0 }) == nil)
        #expect(calls == 1)
        #expect(RuntimeTTYProbe.resolve(startPID: 1, query: { _, _ in Issue.record("must not query init"); return nil }, now: { 0 }) == nil)
    }
    @Test func totalBudgetPreventsLateOrFurtherLookupEvenIfTTYArrivesLate() {
        var time = 0.0; var calls = 0
        #expect(RuntimeTTYProbe.resolve(startPID: 100, query: { _, _ in
            calls += 1; time = 2; return "100 90 ttys001"
        }, now: { time }) == nil)
        #expect(calls == 1)
        var ticks = 0
        #expect(RuntimeTTYProbe.resolve(startPID: 100, query: { _, _ in Issue.record("budget already expired"); return nil }, now: {
            ticks += 1; return ticks == 1 ? 0 : 2
        }) == nil)
    }
    @Test(arguments: ["100 90 /dev/tty/../foreign", "100 90 /dev/console", "100 90 ttys0/other", "100 90 tty", "100 90 ttys001 extra", "100 90 ttys001\n101 90 ttys002", "-100 90 ttys001", "100 -1 ttys001", "100 99999999999999999 ??"])
    func malformedRowsCannotAdmitOrContinueAnAncestor(row: String) {
        #expect(RuntimeTTYProbe.parse(row, expectedPID: 100) == nil)
    }
    @Test func oversizedRowsAreRejectedWithoutSearchingOtherProcesses() {
        #expect(RuntimeTTYProbe.parse("100 90 " + String(repeating: "x", count: 1_024), expectedPID: 100) == nil)
    }

    @Test(arguments: ["claude", "codex", "gemini", "grok"])
    func missingObservedTTYDoesNotRestoreForeignPayloadOrFocusedLocator(agent: String) {
        let env = ["TERM_PROGRAM": "ghostty", "TTY": "/dev/ttys999"]
        let missing = { RuntimeTTYProbe.resolve(startPID: 100, query: { _, _ in "100 1 ??" }, now: { 0 }) }
        var bindingCalls = 0
        let binding: GhosttySourceBindingProvider = { _, _, tty, _, _ in
            bindingCalls += 1; #expect(tty == nil); return nil
        }
        let forbidden: (String) -> (sessionID: String?, tty: String?, title: String?) = { _ in
            Issue.record("Missing source TTY cannot query the focused page"); return (nil, nil, nil)
        }
        let result: (String?, String?)
        switch agent {
        case "claude":
            let value = ClaudeHookPayload(cwd: "/tmp", hookEventName: .userPromptSubmit, sessionID: "source", terminalSessionID: "foreign", terminalTTY: "/dev/ttys999")
                .withRuntimeContext(environment: env, currentTTYProvider: missing, terminalLocatorProvider: forbidden, ghosttyBindingProvider: binding)
            result = (value.terminalTTY, value.terminalSessionID)
        case "codex":
            let value = CodexHookPayload(cwd: "/tmp", hookEventName: .userPromptSubmit, model: "fixture", permissionMode: .default, sessionID: "source", terminalSessionID: "foreign", terminalTTY: "/dev/ttys999", transcriptPath: nil)
                .withRuntimeContext(environment: env, currentTTYProvider: missing, terminalLocatorProvider: forbidden, ghosttyBindingProvider: binding)
            result = (value.terminalTTY, value.terminalSessionID)
        case "gemini":
            let value = GeminiHookPayload(cwd: "/tmp", hookEventName: .sessionStart, sessionID: "source", terminalSessionID: "foreign", terminalTTY: "/dev/ttys999")
                .withRuntimeContext(environment: env, currentTTYProvider: missing, terminalLocatorProvider: forbidden, ghosttyBindingProvider: binding)
            result = (value.terminalTTY, value.terminalSessionID)
        default:
            let value = GrokHookPayload(cwd: "/tmp", hookEventName: .userPromptSubmit, sessionID: "source", terminalSessionID: "foreign", terminalTTY: "/dev/ttys999")
                .withRuntimeContext(environment: env, currentTTYProvider: missing, terminalLocatorProvider: forbidden, ghosttyBindingProvider: binding)
            result = (value.terminalTTY, value.terminalSessionID)
        }
        #expect(result.0 == nil); #expect(result.1 == nil); #expect(bindingCalls == 1)
    }

    @Test func hermesIntakeSurvivesMissingProbeAndRejectsInheritedTTY() throws {
        let raw = #"{"hook_event_name":"pre_llm_call","session_id":"source","cwd":"/tmp","extra":{"turn_id":"turn"}}"#
        let result = try #require(try HermesHookAdapter.decode(Data(raw.utf8), profileID: "fixture",
            environment: ["TERM_PROGRAM": "ghostty", "TTY": "/dev/ttys999", "TERM_SESSION_ID": "foreign"],
            ttyProvider: { RuntimeTTYProbe.resolve(startPID: 100, query: { _, _ in "100 1 ??" }, now: { 0 }) },
            ghosttyBindingProvider: { _, _, _, _, _ in nil }))
        #expect(result.event == .turnStarted); #expect(result.terminalTTY == nil); #expect(result.terminalSessionID == nil)
    }
}
