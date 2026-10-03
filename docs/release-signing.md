# Release Signing and Notarization

AIsland's initial public releases are ad-hoc signed, are not Apple-notarized, and have Sparkle updates disabled. The release workflow needs no Apple credentials in this phase. This keeps the independent project from reusing Open Island's signing certificate, notarization account, or update key.

The current package identity is:

- app name: `AIsland`
- bundle identifier: `dev.aisland.app`
- update mode: disabled
- distribution: GitHub Release DMG and ZIP

See [releasing.md](releasing.md) for the active release procedure.

## Moving to Developer ID Distribution

Developer ID distribution does not require an App Store listing. It requires an
active Apple Developer Program membership, a **Developer ID Application**
certificate with its matching private key, and notarization credentials. A Team
ID by itself is not a signing certificate or proof that membership is active.

Keep `dev.aisland.app` and version `0.1.0` for this migration so application
preferences continue using the existing domain. Keep Sparkle updates disabled;
notarization does not require an appcast, an updater key, or enabling updates.
macOS permissions may need confirmation after changing the signing identity.

### Prepare credentials locally

1. Use Keychain Access's Certificate Assistant to create a certificate signing
   request. Save the CSR to disk; the matching private key stays in Keychain.
2. In Apple's developer portal, use the intended team to create a **Developer ID
   Application** certificate from that CSR, then import the downloaded `.cer`
   into the same Mac's login keychain. Do not use Apple Development, Mac App
   Distribution, Developer ID Installer, or a self-signed local certificate.
3. Confirm the complete signing identity is listed by
   `security find-identity -v -p codesigning` with the intended Team ID.
4. Store a dedicated local notarization profile. Let the account holder enter an
   app-specific password in the secure interactive prompt, rather than putting
   it in command arguments, repository files, or chat:

   ```bash
   xcrun notarytool store-credentials aisland-notary \
     --apple-id '<developer-account-email>' --team-id '<TEAMID>'
   ```

   Alternatively, use an appropriately authorized App Store Connect API key.
   Neither credential method requires publishing an App Store app.

### Package and verify

```bash
OPEN_ISLAND_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
OPEN_ISLAND_TEAM_ID='<TEAMID>' \
OPEN_ISLAND_NOTARY_PROFILE='aisland-notary' \
OPEN_ISLAND_BUILD_NUMBER=1 \
OPEN_ISLAND_PACKAGE_ROOT="$PWD/output/aisland-notarized" \
zsh scripts/package-aisland.sh

python3 scripts/verify-aisland-package.py output/aisland-notarized \
  --require-notarized --team-id '<TEAMID>'
```

The packaging preflight rejects missing/local signing identities, an unexpected
team, disabled hardened runtime, and missing notarization credentials before
compiling or replacing output. Each submission must return `Accepted`; a zero
tool exit code alone is insufficient. Apple's submission result and diagnostic
log are retained beside each artifact as `.notary-result.json` and
`.notary-log.json`. Both app and DMG tickets are stapled and validated. The ZIP
is recreated from the stapled app.

The release verifier checks the Developer ID team, hardened runtime, secure
timestamps, all architecture signatures, stapled tickets, and Gatekeeper
assessment of the app and DMG. It also verifies the app inside the DMG and ZIP,
then records the verified signing team and actual notarization state in
`release-metadata.json`. The existing ad-hoc verification mode remains available
for local builds and current unsigned distribution; it must not be used as the
publication gate for a notarized release.

Keep current public downloads available until all notarized-package checks pass.
Back up the current release assets, replace the existing `v0.1.0` DMG, ZIP,
checksums and metadata together, then verify the public downloads. Before
claiming the normal first-launch experience, test an actual browser download on
a Mac/account with normal Gatekeeper checks and no previous AIsland exception.

Official instructions:

- [Create a CSR](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request)
- [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)
- [Notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

### Future CI credentials

Local signing and notarization do not require uploading private keys to GitHub.
The current release workflow remains ad-hoc. Before automating a signed release,
make its notarized verification gate mandatory and decide whether to authorize
GitHub to hold a dedicated distribution certificate and notarization credential.
The possible GitHub secrets for that separate workflow are:

| Secret | Purpose |
|---|---|
| `APPLE_CERTIFICATE_P12` | Base64-encoded AIsland Developer ID certificate |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the certificate archive |
| `APPLE_SIGNING_IDENTITY` | Developer ID signing identity |
| `APPLE_ID` | Apple account used by `notarytool` |
| `APPLE_TEAM_ID` | Apple Developer team identifier |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for notarization |

Do not add or enable these secrets until the release workflow requires the new
identity and `--require-notarized` verification. A successful ad-hoc build is not
evidence of Developer ID signing or notarization.
