# OpenCode Ghostty source binding

Status: **precise Ghostty return is unavailable for the current OpenCode server plugin**. This round hardens controlling-TTY evidence and prevents inherited Ghostty markers from overriding an authoritative `TERM_PROGRAM`. It does not claim surface binding or real Ghostty acceptance.

## Verified source contract

The locally available `@opencode-ai/plugin` dependency is 1.1.53 (`/Users/seanliew/test/temp-install/node_modules/@opencode-ai/plugin/package.json` and `dist/index.d.ts`), not evidence of the currently running OpenCode version. The corresponding public source was inspected on 2026-10-05:

- [Plugin host v1.1.53](https://github.com/anomalyco/opencode/blob/v1.1.53/packages/opencode/src/plugin/index.ts): `PluginInput` supplies a server client and project/worktree/directory, but no current TUI session ID or input-source proof. Initialization belongs to the server workspace instance. The host loads every module export as a plugin, so this resource keeps only its default export.
- [Plugin hook types v1.1.53](https://github.com/anomalyco/opencode/blob/v1.1.53/packages/plugin/src/index.ts): `chat.message` identifies a native session and message but has no `interactive` source field. `event` receives the general event bus.
- [TUI routes v1.1.53](https://github.com/anomalyco/opencode/blob/v1.1.53/packages/opencode/src/server/routes/tui.ts): HTTP `/submit-prompt`, `/execute-command`, `/select-session`, and `/publish` can publish the same `tui.*` events. Those events prove neither local keyboard input nor the originating terminal surface.
- [TUI worker v1.1.53](https://github.com/anomalyco/opencode/blob/v1.1.53/packages/opencode/src/cli/cmd/tui/worker.ts) and [TUI thread v1.1.53](https://github.com/anomalyco/opencode/blob/v1.1.53/packages/opencode/src/cli/cmd/tui/thread.ts): the TUI shares server/RPC processing; the worker can also expose an HTTP server. A process TTY alone cannot assign every native server session to the local TUI.
- [Current server hook types](https://github.com/anomalyco/opencode/blob/dev/packages/plugin/src/index.ts), inspected the same day, still provide no interactive-source field on `chat.message`. This mutable branch observation is not a versioned runtime acceptance claim.

Consequently, a stable foreground Ghostty snapshot with a unique directory could identify a candidate surface, but it cannot identify which native server session owns that surface. Capturing at plugin initialization and handing the candidate to the first `session.created`, user `message.part.updated`, or `tui.*` event could attach an API session to a local user's page. Same-directory pages make this even less determinable. No such capture or reassignment is allowed here.

## Current payload behavior

`open-island-opencode.js` emits `terminal_app: Ghostty` and a real `terminal_tty` when discovered through process ancestry. It never emits a Ghostty `terminal_session_id` or title from `TERM_SESSION_ID`, assumed `GHOSTTY_SURFACE_ID`, a startup snapshot, current focus, or cwd matching. Background, API, tool, stop, and permission/question events do not query Ghostty. Missing or stale identity therefore cannot select a different page under the app's strict-ID navigation policy.

The controlling-TTY probe follows the shared `Sources/OpenIslandCore/RuntimeTTYProbe.swift` policy: the process itself and at most seven parents, PID/PPID/TTY only, matching requested PID, a complete bounded row, a visited set, no init traversal, 200 ms maximum per query, and a 1.5 second overall monotonic deadline. It reads no inherited `TTY`, arguments, prompts, or terminal contents. A failed/late/malformed query leaves TTY absent and preserves OpenCode event delivery.

Terminal and iTerm retain their existing payload shapes. An explicit non-Ghostty `TERM_PROGRAM` takes precedence over an inherited `GHOSTTY_RESOURCES_DIR` fallback. The environment fixture seam is per plugin instance; importing this resource no longer probes the user's process or reads the user's environment.

## Verification and remaining gate

Run `bun test ./scripts/test-opencode-ghostty-binding.ts`. The fixture imports and invokes the production plugin with synthetic environment, process rows, monotonic clock and transport. It cannot launch `/bin/ps`, OpenCode, Ghostty or the app: its process adapter admits only the synthetic `/bin/ps` query signature. Coverage includes actual ancestor TTY, malformed/mismatched rows, cycles/init, depth/time limits, stable metadata across interleaved events, same-cwd API sessions, missing/stale environment surface IDs, no foreground-reader calls, default-only exports, Terminal/iTerm and shell environment propagation. It does not model successful surface binding because no trustworthy entry contract exists.

Real Ghostty navigation is not accepted. Implementing it requires a separately reviewed TUI entry point that reports the current native session ID, proves a local interactive source, and supplies actual TTY evidence. Only that entry point may use the shared stable-frontmost source locator: unique directory at startup; trusted interactive input for same-cwd disambiguation; background only reuses an admitted `(agent, native session ID, actual TTY)` binding. Source selection must never replace an admitted surface with a newly focused page. A minimum follow-up scope includes a TUI resource and its version/capability gate, the OpenCode installer, and binding plumbing; those files were deliberately outside this round's ownership. Availability of a newer TUI-plugin API by itself is not proof that the installed version or source event meets these requirements.
