# Hook System

OpenIsland receives lifecycle events from managed hook CLIs and runtime extensions. Codex, Claude-family agents, Gemini CLI, Grok Build, and Kimi CLI invoke `OpenIslandHooks`; Pi and Oh My Pi load a TypeScript extension. Both paths forward typed payloads to the app over its Unix socket. Hook sources that support blocking can receive directives on stdout; Pi-family extensions are fire-and-forget.

## Architecture

```text
Managed hook agent                     Pi / Oh My Pi
  │ stdin: JSON payload                  │ runtime ExtensionAPI events
  ▼                                      ▼
OpenIslandHooks CLI                   open-island.ts
  │                                      │
  └──────────── Unix socket ──────────────┘
                         │
                         ▼
              BridgeServer → AppModel → UI

```
Blocking hook sources receive a `BridgeResponse` through `OpenIslandHooks` stdout. Pi-family extension events do not block the agent.

**Fail-open principle**: if the bridge is unavailable, managed hook processes exit without writing to stdout and Pi-family extensions ignore socket errors, so the agent continues running unchanged.

Ordinary app startup locates the callback helper inside the current app bundle and awaits deployment of its managed copy before inspecting hook status, migrating installation intent, or configuring detected sources. Only an executable deployed copy with matching bytes is admitted. Normal source commands use the durable `ManagedHooksBinary.defaultURL()` destination, including Hermes commands and consent identity, rather than the app bundle path. A missing or failed helper stops automatic source configuration. Startup readiness is reported once; completing first-run onboarding remains a separate user action.

Historical session discovery runs independently and cannot replace the admitted helper or trigger startup setup again. Late startup results add historical sessions while preserving every existing identity's current state and navigation metadata, including matching transcript aliases. Cache pruning uses the final merged current state instead of writing the earlier scan snapshot back over newly arrived sessions. Runtime acceptance skips ordinary helper lookup, deployment, source reads, and configuration; scoped source-setup acceptance uses only its isolated wrapper and admitted sources.

Ordinary live process monitoring starts once after successful bridge startup, independently of history discovery and source setup. This lets an already-running Codex App connect through the existing app-server path while historical scans are pending. Runtime acceptance and launches with runtime-state loading or bridge startup disabled do not start ordinary monitoring; applying late history only reconciles the restored attachments.

## Skip Hooks For Delegated Control

Set `OPEN_ISLAND_SKIP_HOOKS=1` on a child agent process when another local controller intentionally owns permission handling for that run. The hook CLI exits immediately without reading or forwarding the payload, so the agent continues without AIsland UI intervention.

`VIBE_ISLAND_SKIP=1` is also recognized as a legacy compatibility alias.

This is meant for per-process launches. Do not set it globally unless you want AIsland hooks disabled for every agent started from that environment.

**Entry point**: [`Sources/OpenIslandHooks/main.swift`](../Sources/OpenIslandHooks/main.swift)

---

## v0.1.1 Runtime Lifecycle Sources (acceptance pending)

Hermes CLI uses `OpenIslandHooks --source hermes --profile-id <profile-directory>`. Its managed shell hooks are `pre_llm_call` and `on_session_end`; the latter carries explicit completed/failed/interrupted flags and a turn identity. `post_llm_call` is not a completion signal. Hermes manages its own command consent, which AIsland never auto-approves. The installer only owns its exact entries and manifest; unrelated config and consent remain intact.

DeepSeek Harness Desktop uses the [official-profile source plugin](../Integrations/DeepSeek/README.md), with a server event projection and a client navigation bridge. Only future `turn/start` and explicit `turn/end` reasons are projected. `idle`, process silence and navigation dispatch are not completion evidence. Public `openSession(ID)` returns void, so dispatch is separately accepted from visible selection and frontmost activation.

Both use `processRuntimeLifecycleHook` with `runtimeLifecycleHook` over the existing NDJSON bridge. Source/profile/session namespace, turn identity, sequence and timestamp prevent cross-task completion, stale events and replay. Only a matching start observed in the current native run and not explicitly unobserved by the source may notify successful completion. Unsuccessful endings and restored endings update state silently; companion success notifications obey the same distinction. `source_observed_start:false` repairs a plugin-reload ending without creating a fresh alert.

Payloads carry only identity, status and navigation metadata; no prompt, tool input, history, error body or credential is projected. Exact contract and restoration behavior are in the [Hermes/native implementation record](exec-plans/active/v0.1.1-hermes-implementation.md). Source-specific reason enums are pinned there and in the plugin. Real native consent, source loading, state, sound and navigation remain pending acceptance.

---

## Codex Hooks (`--source codex`)

**Payload type**: `CodexHookPayload`
**Source**: [`Sources/OpenIslandCore/CodexHooks.swift`](../Sources/OpenIslandCore/CodexHooks.swift)

### Events

| `hook_event_name` | When it fires | Notable fields |
|---|---|---|
| `SessionStart` | Session starts or resumes (`source: "resume"` on resume) | `prompt`, `source` |
| `PreToolUse` | Before a shell command executes | `tool_name`, `tool_input.command`, `turn_id`, `tool_use_id` |
| `PermissionRequest` | Codex requests permission for a tool/action | `tool_name`, `tool_input`, `turn_id` |
| `PostToolUse` | After a shell command completes | `tool_name`, `tool_input`, `tool_response`, `turn_id` |
| `UserPromptSubmit` | User submits a new prompt | `prompt` |
| `Stop` | A turn completes | `last_assistant_message`, `stop_hook_active` |

### Default managed installation

The managed Codex hook installer (`CodexHookInstaller`) installs `SessionStart`, `UserPromptSubmit`, `PermissionRequest`, and `Stop` by default. This keeps the lifecycle hooks low-noise while still allowing OpenIsland to broker Codex's first-class approval requests. Per-command `PreToolUse` / `PostToolUse` hooks remain opt-in because they can add terminal log noise.

The installer chooses the Codex hook feature flag that the local Codex CLI advertises. Newer Codex builds use `[features].hooks = true`; older builds use the legacy `[features].codex_hooks = true`. Status checks recognize both keys, and managed installs migrate between them when the local Codex version changes.

After hooks are installed or changed, Codex may require a manual trust review before running them. Open `/hooks` inside Codex CLI and approve the expected AIsland hook entries. This approval gate belongs to Codex and is not bypassed by AIsland.

The `CodexHookPayload` model and `BridgeServer` can parse richer events (`PreToolUse`, `PostToolUse`) when they are present in the hook payload, and will surface them in the UI if received. However, these per-tool lifecycle events are **not** installed by the managed installer and must be configured manually if desired.

> **Note on file-edit coverage**: Codex file edits may use internal apply-patch paths that do not emit `PreToolUse` events. File-edit approval should not be treated as guaranteed `PreToolUse` coverage; the current reliable coverage is command/shell-level events, depending on Codex hook configuration.

### Common payload fields

| JSON key | Swift property | Description |
|---|---|---|
| `cwd` | `cwd` | Working directory |
| `hook_event_name` | `hookEventName` | Event type |
| `session_id` | `sessionID` | Session UUID |
| `model` | `model` | Model name |
| `permission_mode` | `permissionMode` | `default` / `acceptEdits` / `plan` / `dontAsk` / `bypassPermissions` |
| `transcript_path` | `transcriptPath` | JSONL transcript file path |
| `terminal_app` | `terminalApp` | Terminal name (`Terminal`, `Ghostty`, `iTerm`, …) |
| `terminal_session_id` | `terminalSessionID` | Terminal session identifier |
| `terminal_tty` | `terminalTTY` | TTY device path |
| `terminal_title` | `terminalTitle` | Tab / window title |
| `turn_id` | `turnID` | Current turn ID |
| `tool_name` | `toolName` | Tool name (e.g. `shell`) |
| `tool_use_id` | `toolUseID` | Tool-use call ID |
| `tool_input` | `toolInput` | Tool input (commonly includes `command` and/or `description`) |
| `tool_response` | `toolResponse` | Tool output (JSON) |
| `prompt` | `prompt` | User prompt text |
| `last_assistant_message` | `lastAssistantMessage` | Last assistant message |
| `stop_hook_active` | `stopHookActive` | Whether the stop hook is active |

### Directive responses

#### `PreToolUse`

The app can block a command by writing this to stdout:

```json
{"decision": "block", "reason": "Blocked by AIsland"}
```

#### `PermissionRequest`

The managed `PermissionRequest` hook has a 1-hour timeout so the user can approve or deny from the UI.

Allow:

```json
{
  "continue": true,
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow"
    }
  }
}
```

Deny:

```json
{
  "continue": true,
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "deny",
      "message": "User denied the permission request"
    }
  }
}
```

All other Codex events require no stdout response.

---

## Claude Code Hooks (`--source claude`)

**Payload type**: `ClaudeHookPayload`
**Source**: [`Sources/OpenIslandCore/ClaudeHooks.swift`](../Sources/OpenIslandCore/ClaudeHooks.swift)

### Events

| `hook_event_name` | When it fires | Directive response |
|---|---|---|
| `SessionStart` | Session starts (`startup` / `resume` / `clear` / `compact`) | None |
| `SessionEnd` | Session ends | None |
| `UserPromptSubmit` | User submits a prompt | None |
| `PreToolUse` | Before a tool call | **Yes** — allow / deny / modify input |
| `PostToolUse` | After a successful tool call | None |
| `PostToolUseFailure` | After a failed tool call | None |
| `PermissionRequest` | Agent requests user approval | **Yes** — allow or deny (24 h timeout) |
| `PermissionDenied` | A permission was denied | None |
| `Notification` | Agent emits a notification | None |
| `Stop` | Turn ends normally | None |
| `StopFailure` | Turn ends with an error | None |
| `SubagentStart` | A sub-agent starts | None |
| `SubagentStop` | A sub-agent stops | None |
| `PreCompact` | Before context compaction | None |

### Common payload fields

| JSON key | Swift property | Description |
|---|---|---|
| `cwd` | `cwd` | Working directory |
| `hook_event_name` | `hookEventName` | Event type |
| `session_id` | `sessionID` | Session UUID |
| `transcript_path` | `transcriptPath` | JSONL transcript file path |
| `permission_mode` | `permissionMode` | Permission mode |
| `model` | `model` | Model name |
| `agent_id` | `agentID` | Sub-agent ID (SubagentStart/Stop) |
| `agent_type` | `agentType` | Sub-agent type |
| `source` | `source` | Start source (`startup` / `resume` / `clear` / `compact`) |
| `tool_name` | `toolName` | Tool name |
| `tool_input` | `toolInput` | Tool input parameters (JSON) |
| `tool_use_id` | `toolUseID` | Tool-use call ID |
| `tool_response` | `toolResponse` | Tool output (JSON) |
| `permission_suggestions` | `permissionSuggestions` | Suggested permission changes (PermissionRequest) |
| `prompt` | `prompt` | User prompt text |
| `message` | `message` | Notification message body |
| `title` | `title` | Notification title |
| `notification_type` | `notificationType` | Notification type |
| `stop_hook_active` | `stopHookActive` | Whether the stop hook is active |
| `last_assistant_message` | `lastAssistantMessage` | Last assistant message |
| `error` | `error` | Error message (Failure events) |
| `error_details` | `errorDetails` | Extended error details |
| `is_interrupt` | `isInterrupt` | Whether the event is an interrupt |
| `agent_transcript_path` | `agentTranscriptPath` | Sub-agent transcript path |
| `terminal_app` | `terminalApp` | Terminal name |
| `terminal_session_id` | `terminalSessionID` | Terminal session identifier |
| `terminal_tty` | `terminalTTY` | TTY device path |
| `terminal_title` | `terminalTitle` | Tab / window title |

### PreToolUse directive response

```json
{
  "continue": true,
  "suppressOutput": true,
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow" | "deny" | "ask",
    "permissionDecisionReason": "reason shown to the agent",
    "updatedInput": { ... },
    "additionalContext": "extra context injected into the turn"
  }
}
```

| Field | Description |
|---|---|
| `permissionDecision` | `allow` — proceed; `deny` — block; `ask` — let the agent ask the user |
| `permissionDecisionReason` | Human-readable reason forwarded to the agent |
| `updatedInput` | Replace the tool's input parameters (optional) |
| `additionalContext` | Inject additional context into the turn (optional) |

### PermissionRequest directive response

The `PermissionRequest` event has a **24-hour timeout** to allow the user to review and approve in the UI.

Allow:

```json
{
  "continue": true,
  "suppressOutput": true,
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow",
      "updatedInput": { ... },
      "updatedPermissions": [ ... ]
    }
  }
}
```

Deny:

```json
{
  "continue": true,
  "suppressOutput": true,
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "deny",
      "message": "User denied the permission request",
      "interrupt": false
    }
  }
}
```

Setting `interrupt: true` terminates the current agent turn immediately.

---

## Claude Code Fork Hooks (`--source qoder` / `qwen` / `factory` / `droid` / `codebuddy` / `kimi`)

Qoder, Qwen Code, Factory, CodeBuddy, and Kimi CLI reuse `ClaudeHookPayload` verbatim: the same 14 managed events, payload fields, and directive responses as Claude Code. Hooks are installed into each fork's `~/.<name>/settings.json`; the `--source` argument distinguishes the agent on the wire.

## ZCode Hooks (`--source zcode`)

**Payload type**: `ClaudeHookPayload` (Claude-format)
**Source**: [`Sources/OpenIslandCore/ZCodeHookInstallationManager.swift`](../Sources/OpenIslandCore/ZCodeHookInstallationManager.swift)

ZCode consumes Claude-format payloads but differs from Claude Code in configuration layout and event coverage:

- Configuration lives at `~/.zcode/cli/config.json`, with hook groups nested under `hooks.events.<Event>` (not a top-level `hooks` key) and `hooks.enabled: true` required before configuration-file hooks run.
- ZCode supports exactly seven events; the managed install registers only these: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Stop`.
- `PermissionRequest` supports the interactive allow/deny directive (24 h timeout); matchers are case-sensitive regexes against tool names (`.*` installs as match-all).
- Agents run inside the ZCode desktop app (`dev.zcode.app`); the hook stamps `terminal_app: "ZCode.app"` from the `ZCODE_*` runtime env, session liveness follows the running app, and jump-back raises the existing app window before selecting the corresponding conversation.
- ZCode does not expose a public per-conversation URL. AIsland therefore carries the hook's stable `session_id`, resolves it read-only through `~/.zcode/v2/tasks-index.sqlite`, presses the exact conversation item in ZCode's accessibility tree, and verifies both its selected sidebar state and the resulting page heading. It expands the matching project and reveals additional conversation pages when needed. Standalone tasks have a workspace directory but no project section; for these, AIsland locates the sidebar item outside project sections only when the index identifies one task with that title and the visible item is unambiguous. If the task index or accessibility surface is unavailable, or a standalone title is ambiguous, jump-back degrades to focusing the project window, opening `zcode://workspace/open?path=<git root>`, or activating the app.
- For an already-running ZCode app, jump-back requests LaunchServices activation before selecting the task and confirms ZCode is the frontmost app before reporting success. This also covers a visible, non-minimized ZCode window behind another app; an AX-selected conversation in a background window is not a completed jump.

## WorkBuddy Hooks (`--source workbuddy`)

**Payload type**: `ClaudeHookPayload` (Claude-format)
**Config**: `~/.workbuddy/settings.json` — same shape as Claude Code

WorkBuddy consumes a nine-event subset of the Claude format; the managed install registers `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `SubagentStop`, `Notification`, `PreCompact`. Events are fire-and-forget (no `PermissionRequest` integration). Agents run inside the WorkBuddy desktop app (`com.tencent.workbuddy.mac`); the hook stamps `terminal_app: "WorkBuddy.app"`, session liveness follows the running app, and jump-back uses `workbuddy://chat/<session-id>` when the session supplies a deep link, falling back to app activation.

---

## Gemini CLI Hooks (`--source gemini`)

**Payload type**: `GeminiHookPayload`
**Source**: [`Sources/OpenIslandCore/GeminiHooks.swift`](../Sources/OpenIslandCore/GeminiHooks.swift)

### Events

| `hook_event_name` | When it fires | Current OpenIsland behavior |
|---|---|---|
| `SessionStart` | Session starts or resumes | Creates or restores the Gemini session, title, jump target, and transcript metadata |
| `BeforeAgent` | Gemini starts handling a prompt / turn | Marks the session running, updates prompt text, refreshes terminal metadata |
| `AfterAgent` | Gemini finishes a turn | Marks the turn completed and emits a completion card |
| `SessionEnd` | Gemini reports the session ended | Marks the hook-managed session ended and removes it from active visibility |
| `Notification` | Gemini emits a notification message | Updates the session summary / activity text without blocking the agent |

### Common payload fields

| JSON key | Swift property | Description |
|---|---|---|
| `cwd` | `cwd` | Working directory |
| `hook_event_name` | `hookEventName` | Event type |
| `session_id` | `sessionID` | Session identifier |
| `transcript_path` | `transcriptPath` | Gemini transcript file path |
| `timestamp` | `timestamp` | Hook timestamp |
| `prompt` | `prompt` | User prompt text |
| `prompt_response` | `promptResponse` | Gemini response text |
| `source` | `source` | Session start source |
| `reason` | `reason` | Session-end reason |
| `notification_type` | `notificationType` | Notification category |
| `message` | `message` | Notification message |
| `details` | `details` | Structured notification payload |
| `stop_hook_active` | `stopHookActive` | Whether Gemini stop hook support is active |
| `terminal_app` | `terminalApp` | Terminal name |
| `terminal_session_id` | `terminalSessionID` | Terminal session identifier |
| `terminal_tty` | `terminalTTY` | TTY device path |
| `terminal_title` | `terminalTitle` | Tab / window title |

### Current feature coverage

- Session lifecycle ingestion for Gemini CLI via `OpenIslandHooks --source gemini`
- Session list and island visibility updates from Gemini hook events
- Prompt / response metadata capture for completion cards and session details
- Terminal jump metadata enrichment for Terminal.app, iTerm2, Ghostty, and other supported terminals
- Process-assisted liveness matching so active Gemini CLI sessions can stay visible even when hook traffic is sparse

### Current limitations

- Gemini hooks are currently treated as fire-and-forget. OpenIsland does not send Gemini-specific approval or modification directives back to stdout.
- Gemini hook payloads sometimes include a duplicated copy of the final response body, often with whitespace-only differences. OpenIsland applies a best-effort compatibility pass before rendering completion content, but the result is not guaranteed to be perfect for every response shape.
- Gemini support is currently limited to the hook events and UI/session behaviors listed above. It does not yet match the richer permission / interaction flows available for Claude Code or OpenCode.

---

## Pi and Oh My Pi Extensions

**Payload type**: `PiHookPayload`

**Sources**: [`Sources/OpenIslandCore/PiHooks.swift`](../Sources/OpenIslandCore/PiHooks.swift), [`Sources/OpenIslandApp/Resources/open-island-pi.ts`](../Sources/OpenIslandApp/Resources/open-island-pi.ts)

AIsland installs one bundled extension per runtime:

- Pi: `~/.pi/agent/extensions/open-island.ts`
- Oh My Pi: `~/.omp/agent/extensions/open-island.ts`

The setup UI installs, refreshes, reveals, and uninstalls each extension independently. Current status can compare the installed bytes with the expected bundled template rendered for that agent and socket, so a previous version-4 receipt does not hide a template update. Version-3 migration additionally admits only the exact reviewed `7b2107d` production Pi/OMP renderings, with matching receipt agent/path and backups before replacement. The installer writes only `open-island.ts` plus its AIsland ownership manifest; uninstall leaves other user extensions untouched.

### Event coverage

| AIsland event | Pi event | Oh My Pi event | Behavior |
|---|---|---|---|
| `SessionStart` | `session_start` | `session_start` | Creates the typed Pi/OMP session with model, transcript, working-directory, and terminal metadata |
| `UserPromptSubmit` | `before_agent_start` | `before_agent_start` | Updates the latest user prompt and marks the session running |
| `PreToolUse` | `tool_execution_start` | `tool_execution_start` | Shows the active tool and a clipped input preview |
| `PostToolUse` | `tool_execution_end` | `tool_execution_end` | Clears the active tool and records tool completion |
| `Stop` | `agent_settled` | `session_stop` | Marks the current turn completed and records the latest assistant text |
| `Heartbeat` | 15-second session timer | 15-second session timer | Refreshes only per-session liveness; it does not change turn phase, summary, tool, or message metadata |
| `SessionEnd` | `session_shutdown` | `session_shutdown` | Ends the tracked session immediately; reload shutdowns stop the timer without ending the session |

Jump-back metadata uses the source environment and a bounded TTY lookup. For Ghostty, Pi/OMP never treat `TERM_SESSION_ID` as a surface ID. A UI `session_start` may bind the uniquely matching working directory; otherwise the first `input` event with `source == "interactive"` and `ctx.hasUI` captures the public Ghostty surface ID/title. Capture requires Ghostty to be frontmost, the source working directory to match, an unambiguous ID, and unchanged focus across the read-only snapshot. Interactive input distinguishes separate TUI processes sharing one directory. RPC/extension input and `before_agent_start` never capture focus; tool, completion and heartbeat events retain the admitted per-session binding. Missing permission or source evidence leaves the ID absent. No terminal content or input text is read by the locator, and terminal titles are never changed.

Ghostty navigation requires a source-owned surface ID. Reconciliation and clicks never invent an ID from a working directory or ordinary title, even when the directory has one page. A missing or invalid ID refuses automatic focus and waits for a subsequent trusted source event to supply the binding; this does not signal that the source exited. Attachment discovery may associate an unbound source with a title containing its complete canonical native UUID as a standalone token, only when the source and page match uniquely; prefixes and substrings are not evidence, and this cannot replace an existing recorded surface ID. Shared-directory ambiguity remains rejected. All paths check that the observed focused ID equals the resolved target before reporting success. See [Ghostty's public object model](https://ghostty.org/docs/features/applescript); Ghostty 1.3.1 exposes ID, name and working directory, without a TTY/PID property. The extension does not forward terminal variables into child shell commands. When a prompt starts it sets `OPEN_ISLAND_ACTIVE=1` in the agent process environment, so commands the agent spawns can tell that AIsland is tracking the session. If the socket is unavailable, connection errors are ignored and agent execution continues. Pi and Oh My Pi liveness is keyed by `session_id`: heartbeat keeps or restores that specific session, a 45-second heartbeat timeout hides it after an abnormal exit, and generic process polling does not keep Pi/OMP sessions alive.

### Current limitations

- Pi and Oh My Pi extension events are fire-and-forget. AIsland does not block, approve, deny, or rewrite tool calls through these integrations.
- Runtime event objects are intentionally decoded defensively because Pi and Oh My Pi expose overlapping lifecycle concepts with some different event names.

---

## Timeout Policy

| Source | Event | Timeout |
|---|---|---|
| Codex | `PermissionRequest` | **1 hour** (awaits human approval) |
| Codex | All other managed events | **45 seconds** |
| Claude Code | `PermissionRequest` | **24 hours** (awaits human approval) |
| Claude Code | All other events | **45 seconds** |
| Gemini CLI | All events | Bridge default |
| Grok Build | All managed events | **45 seconds** |
| Pi / Oh My Pi | Heartbeat liveness | **45 seconds** |

---

## Grok Build Hooks (`--source grok`)

**Payload type**: `GrokHookPayload`
**Source**: [`Sources/OpenIslandCore/GrokHooks.swift`](../Sources/OpenIslandCore/GrokHooks.swift)

Grok Build (Grok CLI / Grok TUI) discovers hooks from `~/.grok/hooks/*.json`. AIsland writes a dedicated managed file at `~/.grok/hooks/open-island.json`.

Grok also loads Claude and Cursor hook configurations by default. Their AIsland commands quietly exit when the stdin envelope has Grok's native camelCase identity plus consistent Claude snake_case aliases, and the runner-injected `GROK_HOOK_EVENT`, `GROK_SESSION_ID`, and `GROK_WORKSPACE_ROOT` all match that identity. This check runs before terminal discovery or sending a bridge command; only `--source grok` produces the Grok lifecycle, activity and notifications. Native Claude/Cursor callbacks continue normally, including child agents inheriting Grok environment variables: markers alone do not suppress them. Missing or inconsistent evidence preserves the declared source. No user hook configuration is changed. This admission rule follows the installed Grok 1.0.46 documentation and the official [envelope serializer](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-hooks/src/event.rs) and [command runner](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-hooks/src/runner/command.rs). Compatibility commands do not act as a fallback if the native AIsland Grok hook is absent.

### Events (managed install)

All of the following are registered in `~/.grok/hooks/open-island.json` by the managed installer:

| Event | Matcher | Current OpenIsland behavior |
|---|---|---|
| `SessionStart` | — | Creates / re-opens the Grok session, title, and jump target |
| `SessionEnd` | — | Marks the hook-managed session ended (`isSessionEnd`) |
| `UserPromptSubmit` | — | Marks the session running and updates summary |
| `Stop` | — | Completion when `reason == "end_turn"`; if `reason` is omitted, treat as turn completion; non-`end_turn` reasons are observe-only |
| `StopFailure` | — | Activity update, phase `.completed` (session not ended) |
| `StopCancelled` | — | Turn completion flagged `isInterrupt` — fires *instead of* `Stop` on a user interrupt (Ctrl+C / Esc), a declined or cancelled permission prompt, `--max-turns`, or a no-progress bail-out; summary is `lastAssistantMessage` when present, else derived from `reason` |
| `Notification` | `*` | Activity update; `notificationType == "idle_prompt"` settles a still-running session as completed (Grok's backstop for turns that reported no Stop-family event) and leaves an already-completed session untouched |
| `PreToolUse` | `*` | Activity update, **fire-and-forget** (no deny directive; fail-open) |
| `PostToolUse` | `*` | Activity update |
| `PostToolUseFailure` | `*` | Activity update, phase `.completed` |
| `SubagentStart` / `SubagentStop` | — | Activity updates |
| `PermissionDenied` | — | Activity update; session stays running. Fires for both a user **Reject** (a `StopCancelled` with `permission_rejected` follows and settles the turn) and a configured **PolicyDeny** rule (the model is told the tool was skipped and keeps working) |
| `PreCompact` / `PostCompact` | — | Activity updates |

Managed status is **healthy only when every event above** is present with an AIsland Grok command. A Vibe Island-only command does **not** count as installed.

### Lifecycle / liveness notes

- Non-`SessionStart` events on an **already ended** session are acknowledged and ignored (no resurrection).
- Process discovery cannot recover Grok session UUIDs. While a `grok` process is alive, AIsland keeps non-ended Grok sessions in the process-alive set (TTY/CWD match when unique; otherwise a conservative “any Grok process” fallback similar to Kimi). Explicit `SessionEnd` still ends the session.

### Wire format notes

- Stdin JSON uses **camelCase** keys (`sessionId`, `hookEventName`, `toolName`, `toolResult`).
- `hookEventName` may arrive as PascalCase (`PreToolUse`), snake_case (`pre_tool_use`) or camelCase (`preToolUse`); all are accepted.
- Envelopes may carry `promptId`; it is decoded as `promptID` but not acted on yet (reserved for ignoring stale-prompt reports).
- `UserPromptSubmit` also fires observe-only for auto-wake turns (task/subagent completion and scheduler) and subagent sessions. Its event name is not sufficient evidence of interactive user input. Ghostty source admission uses the unique-directory capture policy for both `SessionStart` and `UserPromptSubmit`, verifies foreground/focus stability, and never overwrites an admitted ID. Multiple unbound pages in the same directory remain unresolved until stronger source evidence becomes available. See the official [UserPromptSubmit contract](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/10-hooks.md#userpromptsubmit-decision-control).
- `StopCancelled` carries `reason` (`user_interrupt`, `permission_rejected`, `permission_cancelled`, `max_turns`, `no_progress`, `unknown`), `cancelledBy` (`user` / `runtime` / `unknown`) and optional `cancelTrigger` / `reasonDetails` / `lastAssistantMessage`.
- PreToolUse decision format (not used by the managed install yet): `{"decision":"allow"}` / `{"decision":"deny","reason":"..."}`.
- Sessions also land under `~/.grok/sessions/<url-encoded-cwd>/<session-id>/` for offline discovery (not yet scanned by AIsland).

### Install / uninstall

```bash
swift run OpenIslandSetup installGrok
swift run OpenIslandSetup statusGrok
swift run OpenIslandSetup uninstallGrok
```

Or use **Settings → Setup → Grok Build** in the app.

> If commercial Vibe Island is also installed, both may write under `~/.grok/hooks/`. Prefer one controller at a time.

---

## Terminal Auto-detection

The hook process infers the terminal type from environment variables at runtime:

| Environment variable | Inferred terminal |
|---|---|
| `ITERM_SESSION_ID` or `LC_TERMINAL=iTerm2` | `iTerm` |
| `CMUX_WORKSPACE_ID` or `CMUX_SOCKET_PATH` | `cmux` |
| `GHOSTTY_RESOURCES_DIR` | `Ghostty` |
| `WARP_IS_LOCAL_SHELL_SESSION` | `Warp` |
| `TERM_PROGRAM=Apple_Terminal` | `Terminal` |
| `TERM_PROGRAM=WezTerm` | `WezTerm` |

For iTerm and Terminal, existing metadata queries supply session ID/TTY/title.
Ghostty uses a stable private binding keyed by source agent, native session ID
and real callback TTY. Source startup can bind an unambiguous directory;
Claude/Codex `UserPromptSubmit` and Pi/OMP interactive input can bind the
stable focused surface after verifying foreground and directory evidence.
Grok `UserPromptSubmit` also runs for automatic wakeups and subagent turns, so
it only reuses an existing binding or captures a uniquely matching directory;
an unbound Grok source sharing a directory with another page remains unresolved.
Tools, stops, heartbeats and notifications reuse that binding and never query
the current focused page. Gemini `BeforeAgent` does not establish interactive
input; without a startup binding, same-directory multi-page selection remains
unresolved. Generic inherited `TERM_SESSION_ID` is not a Ghostty surface ID.
Ordinary reconciliation and jump-back reject directory/ordinary-title fallback
and explicit missing-ID redirection. The `cmux` terminal uses `CMUX_SURFACE_ID`.

---

## Related source files

| File | Responsibility |
|---|---|
| [`Sources/OpenIslandHooks/OpenIslandHooksCLI.swift`](../Sources/OpenIslandHooks/OpenIslandHooksCLI.swift) | Hook CLI entry point — routes to Codex, Claude, Gemini, Grok, … |
| [`Sources/OpenIslandCore/CodexHooks.swift`](../Sources/OpenIslandCore/CodexHooks.swift) | Codex payload model, output encoder, terminal detection |
| [`Sources/OpenIslandCore/ClaudeHooks.swift`](../Sources/OpenIslandCore/ClaudeHooks.swift) | Claude Code payload model, directive types, output encoder |
| [`Sources/OpenIslandCore/GeminiHooks.swift`](../Sources/OpenIslandCore/GeminiHooks.swift) | Gemini CLI payload model, terminal detection, metadata helpers |
| [`Sources/OpenIslandCore/GrokHooks.swift`](../Sources/OpenIslandCore/GrokHooks.swift) | Grok Build payload model, terminal detection, lifecycle summaries |
| [`Sources/OpenIslandCore/GrokHookInstaller.swift`](../Sources/OpenIslandCore/GrokHookInstaller.swift) | Writes `~/.grok/hooks/open-island.json` |
| [`Sources/OpenIslandCore/PiHooks.swift`](../Sources/OpenIslandCore/PiHooks.swift) | Pi/OMP payload model and session metadata helpers |
| [`Sources/OpenIslandCore/PiExtensionInstallationManager.swift`](../Sources/OpenIslandCore/PiExtensionInstallationManager.swift) | Installs and removes the runtime-specific TypeScript extension |
| [`Sources/OpenIslandCore/PiSessionRegistry.swift`](../Sources/OpenIslandCore/PiSessionRegistry.swift) | Persists recent Pi and OMP sessions |
| [`Sources/OpenIslandApp/Resources/open-island-pi.ts`](../Sources/OpenIslandApp/Resources/open-island-pi.ts) | Shared Pi/OMP runtime extension |
| [`Sources/OpenIslandCore/BridgeServer.swift`](../Sources/OpenIslandCore/BridgeServer.swift) | Unix socket server — handles incoming hook payloads |
| [`Sources/OpenIslandCore/BridgeTransport.swift`](../Sources/OpenIslandCore/BridgeTransport.swift) | Protocol codec and envelope types |

### Opt-in Ghostty support diagnostics

An existing, user-owned empty regular file `.ghostty-diagnostics-enabled` with mode `0600` in the OpenIsland support directory enables metadata diagnostics. Removing that marker stops recording. Neither the app nor hooks create it. The private `ghostty-diagnostics.jsonl` is capped at 256 KiB; unsafe markers/logs, symlinks, a busy diagnostic lock, or a full log cause recording to be skipped. A leftover `.ghostty-diagnostics.lock` after a crash also disables writes until the operator removes it.

Records use fixed stage/reason/agent/event categories, booleans and bounded counts. Native and surface identifiers use lowercase SHA-256 of their UTF-8 bytes; Pi/OMP hash the emitted prefixed native session ID. No working directory, title, TTY value, prompt, arguments, environment values or stderr are recorded. Source binding traces distinguish missing TTY, event gates, receipt reuse, directory ambiguity and locator errors; click traces distinguish start, success and approved failure categories. This trace does not change source admission, terminal focus policy or product UI, and is not evidence of successful real navigation until the user checks the selected source.

CLI callback TTY detection is shared by Claude-family, Codex, Gemini, Grok and Hermes. It examines the callback process and at most seven ancestors, querying only PID, PPID and controlling TTY. Each query verifies the returned PID; absent processes, malformed rows, cycles and the init boundary stop the search. Lookups have a 1.5-second aggregate budget and at most 0.2 seconds per query, plus a bounded 20 ms output-drain wait and process-launch overhead. No stdin, process arguments or process environment are inspected by the probe. Inherited `TTY` and payload TTY values do not identify a Ghostty source: Ghostty continues to require the observed source TTY, native identity and existing source-binding admission/receipt checks. Finding a TTY alone never creates a surface ID or permits a directory-based jump.
