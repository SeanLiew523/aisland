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

```sh
zsh scripts/build-aisland-app.sh --install
open -a "$HOME/Applications/AIsland.app"
```

The local installer creates a debug bundle from `OpenIslandApp`, `OpenIslandHooks`
and `OpenIslandSetup`. It embeds Sparkle, localized resources and license notices,
uses an existing local signing identity when available, and verifies the bundle.
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
