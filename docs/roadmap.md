# Roadmap

<a href="roadmap.zh-CN.md">中文</a> | <strong>English</strong>

AIsland is an independently maintained, community-oriented macOS control surface for local coding agents. The roadmap favors small end-to-end improvements that can be verified against the real agent and desktop runtime they affect.

Open an issue before starting a broad product or architecture change. Focused fixes and integration improvements can go directly to a pull request; see [CONTRIBUTING.md](../CONTRIBUTING.md).

## Focus Areas

| # | Area | Direction | Status |
|---|---|---|---|
| 1 | **ZCode and WorkBuddy** | Keep hook installation, session identity, liveness, and exact desktop conversation jump-back reliable as those products evolve. | Active |
| 2 | **Claude Code and Codex** | Preserve low-noise lifecycle reporting, supported interaction flows, usage visibility, and precise return paths across CLI and desktop surfaces. | Active |
| 3 | **Other coding agents** | Improve OpenCode, Gemini CLI, Qoder, Qwen Code, Factory, CodeBuddy, Cursor, Kimi CLI, Grok Build, Pi, and Oh My Pi through evidence from their real runtimes. | Ongoing |
| 4 | **Terminal and IDE jump-back** | Expand precise targeting without replacing a known-good exact route with generic app activation. | Ongoing |
| 5 | **Local reliability** | Make hook management, transcript discovery, process detection, Accessibility use, and failure recovery quieter and more predictable. | Active |
| 6 | **Native experience** | Improve the macOS UI, notifications, sound, animation, accessibility, and multi-display behavior. | Open |
| 7 | **Remote sessions and new surfaces** | Strengthen SSH workflows, then evaluate Apple Watch, iOS, voice, and notification reply as bounded slices. | Planned |
| 8 | **Release independence** | Establish AIsland signing, notarization, Sparkle identity, and sustainable release automation without inheriting upstream credentials. | Active |

**Status legend:** `Active` = current maintainer priority · `Ongoing` = supported area with incremental work · `Planned` = accepted direction, not a release commitment · `Open` = proposals and contributions welcome

## Boundaries

- macOS 14+ remains the supported platform.
- Integrations stay local-first and fail open when AIsland is unavailable.
- AIsland owns its release history and does not automatically mirror upstream releases.
- Internal `OpenIsland*` identifiers remain compatibility details until a dedicated migration is designed.

See [Product Scope](product.md) for the current supported matrix and [Upstream Relationship](upstream.md) for how upstream changes are evaluated.
