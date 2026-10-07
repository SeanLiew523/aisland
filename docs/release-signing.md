# Release signing and updates

Formal v0.1.1 packages use Developer ID Application signing and Hardened Runtime.
The committed public Ed25519 identity is `config/packaging/AIslandUpdates.json`;
its private key stays in the local login Keychain account
`dev.aisland.app.sparkle-v1`. No private key is stored in the repository, exported
by packaging, or uploaded to GitHub Actions. Do not regenerate or replace it
after shipping this identity: existing installations rely on its public key.

`package-aisland.sh` enables signed updates for formal packages by default.
It verifies the existing Keychain public identity before compiling. The app
and signed archive/feed must use the same committed public key. User initiation
is required: Settings checks GitHub's latest stable release, then one Download
and Install action downloads the verified ZIP, replaces the app and relaunches.
Automatic background checks/downloads remain disabled. Development and CI
packages explicitly disable updates and are not release artifacts.

Notarization remains an external Apple acceptance gate. Before public release,
staple the application, recreate/sign the final ZIP/feed, recreate/staple the
DMG and run `verify-aisland-package.py --require-notarized`. Both tickets and the
actual Gatekeeper assessment must pass. A pending Apple submission is not an
accepted or publicly installable release. v0.1.0 submissions/artifacts remain
owned by their separate notarization worktree and are not changed here.

The installed v0.1.0 build 5 disables Sparkle. Its first upgrade must be manual;
publishing a successor cannot alter that installed executable. Deleting only
the app does not reset welcome/setup preferences.

See [releasing.md](releasing.md) for packaging and publication.
