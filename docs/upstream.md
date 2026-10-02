# Upstream Relationship

AIsland is an independent project derived from [Open Island](https://github.com/Octane0411/open-vibe-island). Its adaptations, as of October 2, 2026, include the C1 brand, native bloub status animations, and ZCode / WorkBuddy integrations.

## What independence means

- `SeanLiew523/aisland` is created as a standalone GitHub repository, not through GitHub's fork API.
- AIsland owns its `main` branch, issues, releases, roadmap, branding, and compatibility decisions.
- The public repository starts with the complete AIsland v0.1.0 source snapshot. Original copyright and license notices remain intact, and upstream authorship is acknowledged in the README and source files.
- The original GPL-3.0 license remains in force for AIsland and future distributed modifications.

## Compatibility boundary

The shipped product name is **AIsland**. Internal Swift targets, helper binaries, environment variables, Unix socket names, resource bundles, and previously installed hook markers may retain the `OpenIsland` or `open-island` spelling. Those values are compatibility identifiers, not product branding.

Renaming them requires an explicit migration plan covering existing configuration, hooks, local permissions, session data, and uninstall behavior.

## Taking upstream changes

Upstream changes are reviewed and integrated manually. Do not assume a new Open Island release should be merged wholesale. For each candidate change:

1. inspect its user impact and compatibility assumptions;
2. reconcile it with AIsland's ZCode and WorkBuddy behavior;
3. preserve AIsland branding and release identity;
4. run the repository's normal build, hook, packaging, and runtime checks;
5. land it through an AIsland feature branch and pull request.

AIsland-specific commits may be proposed upstream separately, but upstream acceptance is not a prerequisite for this project's development.
