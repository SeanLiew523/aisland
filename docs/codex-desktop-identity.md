# Codex Desktop identity and conversation jump

Codex Desktop can report rollout source `vscode` while its originator is
`codex_work_desktop`. A hook may also omit `__CFBundleIdentifier` while retaining
`CODEX_INTERNAL_ORIGINATOR_OVERRIDE=Codex Desktop`. Treating the source alone as
the host produced `Unknown` targets, and later incomplete hooks could erase a
previously resolved `codex://threads/<id>` jump.

The Desktop originator recognition and periodic rollout recovery are adapted
from [upstream PR #690](https://github.com/Octane0411/open-vibe-island/pull/690),
reviewed at `86b50c3`. AIsland additionally preserves a resolved Desktop target
through incomplete hooks and repeated session starts, fills missing thread IDs
in existing caches, and keeps pending approvals/questions during rediscovery.
Explicit terminal or IDE hosts remain authoritative; a generic `vscode` source
does not establish a Desktop host.

The app-server executable is resolved from the selected `com.openai.codex`
bundle, supporting both the nested `CodexCLI.app` and older resource layout.
Modern `thread/loaded/list` returns thread IDs, whereas `thread/list` returns
thread objects. Loaded IDs are hydrated through metadata-only `thread/read`,
without resuming conversations. Legacy `threads` responses remain supported.
Structured sub-agent sources are decoded as unknown instead of failing an
entire list.

Regression coverage is in `CodexDesktopIdentityTests`,
`CodexDesktopDiscoveryTests`, `CodexAppServerCompatibilityTests`, and the
existing hook, rollout, and session-list suites. Run the relevant suites with
`scripts/test-clt.sh`; Command Line Tools need its Swift Testing framework flags.

Local installation uses the same `/Applications/AIsland.app` path and
`dev.aisland.app` identity, preserving settings. This validation branch does
not modify the original v0.1.0 archive already submitted for Apple notarization.
