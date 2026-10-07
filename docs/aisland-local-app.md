# AIsland local live build

AIsland uses C1 / Curious Gaze: the original flat-top 160×64 notch silhouette,
two ivory capsule eyes angled eight degrees, and an internal blue notification
dot on a warm-paper macOS tile. This is the shipped icon, not a generated mockup.

## Icon source

Regenerate every macOS size directly from the native vector source:

```sh
swift scripts/generate-aisland-appicon.swift
iconutil -c icns Assets/Brand/AIsland/AIsland.iconset -o Assets/Brand/AIsland/AIsland.icns
```

The PNG, iconset and ICNS are committed. Routine packages use these exact assets.

## Build and install

Build an ordinary local app without installing or launching it:

```sh
zsh scripts/build-aisland-app.sh --version 0.1.1 --build-number 47 \
  --output output/normal-runtime-b47/AIsland.app
```

Add `--validate-only` to inspect the version, clean source SHA, output and runtime
mode without compiling, signing, creating output directories or installing.
The v0.1.1 development-line default is `0.1.1`; `OPEN_ISLAND_VERSION` overrides
that default. Build number defaults to the Git commit count, or
`OPEN_ISLAND_BUILD_NUMBER` when supplied. Explicit flags take precedence.
There is no hardcoded build 1. Existing output bundles are rejected rather than
overwritten; choose a fresh output path for each round. All build output must
remain under this checkout's `output/` directory, including after resolving
symlinks.

The source tree must be clean. Source commit and tracked input timestamps are
checked again after compilation and signing; a changed or reverted edit rejects
publication. The final plist records `AIslandSourceCommit`, exact version/build
and `en`/`zh-Hans`/`zh-Hant` localizations. This is the ordinary
`dev.aisland.app` runtime, with no runtime-acceptance, source-setup or updater
fixture markers. Starting it uses normal preferences, discovery and hooks;
building it does not start those services.

Installation remains an explicit separate option:

```sh
zsh scripts/build-aisland-app.sh --install
open -a "$HOME/Applications/AIsland.app"
```

The local installer creates a debug bundle from `OpenIslandApp`, `OpenIslandHooks`,
`OpenIslandSetup` and `MiniMaxCodeSourceProbe`. It embeds Sparkle, localized
resources and license notices. It requires the existing `Open Island Dev Local`
signing identity (or explicit `OPEN_ISLAND_SIGN_IDENTITY`) and verifies the
bundle; it never creates a key or silently falls back to ad-hoc signing.
It refuses to replace a different bundle or a running AIsland. Previous AIsland
builds are kept under ignored `output/aisland/backups/`.

## Release identity

Public packages come from `scripts/package-aisland.sh`, use release optimization,
and include Universal arm64/x86_64 app and helper binaries. The app name is
**AIsland**, bundle ID `dev.aisland.app`; `OpenIslandLiveBloubStyle=true` enables
the live status colors and native animations. `OpenIslandDisableUpdates=true`
disables automatic updates. The initial public release is
ad-hoc signed and not Apple-notarized.

Idle uses subtle gaze movement and occasional blinks. Thinking uses three pulsing
dots. Approval is pink and answers warm yellow, each with a blue notification
dot, gentle breathing and an approximately five-second blink. Preferences use
AIsland's own bundle domain. The Dock icon is visible on first launch and follows
later user choices.

The shipped bundle has no interactive-trial flag or forced harness scenario.
Normal discovery, hooks and bridge are active. Packaging does not install or
rewrite agent hooks. The local bridge uses the OpenIsland socket protocol. Run only one app
using that bridge at a time.

## Verification boundary

`scripts/verify-aisland-package.py` checks identity, both architectures in all
three executables, update isolation, resources, strict signatures, ZIP extraction
and the mounted DMG. GitHub CI runs the full harness on a full Xcode toolchain;
local Command Line Tools may not provide the Swift Testing/Foundation overlay.
A package launch test uses example data with its bridge disabled so it cannot
replace a running app's bridge. This checks package loading, not real approvals
or exact conversation navigation; those require live supported-agent sessions.
