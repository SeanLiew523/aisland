# Releasing AIsland

Formal releases are locally prepared Universal Developer ID packages with an
AIsland-signed update archive and signed `appcast.xml`. CI smoke packages remain
ad-hoc and update-disabled. Keep the stable names `AIsland.dmg`, `AIsland.zip`,
`appcast.xml`, `SHA256SUMS.txt` and `release-metadata.json`.

## Build

Commit the feature branch before packaging and choose a fresh output directory:

```zsh
OPEN_ISLAND_VERSION=0.1.1 OPEN_ISLAND_BUILD_NUMBER=87 \
OPEN_ISLAND_PACKAGE_ROOT="$PWD/output/releases/v0.1.1-build87" \
zsh scripts/package-aisland.sh
python3 scripts/verify-aisland-package.py output/releases/v0.1.1-build87
```

The builder uses the committed public identity and its dedicated existing
Keychain account. It never creates, exports or uploads a private key. It signs
the complete app/ZIP/DMG and produces the exact signed per-release feed.
Keep source/build numbers increasing. Local developer builders continue to
disable updates so public versions cannot overwrite branch fixes.

## Notarization and final verification

For synchronous Apple submission, explicitly pass
`OPEN_ISLAND_NOTARY_PROFILE=aisland-notary` while packaging. Apple may take an
unbounded time; for an asynchronous submission, preserve the candidate, submit
its ZIP without `--wait`, and record the returned job ID. Do not publish while
Apple acceptance is pending. Once accepted, staple the app, rebuild the ZIP and
DMG from that stapled app, regenerate the signed feed for the final ZIP bytes,
and staple the DMG after its own Apple acceptance. Never change a signed ZIP
without re-signing its enclosure and feed.

```zsh
python3 scripts/verify-aisland-package.py output/releases/v0.1.1-build87 \
  --require-notarized --expected-source <exact-packaged-commit>
```

Verification checks Universal app/helpers, bundle identity, strict signatures,
mounted DMG and extracted ZIP, exact build/source/feed URL, cryptographic archive
and feed signatures using only the public key, both notarization tickets and
Gatekeeper. The generated metadata records actual notarization rather than a
fixed false/true value; SHA256SUMS includes the signed feed.

## Publish

Integrate through a PR targeting main and tag the exact packaged source commit
after confirming it is an ancestor of main. Prepare a draft GitHub Release with
all five verified assets and bilingual release notes. Dispatch the `Release`
workflow with that existing tag. It downloads/checks the complete prepared
assets, verifies exact source and notarization, then publishes the draft as
latest. It cannot rebuild unsigned replacements or access local private keys.
Verify public downloads and their digests after publication.

Settings first queries GitHub's stable-release metadata, then uses that same
release's `appcast.xml` asset. The bundle fallback URL is the latest-release
asset; the old repository `appcast.xml` is not the active delivery contract.
No local fixture is evidence of a published upgrade. Actual update verification
can copy the release executable/resources with `prepare-updater-app-fixture.py
--prepare-release <release.app>` into a random isolated domain and test through
Settings; it never modifies the installed app or grants production loopback
overrides. Corrupt archive/feed rejection must remain effective.

v0.1.0 build 5 has updates disabled and requires one manual upgrade. v0.1.1
supports Settings → Check for Updates → Download and Install → automatic
relaunch for subsequent compatible signed releases. Reinstalling the app alone
retains first-run preferences; use a fresh profile for automatic-welcome tests.

The public website download remains
`https://github.com/SeanLiew523/aisland/releases/latest/download/AIsland.dmg`.
