import Darwin
import CoreFoundation
import Foundation

public enum HermesHookAdapter {
    /// Hermes stdin contains user/tool/history content. Decode only identity and result fields.
    public static func decode(_ data: Data, profileID: String?, environment: [String: String] = [:],
                              timestamp: Date = .now, ttyProvider: () -> String? = runtimeTTY) throws -> RuntimeLifecycleHookPayload? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = root["hook_event_name"] as? String,
              let session = root["session_id"] as? String, !session.isEmpty else { return nil }
        let extra = root["extra"] as? [String: Any] ?? [:]
        // Shutdown supplement without a turn identity cannot safely end another active turn.
        guard let turn = extra["turn_id"] as? String, !turn.isEmpty else { return nil }
        let event: RuntimeLifecycleHookPayload.Event
        switch name {
        case "pre_llm_call": event = .turnStarted
        case "on_session_end":
            if boolean(extra["interrupted"]) == true { event = .turnInterrupted }
            else if boolean(extra["failed"]) == true { event = .turnFailed }
            else if boolean(extra["completed"]) == true { event = .turnCompleted }
            else { event = .turnFailed }
        default: return nil
        }
        let profile = profileID ?? environment["HERMES_HOME"] ?? (root["profile"] as? String)
        guard let profile, !profile.isEmpty else { return nil }
        let cwd = root["cwd"] as? String ?? ""
        // Reuse existing host inference/multiplexer IDs, but never guess the focused window.
        // PID correlation is unambiguous for Warp; cwd-only fallback is deliberately omitted.
        let runtime = ClaudeHookPayload(cwd: cwd, hookEventName: .userPromptSubmit, sessionID: session)
            .withRuntimeContext(environment: environment, currentTTYProvider: ttyProvider,
                terminalLocatorProvider: { _ in (nil, nil, nil) }, warpPaneResolver: { _ in
                    guard let context = WarpProcessResolver.resolveCurrentPaneContext() else { return nil }
                    return WarpSQLiteReader().lookupPaneUUIDByShellPID(context.shellPID, terminalServerPID: context.terminalServerPID)
                })
        return RuntimeLifecycleHookPayload(source: .hermesCLI, event: event, profileID: profile, sessionID: session,
            turnID: turn, cwd: cwd, timestamp: timestamp, terminalApp: runtime.terminalApp,
            terminalSessionID: runtime.terminalSessionID ?? environment["ITERM_SESSION_ID"] ?? environment["TERM_SESSION_ID"],
            terminalTTY: runtime.terminalTTY, resultReason: coarseReason(extra["turn_exit_reason"] as? String),
            tmuxTarget: environment["TMUX_PANE"], tmuxSocketPath: environment["TMUX"]?.components(separatedBy: ",").first,
            warpPaneUUID: runtime.warpPaneUUID)
    }
    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    public static func coarseReason(_ value: String?) -> String? {
        guard let value else { return nil }
        let coarse = String(value.prefix { $0 != "(" })
        return RuntimeLifecycleHookPayload.hermesResultReasons.contains(coarse) ? coarse : nil
    }

    public static func runtimeTTY() -> String? {
        if let tty = ProcessInfo.processInfo.environment["TTY"], tty.hasPrefix("/dev/") { return tty }
        let process = Process(); let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", "\(getppid())", "-o", "tty="]
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value == "??" || value == "-" ? nil : (value.hasPrefix("/dev/") ? value : "/dev/\(value)")
    }
}
