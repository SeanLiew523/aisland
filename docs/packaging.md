# Packaging

This repository can now produce a local macOS app bundle from the Swift package without requiring an Xcode project archive.

## Current Shape

- `zsh scripts/package-app.sh` builds `OpenIslandApp`, `OpenIslandHooks`, and `OpenIslandSetup` in release mode.
- The script creates `output/aisland/AIsland.app` by default.
- The bundle embeds helper binaries inside `Contents/Helpers/` so the app can still locate `OpenIslandHooks` after it leaves the repository checkout.
- The script also creates `output/aisland/AIsland.zip` and `output/aisland/AIsland.dmg` for local sharing or release upload.
- `zsh scripts/package-aisland.sh` is the opinionated local wrapper: it uses the AIsland name, bundle ID `dev.aisland.app`, disables upstream updates, and defaults to ad-hoc signing and Universal binaries.

## Ad-hoc First

If no signing identity is supplied, the script still works. It ad-hoc signs the app and its embedded code so macOS can load the bundle, but the result has no Developer ID trust and is not notarized.

Check whether signing identities are available with:

```bash
security find-identity -v -p codesigning
```

If that command reports `0 valid identities found`, packaging remains limited to ad-hoc output until a certificate is created in the Apple Developer account and imported into the login keychain.

### "AIsland is damaged and can't be opened"

This Gatekeeper error can appear when macOS quarantines an ad-hoc signed or un-notarized download. There are two paths:

**Option 1 — remove quarantine (internal/dev use only):**

```bash
xattr -dr com.apple.quarantine "/Applications/AIsland.app"
```

Or right-click the app → **Open** → click **Open** to bypass the block once.

**Option 2 — Developer ID sign and notarize:** follow the section below for a release that opens normally after download.

## Signing And Notarization

When a signing identity is available, pass it in with environment variables:

```bash
OPEN_ISLAND_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
zsh scripts/package-app.sh
```

The script signs the helper binaries and app bundle, then also signs the DMG itself (required for notarization). Entitlements are declared in `config/packaging/OpenIslandApp.entitlements`.

If a `notarytool` keychain profile is already stored, the same script notarizes and staples in the correct order (app bundle first so the stapled bundle is embedded in the DMG, then the DMG):

```bash
OPEN_ISLAND_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
OPEN_ISLAND_NOTARY_PROFILE="open-island-notary" \
zsh scripts/package-app.sh
```

That path expects `xcrun notarytool store-credentials` to have been run ahead of time.

## Optional Overrides

The script accepts these environment variables:

- `OPEN_ISLAND_APP_NAME`
- `OPEN_ISLAND_BUNDLE_ID`
- `OPEN_ISLAND_VERSION`
- `OPEN_ISLAND_BUILD_NUMBER`
- `OPEN_ISLAND_DISABLE_UPDATES` (defaults to `true`; enable only after AIsland owns and verifies its Sparkle identity)
- `OPEN_ISLAND_PACKAGE_ROOT`
- `OPEN_ISLAND_BUNDLE_DIR`
- `OPEN_ISLAND_ZIP_PATH`
- `OPEN_ISLAND_SIGN_IDENTITY`
- `OPEN_ISLAND_NOTARY_PROFILE`
