<p align="center">
  <img src="docs/images/readme-banner.svg" alt="AIsland — agents in your menu bar" width="760">
</p>

<h1 align="center">AIsland</h1>

<p align="center">
  <strong>A local-first macOS control surface for AI coding agents.</strong>
  <br>
  Monitor sessions, handle approvals, and jump back to the exact terminal or desktop conversation.
  <br><br>
  <a href="README.zh-CN.md">中文</a> | <strong>English</strong>
</p>

<p align="center">
  <a href="https://github.com/SeanLiew523/aisland/releases/latest"><img src="https://img.shields.io/github/v/release/SeanLiew523/aisland?style=flat-square&label=release&color=blue" alt="Latest Release"></a>
  <a href="https://github.com/SeanLiew523/aisland/stargazers"><img src="https://img.shields.io/github/stars/SeanLiew523/aisland?style=flat-square&color=yellow" alt="Stars"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL%20v3-green?style=flat-square" alt="License: GPL v3"></a>
</p>

<p align="center">
  <a href="https://github.com/SeanLiew523/aisland/releases/latest/download/AIsland.dmg">Download DMG</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="docs/index.md">Documentation</a> ·
  <a href="docs/product.md">Product Scope</a> ·
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

<p align="center">
  <a href="https://seanliew523.github.io/aisland/"><img src="docs/images/aisland-demo.gif" alt="AIsland native demo: idle, thinking, approvals, answers, sessions and completion" width="720"></a>
</p>

<p align="center">20-second native demo with example sessions · Click to explore the full demo</p>

> AIsland is an independent project based on [Open Island](https://github.com/Octane0411/open-vibe-island), distributed under GPL-3.0 with its own product and release path. See [Upstream Relationship](docs/upstream.md).

## What is AIsland?

AIsland lives in your Mac's notch or top bar and gives you one lightweight place to follow local coding agents. It surfaces session state, permission requests, questions, completion events, and a one-click route back to the owning terminal, IDE, or desktop-agent conversation.

Everything runs locally: no AIsland account, server, analytics, or telemetry.

See the [native motion demo](https://seanliew523.github.io/aisland/) for the current C1 icon and status animations.

## Highlights

- **Expressive status** — curious eyes while idle, three pulsing dots while thinking, pink approvals and warm yellow answers; waiting blinks approximately every five seconds
- **Native macOS** — SwiftUI + AppKit, not an Electron wrapper
- **Local first** — local sockets, local transcripts, and local process discovery
- **Multi-agent** — Claude Code, Codex, ZCode, WorkBuddy, Cursor, Gemini CLI, OpenCode, and more
- **Precise jump-back** — terminal targeting plus exact ZCode and WorkBuddy conversation focus
- **Interactive control** — approve or deny supported permission requests and answer agent questions
- **Fail open** — if AIsland is unavailable, managed agents continue running
- **Bilingual UI** — English and Simplified Chinese

## Supported Agents

| Agent | Current integration |
|---|---|
| **Claude Code** | Hooks, transcript discovery, permission/question flows, status-line usage bridge |
| **Codex CLI & Desktop** | Low-noise managed hooks, local usage tracking, app-server lifecycle, exact desktop deep-link jump |
| **OpenCode** | Bundled plugin, lifecycle, permission and question events |
| **Qoder** | Claude-format hooks in `~/.qoder/settings.json` |
| **Qwen Code** | Claude-format hooks in `~/.qwen/settings.json` |
| **Factory** | Claude-format hooks in `~/.factory/settings.json` |
| **CodeBuddy** | Claude-format hooks in `~/.codebuddy/settings.json` |
| **ZCode** | Seven-event hook set, interactive permission decisions, desktop liveness, exact conversation focus through the local task index and macOS Accessibility |
| **WorkBuddy** | Nine-event hook set, desktop liveness, and exact `workbuddy://chat/<session-id>` jump-back |
| **Cursor** | Hook integration, session tracking, workspace jump-back |
| **Gemini CLI** | Lifecycle hooks and fire-and-forget session updates |
| **Kimi CLI** | TOML hook installer, lifecycle and permission flow |
| **Grok Build** | Managed hook file, lifecycle tracking and terminal jump-back |
| **Pi** | Bundled TypeScript extension, lifecycle and terminal metadata |
| **Oh My Pi** | Bundled extension with equivalent lifecycle coverage |

The detailed event contracts and compatibility boundaries live in [docs/hooks.md](docs/hooks.md).

## Supported Terminals and IDEs

Full jump-back is available for Terminal.app, Ghostty, iTerm2, WezTerm, Warp, cmux, Kaku, tmux, and Zellij. Workspace-level activation is supported for VS Code, Cursor, Windsurf, Trae, Zed, and JetBrains IDEs.

## ZCode and WorkBuddy

These integrations are maintained as first-class AIsland features:

- **ZCode** stores hooks under `~/.zcode/cli/config.json`. AIsland carries the stable session ID, resolves it read-only through `~/.zcode/v2/tasks-index.sqlite`, selects the matching sidebar conversation through Accessibility, and verifies the resulting heading. If exact focus is unavailable, it falls back to the workspace window or app activation.
- **WorkBuddy** uses Claude-compatible hooks under `~/.workbuddy/settings.json`. AIsland follows the desktop app's liveness and uses WorkBuddy's own `workbuddy://chat/<session-id>` route to open the matching task conversation.

## Quick Start

### Download

Download the latest DMG from [GitHub Releases](https://github.com/SeanLiew523/aisland/releases), open it, and drag **AIsland** into **Applications**.

The initial releases are development builds and are not Apple-notarized. If macOS blocks the app, open **System Settings → Privacy & Security → Open Anyway** for AIsland. For a quarantined local build, you can also run:

```bash
xattr -dr com.apple.quarantine "/Applications/AIsland.app"
```

Requirements: macOS 14+; release automation builds a Universal app for Apple Silicon and Intel.

### Build from source

```bash
git clone https://github.com/SeanLiew523/aisland.git
cd aisland
swift build
swift run OpenIslandApp
```

To build the AIsland app, ZIP, and DMG locally:

```bash
OPEN_ISLAND_VERSION=0.1.0 zsh scripts/package-aisland.sh
```

Run the deterministic smoke harness with `zsh scripts/harness.sh smoke`.

The executable target names retain the `OpenIsland` prefix for compatibility with existing hooks and local data paths. The shipped app name is **AIsland**.

On first launch, use **Settings → Setup** to select the agents you want to connect. Hook installation happens only when requested there.

AIsland uses the compatible OpenIsland local bridge. Quit Agent Island or Alsland before launching AIsland. Their app files and preferences are not migrated automatically.

## How It Works

```text
coding agent
    ↓ hook event
OpenIslandHooks CLI
    ↓ local Unix socket
BridgeServer → session state → AIsland UI
    ↓ click
terminal / IDE / exact desktop conversation
```

The repository is a Swift package with four main targets:

| Target | Role |
|---|---|
| `OpenIslandApp` | SwiftUI/AppKit app, menu bar, overlay, settings, jump-back |
| `OpenIslandCore` | Models, bridge protocol, installers, discovery, persistence |
| `OpenIslandHooks` | Lightweight hook process that forwards events locally |
| `OpenIslandSetup` | CLI for installing and removing managed integrations |

See [Architecture](docs/architecture.md), [Hooks](docs/hooks.md), and [Packaging](docs/packaging.md) for implementation details.

## Project Direction

AIsland intentionally develops outside the upstream fork network. The current priorities are:

- reliable ZCode and WorkBuddy behavior on real desktop sessions;
- low-noise, reviewable hook management;
- precise jump-back instead of app activation alone;
- native macOS interaction and stable local permissions;
- user-directed features without a cloud dependency.

## Contributing

Issues and pull requests are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md) and keep changes incremental, reviewable, and verified on the runtime they affect.

## Contributors

<table>
  <tr>
    <td align="center" width="160">
      <a href="https://github.com/SeanLiew523"><img src="https://avatars.githubusercontent.com/u/208326784?v=4&amp;s=128" width="64" height="64" alt="SeanLiew523"></a><br>
      <a href="https://github.com/SeanLiew523"><strong>SeanLiew523</strong></a><br>
      <sub>Project maintainer</sub>
    </td>
    <td align="center" width="160">
      <a href="https://chatgpt.com/"><img src="https://images.ctfassets.net/j22is2dtoxu1/intercom-img-d177d076c9a5453052925143/49d5d812b0a6fcc20a14faa8c629d9fb/icon-ios-1024_401x.png?fm=webp&amp;q=80&amp;w=128" width="64" height="64" alt="ChatGPT"></a><br>
      <a href="https://chatgpt.com/"><strong>ChatGPT / Codex</strong></a><br>
      <sub>AI development assistant</sub>
    </td>
  </tr>
</table>

## License and Credits

AIsland is distributed under the [GNU General Public License v3.0](LICENSE).

It is derived from [Open Island](https://github.com/Octane0411/open-vibe-island). Original copyright and license notices are retained, and the upstream authors are credited for their work. AIsland's independent adaptations, as of October 2, 2026, include its C1 branding, native status character, and ZCode / WorkBuddy integrations. AIsland is not an official Open Island release.

The native status character adapts [bloub](https://github.com/jeremy-prt/bloub) under its [MIT license](docs/licenses/bloub-MIT.txt).
