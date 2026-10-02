# Release Signing and Notarization

AIsland's initial public releases are ad-hoc signed, are not Apple-notarized, and have Sparkle updates disabled. The release workflow needs no Apple credentials in this phase. This keeps the independent project from reusing Open Island's signing certificate, notarization account, or update key.

The current package identity is:

- app name: `AIsland`
- bundle identifier: `dev.aisland.app`
- update mode: disabled
- distribution: GitHub Release DMG and ZIP

See [releasing.md](releasing.md) for the active release procedure.

## Moving to Developer ID Distribution

Treat signed distribution as a separate, reviewed migration. Before enabling it:

1. Choose a permanent AIsland bundle identifier.
2. Create a dedicated Developer ID Application certificate and notarization profile.
3. Generate an AIsland Sparkle EdDSA key pair and publish only the public key.
4. Decide how existing local permissions and installs migrate to the permanent identity.
5. Update packaging, CI, `appcast.xml`, and user documentation in one coherent change.
6. Verify the signed, notarized app on a clean macOS account before publishing it.

The likely GitHub secrets for that future workflow are:

| Secret | Purpose |
|---|---|
| `APPLE_CERTIFICATE_P12` | Base64-encoded AIsland Developer ID certificate |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the certificate archive |
| `APPLE_SIGNING_IDENTITY` | Developer ID signing identity |
| `APPLE_ID` | Apple account used by `notarytool` |
| `APPLE_TEAM_ID` | Apple Developer team identifier |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for notarization |

Do not add or enable these secrets until the packaging workflow has been updated to require and verify the new permanent identity. A successful ad-hoc build is not evidence of Developer ID signing or notarization.
