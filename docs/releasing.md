# Releasing AIsland

AIsland uses Semantic Versioning and publishes GitHub Releases from `v*` tags on `main`.

## Versioning

- **Patch** (`0.1.x`): bug fixes, documentation, and small improvements
- **Minor** (`0.x.0`): new compatible features
- **Major** (`x.0.0`): intentionally breaking changes or migration boundaries

## Current release pipeline

The workflow at `.github/workflows/release.yml`:

1. checks out the tagged commit;
2. builds Universal `OpenIslandApp`, `OpenIslandHooks`, and `OpenIslandSetup` binaries;
3. packages them as **AIsland.app**, **AIsland.zip**, and **AIsland.dmg**;
4. verifies bundle identity, version, structure, and code signature;
5. publishes a GitHub Release with DMG, ZIP, `SHA256SUMS.txt` and `release-metadata.json`.

Public releases currently use ad-hoc signing and disable Sparkle updates. They are not Apple-notarized. This avoids reusing Open Island's signing identity, appcast, or updater key while AIsland establishes its own release credentials.

## Release checklist

1. Confirm all intended changes are merged into `main` and CI is green.
2. Review the diff since the previous AIsland tag.
3. Update user-facing documentation and `.github/RELEASE_TEMPLATE.md` when installation behavior changes.
4. Create and push an annotated tag:

   ```bash
   git switch main
   git pull --ff-only
   git tag -a v<version> -m "AIsland v<version>"
   git push origin v<version>
   ```

5. Wait for the `Release` workflow to finish.
6. Verify that the GitHub Release is not a draft and contains the app archives, checksum file and exact-source metadata.
7. Compare the published asset digests with the workflow output.

## Local package verification

To build the same product identity locally:

```bash
OPEN_ISLAND_VERSION=<version> zsh scripts/package-aisland.sh
```

This writes artifacts under `output/aisland/`. Public packaging defaults to ad-hoc signing. Local developers may explicitly provide an existing identity; no certificate or system setting is created or changed.

## Release notes

Release notes should be bilingual and lead with user impact. Use this structure:

```markdown
## AIsland v<version> — Short title

One-paragraph English summary.
一段中文摘要。

### Highlights | 主要变化

- **Feature**: English description
  中文描述

### Installation | 安装

1. Download **AIsland.dmg** and drag **AIsland** to **Applications**.
   下载 **AIsland.dmg**，并将 **AIsland** 拖入 **Applications**。
2. Requires macOS 14+.
   需要 macOS 14+。
```

## Sparkle boundary

`appcast.xml` points only to `SeanLiew523/aisland` and intentionally has no release entries yet. Do not enable updates until AIsland has:

- its own Developer ID and notarization credentials;
- its own Sparkle EdDSA key pair;
- a verified appcast entry referencing an AIsland ZIP;
- an upgrade test from an already installed AIsland version.

Once those conditions are satisfied, enable the feed in packaging, update `scripts/update-appcast.sh`, and document the key and rollback process without committing private credentials.

## Upstream releases

Open Island version numbers and release artifacts are not AIsland releases. Upstream changes may be reviewed and integrated manually under [upstream.md](upstream.md), but they do not advance AIsland's version or appcast automatically.

## Website download contract

The public page at https://seanliew523.github.io/aisland/ is deployed from
`aisland-website/dist` by the Website workflow. Every download button uses
`https://github.com/SeanLiew523/aisland/releases/latest/download/AIsland.dmg`.
Keep this asset name stable in future releases. After publishing, download both
archives and metadata, compare SHA-256 with the GitHub asset digests, and inspect
the mounted DMG identity. Existing Sites hosting keeps its audience and uses the
same static output; it does not embed or independently replace a binary.
