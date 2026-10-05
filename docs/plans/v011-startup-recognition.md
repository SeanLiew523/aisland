# Ordinary startup recognition

## Claude hook cache identity

`ClaudeTrackedSessionRecord` persists the actual supported Claude hook-family `tool`, native ID, timestamps, complete Claude metadata and jump target. Missing legacy tool tags mean Claude Code; explicit unknown or non-family tags fail decoding/encoding rather than being relabeled. Demo, ended, synthetic and expired sessions are not written to the live cache. Ended and demo records are not restored; startup retains the existing 24-hour cutoff.

Restoring a record marks its attachment stale and does not assert process liveness or hook ownership. The ordinary process monitor remains responsible for confirming source availability. Cached timestamps are never refreshed to keep an old task alive. Existing ZCode/WorkBuddy app tags remain available to their current desktop liveness checks.

## Verification boundary

`python3 scripts/test-startup-recognition-isolated.py` builds the production Core and complete startup coordinator in a temporary fixture package, using `scripts/test-clt.sh`. Tests inject synthetic registry paths and an empty archived-Codex index; no AppModel, preferences, installed source runtime, user transcript or actual app restart is used. Passing fixtures verifies the cache and merge contracts, not real source recognition after restart.
