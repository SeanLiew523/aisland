# MiniMaxCode passive source adapter

This package observes user-owned MiniMaxCode sessions. It never runs `mcode`,
starts tasks, hosts exec/ACP, changes source permissions, or replies to questions.
Desktop is first; CLI installation stays gated until desktop runtime acceptance.

Supported source baselines: MiniMaxCode desktop 3.1.0 / bundle 3.1.0.176
(`com.minimax.agent`) and MiniMaxCode CLI `mcode` 0.5.3. A version update requires
rechecking the source hook/ingress contract and native metadata reader. A copied
version number in `config.json` is a configured contract guard. Each native Hook
additionally proves the actual source through process metadata before emitting.

## Native package and wire contract

Copy only `.minimax-plugin/plugin.json`, `hooks/hooks.json`, `scripts/core.mjs`,
`scripts/source.mjs`, `scripts/hook.mjs`, and `icon.png` to the actual source
`<dataDir>/plugins/aisland-minimaxcode-passive/`. The native local-directory watcher
rescans that root; source recognition and explicit enablement still need real UI
verification. Do not symlink the repository or modify installed source packages.
Use an absolute verified Node interpreter in the rendered hook commands; the
source safe environment does not guarantee Node or inherit AIsland socket paths.

Write the reviewed `config.json` next to the manifest directory. Required fields
are in `config.example.json`. Set `sourceRuntimeVersion` to the verified baseline,
`profileID` to the source-specific profile identity, and `metadataDatabasePath` to
that same source data directory's `v2/sqlite/runtime-state.sqlite`. Desktop dataDir
defaults to `~/.minimax`; explicit `MINIMAX_DATA_DIR`, `MAVIS_DATA_DIR`, custom data
parent, and profile selection can change it. Inspect the selected active directory;
do not assume the default. Desktop and CLI can share this same plugin/dataDir;
the configured `source` does not determine the observed runtime.

Compile the reviewable `scripts/source-probe.swift` outside the native plugin
directory with `swiftc -O <source> -o <owned-helper>`. Native plugin packages do
not need a bundled executable. Add this required discovery configuration:

```json
{"sourceDiscovery":{"probePath":"/absolute/owned/source-probe","desktopAppPath":"/Applications/MiniMax Code.app","cliPrefix":"/Users/example/.minimax-code","allowedSources":["minimaxCodeDesktop"],"profileIDs":{"minimaxCodeDesktop":"desktop","minimaxCodeCLI":"cli"}}}
```

The installer must validate its owned helper and preflight it once using its own
PID and the app path. macOS first-launch validation can exceed the Hook's 200 ms
probe deadline. Preflight reads metadata only. Allow CLI only after real desktop
acceptance by adding `minimaxCodeCLI` to `allowedSources`; a proven CLI remains
silent while gated, and cannot fall back to Desktop.

The helper walks at most 16 ancestors, reading only PID, parent PID, executable
path, kernel birth time and controlling TTY. Desktop proof requires a canonical
application path plus actual `com.minimax.agent` bundle/version 3.1.0. CLI proof
requires the installed public `@minimax-ai/code` package version 0.5.3 and its
native `<cliPrefix>/.mcode-active/<ancestorPID>.json` marker. Marker PID must match
that exact ancestor and its timestamp must fall between kernel birth and Hook
birth, preventing stale PID reuse. Only exact ancestor markers are read, each
capped at 1 KiB; symlinks and nonregular files are rejected. The Hook process is
skipped because its interpreter can come from either application. A nearer CLI
proof wins when `mcode` runs inside Desktop's terminal. Unknown Node ancestors,
missing markers, source-version drift or unavailable helper produce no event.
Neither helper nor adapter reads process argv/environment, task content or auth.

The adapter emits newline-delimited local bridge commands:

```json
{"type":"command","command":{"type":"processRuntimeLifecycleHook","runtimeLifecycleHook":{"source":"minimaxCodeDesktop","event":"sessionObserved","profile_id":"desktop","session_id":"native-session","turn_id":"native-turn","cwd":"/source/workspace","timestamp":1000,"metadata_database_path":"/source/dataDir/v2/sqlite/runtime-state.sqlite","app_bundle_id":"com.minimax.agent","app_conversation_id":"native-session","terminal_app":"MiniMax Code.app"}}}
```

`SessionStart`, `UserPromptSubmit`, and `Stop` emit `sessionObserved`; it is
nonterminal and may omit `turn_id`. `SessionEnd` emits `sessionEnded`, representing
release/archive/logout/idle, never successful completion. Missing IDs are not
invented. `Stop` has no success semantics because a subsequent Hook can continue
the same turn. Source native metadata monitoring resolves actual accepted/final
states; the Hook command never reads SQLite itself.

Only known metadata fields are copied. Prompts, transcript paths, assistant
messages, tool names/arguments/results, model configuration, and error bodies are
discarded. stdin is capped at 1 MiB. Hook outputs are empty and exit 0, including
malformed input, unavailable bridge and missing configuration. Delivery has a
150 ms default deadline (configurable 10–300 ms), no retry/replay and no queue.
Transport delivery alone is not bridge admission or task acceptance.

## Read-only committed-result contract

Desktop source `dist/infra/db/schema/turn.js` defines
`local_runtime_turn_ingress` status `accepted`, `completed`, `failed`, or `aborted`.
`dist/service/turn-system/persistence/turn.repository.js` settles the matching
`turn_id` + `session_id` while still `accepted`, verifies ownership and releases
the lease in the same transaction. The CLI 0.5.3 bundle contains the same table,
path and settlement contract.

The native reader owns the following bound query over Hook-observed identity:

```sql
SELECT turn_id, session_id, status, accepted_at_ms, accepted_sequence, completed_at_ms
FROM local_runtime_turn_ingress
WHERE session_id = ? AND turn_id = ?
LIMIT 1;
```

Open read-only with file-must-exist semantics; check only this table's schema and
required column types before reading. Never select `*`, `input_json`,
`input_metadata_json`, `input_digest`, message tables, credentials, or unrelated
session rows. Optional native-ID discovery must remain within the observed session
and its admission time, then pin the exact turn; no unfiltered database scan.
Use committed `completed_at_ms` for final timestamps. A terminal row from before
admission, a replayed start, stale different turn, or bridge restart cannot create
a new success notification. Disconnection, source process exit and idle are not
successful outcomes. Schema mismatch or missing DB remains an explicit gap.

The global Events SSE has committed lifecycle events, but no server-side session
or event filter. Desktop localhost HTTP is a diagnostic-only optional sidecar;
production renderer uses private MessagePort. This package uses neither route.

## Install/remove review plan

`node plan.mjs '<JSON inputs>'` prints a plan only. Inputs:
`source`, `profileID`, absolute `dataDir`, absolute `bridgeSocketPath`, and absolute
`nodePath`. The existing dry-run plan describes the package/config skeleton;
the installer must add `scripts/source.mjs`, compile/preflight the external
helper and add `sourceDiscovery` before it is usable. CLI also requires the caller to supply `desktopVerified: true` after
actual desktop acceptance; the flag does not constitute acceptance evidence.

Before installation, record active source dataDir/version, chosen Node executable,
owned destination state and any exact backup. Refuse to overwrite an unknown
existing destination. Copy regular package files only, write `config.json` and the
rendered Hook document, preserve other plugins, and explicitly enable only this
plugin in MiniMaxCode. Main source/runtime installer owns these reversible changes.
Remove by disabling this plugin and deleting only its recorded owned installation;
restore the previous exact backup when applicable. Preserve source database,
source sessions, source plugin data and all unrelated profile files. Remove only
the separately recorded owned helper as part of rollback.

## Navigation and remaining runtime checks

`app_conversation_id` is the exact native `session_id`; it is selection metadata,
not proof that the desktop selected it. There is no verified session-navigation
Deep Link contract in desktop 3.1.0. Main's Deep Link handler focuses a window and
broadcasts input; renderer's `navigate` listener consumes URL/payment parameters.
Do not fabricate a session URL or report application activation as exact selection.
The native navigator must prove selection through a supported source/UI contract
or expose unavailable navigation honestly. For CLI, the source ancestor's
controlling terminal becomes `terminal_tty`; a recognized original terminal app
ancestor becomes `terminal_app`. This association uses the normal user-started
`mcode` process, with no startup wrapper. Hook child TTY and safe-env alone do not
provide this identity. Exact pane selection still requires native UI validation;
never resume another `mcode` process as a substitute for selecting the original.

Run `npm test` and `npm run check` in this directory. Tests verify native-baseline
source schema, metadata projection, malformed inputs, absent native IDs, bounded
failure, shared-source classification/PID reuse and real command/socket delivery.
The compiled helper test reads its own test process metadata only. They do not replace live source loading,
normal/failed/aborted final results, Stop continuation, exact navigation, frontmost,
terminal association, restart recovery, or completion audio acceptance.
