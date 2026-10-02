# AIsland Product Scope

## Project Identity

AIsland is an independently maintained macOS product derived from Open Island. It retains the GPL-3.0 license and original copyright notices, while owning its branding, roadmap, releases, and first-class ZCode and WorkBuddy integrations. Internal `OpenIsland*` target names and compatibility paths remain stable unless a separate migration is intentionally designed.

## Problem

CLI coding agents are powerful, but they pull attention away from the editor and terminal. Developers need a lightweight control surface to monitor work, approve actions, answer questions, and return to the right session quickly — without handing their machine over to a closed-source paid app.

## Target User

- macOS developers using terminal-based coding agents daily
- Users running more than one agent or more than one terminal session
- Users who care about low latency, native behavior, and open-source transparency

## Product Principles

- **Open source** — all code is public, all contributions are AI-produced
- **Local first** — no server dependency, no accounts, no analytics
- **Native macOS** — SwiftUI + AppKit, not a web wrapper
- **Terminal-native** — built to support the terminal workflow, not replace it
- **Fail open** — if the app or bridge is unavailable, agents keep running unchanged

## Supported Code Agents

| Agent | Status | Notes |
|---|---|---|
| **Claude Code** | Supported | Hook integration, JSONL session discovery, status line bridge, usage tracking |
| **Codex** | Supported | Full hook integration (SessionStart, UserPromptSubmit, Stop), usage tracking |
| **OpenCode** | Supported | JS plugin integration, permission/question flows, process detection |
| **Qoder** | Supported | Claude Code fork — same hook format, config at `~/.qoder/settings.json` |
| **Qwen Code** | Supported | Claude Code fork — same hook format, config at `~/.qwen/settings.json` |
| **Factory** | Supported | Claude Code fork — same hook format, config at `~/.factory/settings.json` |
| **CodeBuddy** | Supported | Claude Code fork — same hook format, config at `~/.codebuddy/settings.json` |
| **ZCode** | Supported | Seven managed events in `~/.zcode/cli/config.json`, interactive permission flow, desktop liveness, and exact conversation focus through the local task index plus Accessibility |
| **WorkBuddy** | Supported | Nine managed events in `~/.workbuddy/settings.json`, desktop liveness, and exact `workbuddy://chat/<session-id>` jump-back |
| **Cursor** | Supported | Hook integration, session tracking, and workspace jump-back |
| **Gemini CLI** | Supported | Hook integration (`SessionStart`, `BeforeAgent`, `AfterAgent`, `SessionEnd`, `Notification`), session tracking, terminal jump metadata, completion-card compatibility handling |
| **Kimi CLI** | Supported | Hook integration via `~/.kimi/config.toml` `[[hooks]]` (Moonshot AI). Kimi's hook payload is byte-compatible with Claude Code, so runtime reuses the Claude decode path; a dedicated TOML installer preserves user-authored hooks |
| **Grok Build** | Supported | Managed hook file, lifecycle tracking, and terminal jump-back |
| **Pi** | Supported | Runtime extension at `~/.pi/agent/extensions/open-island.ts`; lifecycle/tool events, session persistence, process detection, and terminal jump metadata |
| **Oh My Pi (OMP)** | Supported | Runtime extension at `~/.omp/agent/extensions/open-island.ts`; equivalent coverage through OMP lifecycle aliases |

## Supported Terminals

| Terminal | Status | Notes |
|---|---|---|
| **Terminal.app** | Full Support | Jump-back with TTY targeting |
| **Ghostty** | Full Support | Jump-back with ID matching |
| **cmux** | Full Support | Jump-back via Unix socket API |
| **Kaku** | Full Support | Jump-back via CLI pane targeting |
| **WezTerm** | Full Support | Jump-back via CLI pane targeting |
| **iTerm2** | Full Support | Jump-back with session ID / TTY matching |
| **tmux** (multiplexer) | Full Support | Jump-back with session/window/pane targeting |
| **Warp** | Full Support | Precision tab jump through SQLite pane lookup and Accessibility |

## Features

- **Notch overlay** — sits in the notch area on notch Macs, falls back to a compact top-center bar on external displays or non-notch Macs
- **Settings** — hook install/uninstall, usage dashboard, General, Display, Sound, Shortcuts, Lab, About
- **Notification mode** — auto-height panel for permission requests and session events
- **Notification sounds** — configurable system sounds with mute toggle
- **i18n** — English and Simplified Chinese
- **Session discovery** — auto-discover from local transcripts, persist across launches
- **Process discovery** — match active agents via `ps`/`lsof`
- **DMG packaging** — ad-hoc signed independent releases today, with a separate path for future Developer ID signing and notarization
- **Auto-update** — Sparkle remains embedded, but independent development builds keep updates disabled until AIsland owns a signed appcast and release identity

## Success Criteria

- Agent events appear in the overlay with low latency
- Approval and answer actions round-trip back to the source process
- The app can restore focus to the owning terminal window reliably
- Idle resource usage remains low enough for all-day background use

## Future Directions

- Stable public signing, notarization, and AIsland-owned updates
- Sound packs, themes, and onboarding polish
- Deeper terminal split targeting
