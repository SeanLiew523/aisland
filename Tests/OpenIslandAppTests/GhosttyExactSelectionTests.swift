import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct GhosttyExactSelectionTests {
    private let first = TerminalJumpService.GhosttyTerminal(id: "first", workingDirectory: "/tmp/shared", title: "OMP first")
    private let second = TerminalJumpService.GhosttyTerminal(id: "second", workingDirectory: "/tmp/shared", title: "OMP second")
    private func target(id: String? = nil, cwd: String? = "/tmp/shared", title: String = "OMP first") -> JumpTarget {
        .init(terminalApp: "Ghostty", workspaceName: "fixture", paneTitle: title, workingDirectory: cwd, terminalSessionID: id)
    }
    @Test func exactIDWinsAndForeignIDNeverFallsBack() {
        #expect(TerminalJumpService.selectGhosttyTerminal([first, second], target: target(id: "second")) == .matched(second))
        #expect(TerminalJumpService.selectGhosttyTerminal([first], target: target(id: "foreign")) == .missing)
        #expect(TerminalJumpService.selectGhosttyTerminal([first], target: target(cwd: "/foreign")) == .missing)
        #expect(TerminalJumpService.selectGhosttyTerminal([first, first], target: target(id: "first")) == .ambiguous)
    }
    @Test func directoryAndTitleNeverCreateSourceIdentity() {
        #expect(TerminalJumpService.selectGhosttyTerminal([first], target: target()) == .missing)
        #expect(TerminalJumpService.selectGhosttyTerminal([first, second], target: target()) == .missing)
        #expect(TerminalJumpService.selectGhosttyTerminal([first], target: target(cwd: nil, title: "OMP")) == .missing)
        #expect(TerminalJumpService.selectGhosttyTerminal([first, second], target: target(cwd: nil)) == .missing)
        #expect(TerminalJumpService.selectGhosttyTerminal([first, .init(id: "other", workingDirectory: "/else", title: first.title)], target: target(cwd: nil)) == .missing)
    }
    @Test func inventoryRejectsMalformedOrDuplicateIDs() {
        #expect(TerminalJumpService.parseGhosttyInventory("first\u{1f}/tmp/shared\u{1f}OMP first\n") == [first])
        #expect(TerminalJumpService.parseGhosttyInventory("first\u{1f}/tmp/shared\n") == nil)
        #expect(TerminalJumpService.parseGhosttyInventory("first\u{1f}/tmp/shared\u{1f}one\nfirst\u{1f}/else\u{1f}two\n") == nil)
    }
    private final class Calls: @unchecked Sendable { var scripts: [String] = []; var opened: [[String]] = [] }
    @Test func receiptIDRequiresVerifiedFocusAndUnboundTargetDispatchesNoFocus() throws {
        for output in ["first", "other", "matched"] {
            let calls = Calls()
            let service = TerminalJumpService(applicationResolver: { _ in URL(fileURLWithPath: "/Applications/Ghostty.app") },
                appRunningChecker: { _ in true }, openAction: { calls.opened.append($0) },
                appleScriptRunner: { script in
                    calls.scripts.append(script)
                    return calls.scripts.count == 1 ? "first\u{1f}/tmp/shared\u{1f}OMP first\n" : output
                })
            if output == "first" { #expect(try service.jump(to: target(id: "first")) == "Focused the matching Ghostty terminal.") }
            else { #expect(throws: TerminalJumpError.self) { try service.jump(to: target(id: "first")) } }
            #expect(calls.scripts.count == 2)
            #expect(calls.scripts[1].contains("is \"first\""))
            #expect(calls.opened.isEmpty)
        }
        let calls = Calls()
        let service = TerminalJumpService(applicationResolver: { _ in URL(fileURLWithPath: "/Applications/Ghostty.app") },
            appRunningChecker: { _ in true }, openAction: { calls.opened.append($0) },
            appleScriptRunner: { script in
                calls.scripts.append(script)
                return "first\u{1f}/tmp/shared\u{1f}OMP first\nsecond\u{1f}/tmp/shared\u{1f}OMP second\n"
            })
        #expect(throws: TerminalJumpError.self) { try service.jump(to: target()) }
        #expect(calls.scripts.count == 1 && calls.opened.isEmpty)
    }
}
