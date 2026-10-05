# Ordinary startup recognition

## Claude hook cache identity

`ClaudeTrackedSessionRecord` persists the actual supported Claude hook-family `tool`, native ID, timestamps, complete Claude metadata and jump target. Missing legacy tool tags mean Claude Code; explicit unknown or non-family tags fail decoding/encoding rather than being relabeled. Demo, ended, synthetic and expired sessions are not written to the live cache. Ended and demo records are not restored; startup retains the existing 24-hour cutoff.

Restoring a record marks its attachment stale and does not assert process liveness or hook ownership. The ordinary process monitor remains responsible for confirming source availability. Cached timestamps are never refreshed to keep an old task alive. Existing ZCode/WorkBuddy app tags remain available to their current desktop liveness checks.

## Incremental startup discovery

Startup first reserves the Codex discovery single-flight on the main actor, then loads only local registries off it. The cache batch is applied before either transcript scanner starts. A single background producer then delivers each fully parsed Codex candidate followed by each fully parsed Claude candidate through an ordered stream. Existing array discovery callers, duplicate reduction, scan limits and transcript parsing retain their behavior.

Each batch applies on the main actor. Identities present before startup and identities receiving accepted runtime events during startup are protected, including same-transcript aliases. Cache-only identities remain eligible for source enrichment. Cache pruning always schedules persistence from the merged current state rather than writing a historical snapshot. Runtime heartbeat events receive the same protection. The protected set is released after history finishes.

The ordinary bridge and process monitor continue during history discovery. Only the periodic Codex array re-scan waits for startup history to finish, so it cannot occupy the scanner first and defeat per-file delivery. It resumes under the existing 10-second throttle afterwards.

This removes the all-files delivery barrier; it does not bound the parse time of a single large transcript, eliminate directory enumeration, or run Claude parsing concurrently with Codex. No partial tail is treated as proof of completion. No measured claim about the reported ten-minute delay is made.

## Verification boundary

`python3 scripts/test-startup-recognition-isolated.py` builds the production Core and complete startup coordinator in a temporary fixture package, using `scripts/test-clt.sh`. Tests inject synthetic registry/transcript paths and an empty archived-Codex index; no AppModel, preferences, installed source runtime, user transcript or actual app restart is used. Blocking fixtures prove cache application precedes scanner entry, the first discovered card appears while remaining scans are blocked, periodic re-scan yields before/during startup and resumes after it, and late history cannot replace live completion or native jump identity. Synthetic real transcript files verify both per-file callbacks, Codex single-flight and the existing array results. Desktop liveness fixtures extract the production ZCode/WorkBuddy loops verbatim, replacing only app-availability queries with explicit inputs; the original 600-second completion guard and two-poll missing-process grace remain intact.

Passing fixtures verifies the cache, startup ordering, merge and liveness contracts, not real source recognition after restart. AppModel startup/event wiring is not included in the lightweight fixture target; its normal integration build and a real app restart are separate acceptance steps.
