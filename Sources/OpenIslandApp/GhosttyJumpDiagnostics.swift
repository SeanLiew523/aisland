import Foundation
import OpenIslandCore

enum GhosttyJumpDiagnostics {
    static func shouldRecord(loadRuntimeState: Bool, isAcceptance: Bool) -> Bool {
        loadRuntimeState && !isAcceptance
    }

    static func event(target: JumpTarget?, phase: String, error: Error? = nil) -> GhosttyDiagnosticEvent {
        let app = target?.terminalApp.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let category = app == "ghostty" ? "ghostty" : app == "terminal" || app == "apple_terminal" ? "terminal" : "other"
        var reason = category
        if let error {
            switch error {
            case TerminalJumpError.unsupportedTerminal: reason = "unsupportedTerminal"
            case TerminalJumpError.openFailed: reason = "openFailed"
            case TerminalJumpError.appleScriptFailed: reason = "appleScriptFailed"
            case let TerminalJumpError.conversationUnavailable(_, value):
                let allowed: Set<String> = ["terminal-inventory-unavailable", "terminal-id-or-unique-target-missing", "ambiguous-terminal", "focused-terminal-id-unverified"]
                reason = allowed.contains(value) ? value : "conversationUnavailable"
            default: reason = "unknownError"
            }
        }
        return .init(stage: "jump", event: phase, reason: reason, surfaceID: target?.terminalSessionID,
                     flags: ["isGhostty": category == "ghostty", "hasSurfaceID": target?.terminalSessionID?.isEmpty == false])
    }
}
