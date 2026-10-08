# AIsland website

The approved Deep Ink homepage is served at both
https://aisland.brianliew.chatgpt.site/ and
https://seanliew523.github.io/aisland/. GitHub Pages keeps its own address;
it does not redirect or embed the other host.

## Published direction

Deep Ink is the only production design. Its graphite background, pale jade
headlines, paper content planes, technical meshes and native MacBook framing
match the approved `467eb00` preview. The comparison menu, other palettes,
preview-only copy and unused alternate artwork are excluded from production.
The `data-design="ink"` attribute is fixed; URL parameters cannot select
another direction. `site-source.json` records the matching Sites source
version and SHA-256 hashes of the published static files.

The first viewport presents the idle character in a sharp native notch
close-up. Scrolling starts the separate native demo immediately and pulls
back to the whole MacBook. Its sequence is Running → Answer → Approval →
Sessions → Done, played at 1.2×. The brand chapter loops scattered agents →
orbit → one island at the approved 1.5× rate. Background meshes stay in the
colored page shells and gutters, behind opaque content planes. Chinese and
English copy share the genuine English native recording. Reduced Motion
disables scroll pinning and decorative animation and uses static status images.

All asset paths are relative, so the same static output works at the Sites
root and beneath `/aisland/`. These are separate deployments: the GitHub
workflow publishes `dist` when its files change on `main`; Sites publishes
an identical archive. Future updates must keep both outputs in sync.

## Product and media

The high-density, alpha-native reveal recording retains the production
AppKit/SwiftUI views at pinned app commit
`111b21950f2319213432e4464c3f6ee6862ff95b`, with English example sessions
supplied by the existing debug snapshot API. Compact vector layers were
captured at 8×, with a separate 2× take for expanded native text. Apple's
original Ventura wallpaper is composited behind the native pixels.
The footage does not represent live permissions or session jumps.
See `dist/assets/reveal-capture-provenance.json`, `capture-provenance.json`
and `status-provenance.json` for source and media hashes.

The older English master and three original Chinese `native-*.png` captures
remain for the repository READMEs; their language-specific masters and GIFs
are documented in [README visual assets](../docs/images/readme/README.md).
Their content is independent of the website's high-density reveal footage.

The native status character and brand chapter adapt
[bloub](https://github.com/jeremy-prt/bloub) under the retained MIT license.
Original source and attribution remain in `src/vendor/bloub/`.
Barlow Condensed and GSAP / ScrollTrigger retain their licenses and source
notices in `dist/assets/fonts/` and `dist/assets/vendor/`.

Every download button uses the latest stable AIsland release asset:

https://github.com/SeanLiew523/aisland/releases/latest/download/AIsland.dmg

At publication, this resolves to v0.1.1's `AIsland.dmg` (42,471,002 bytes),
SHA-256 `ad3a83651994d5c31d4aaf010bb5a708a397f4bf2a76c9b5bed3a9d6c0ea7986`.
The package is Developer ID signed and Apple notarized, requires macOS 14+,
and supports Apple Silicon and Intel. Installers are served by GitHub Releases.

## Preview and build

The checked-in page needs no build to preview:

```sh
python3 aisland-website/media/preview.py --port 4327
```

Open http://127.0.0.1:4327/. The server supports video byte ranges.
To rebuild the included brand animation source:

```sh
cd aisland-website
npm ci
npm run build
```

After changing static CSS or JavaScript, refresh its content fingerprint in
`dist/index.html` so returning visitors receive the new entrypoints.
`media/compose-reveal.py` and `media/reveal-edit.json` document the native
reveal edit; the raw native frame takes are not included in this repository.
