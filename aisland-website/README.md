# AIsland website

GitHub Pages at https://seanliew523.github.io/aisland/ serves the same reviewed
product homepage as https://aisland.brianliew.chatgpt.site/. It stays on the
GitHub Pages address rather than redirecting or embedding the other host.

## Published source

This snapshot matches Sites version 2, published from commit
`51812cf5dc08f8cb9ee8fcb22e7a83655e150537`. `site-source.json` records that
source and the SHA-256 of every imported file. The static output is copied
unchanged; all asset paths are relative, including fonts, native video, status
previews and the bundled animation runtimes, so they resolve under `/aisland/`.

The page uses the single cobalt direction with warm paper feature sections,
light Barlow Condensed typography and GitHub icon links. Chinese and English
page copy share the genuine English native recording. The native demo moves
and enlarges toward the center on desktop scroll, without changing its
playback time. The brand chapter loops scattered agents → orbit → one island
at the approved 1.5× rate, beginning when it enters view and pausing offscreen.
There are no theme selectors or pricing sections. Reduced Motion disables
scroll pinning and decorative animation, and uses static status previews.

GitHub Pages and Sites are separate deployments. This repository's workflow
publishes `dist` whenever its files change on `main`. Future Sites changes
need a new reviewed snapshot here; this update does not create an automatic
cross-host sync or alter the Sites deployment.

## Product and media

The C1 logo, native status previews, 20-second English video, three English
feature images and their provenance match the accepted Site. The recording
uses production AppKit/SwiftUI views at pinned app commit
`111b21950f2319213432e4464c3f6ee6862ff95b`, with example sessions supplied by
the existing debug snapshot API. Apple’s original Ventura wallpaper is
composited behind native pixels. The footage does not represent live
permissions or session jumps. See `dist/assets/capture-provenance.json` and
`dist/assets/status-provenance.json`.

The three original Chinese `native-*.png` captures are retained only for
`README.zh-CN.md`; the website uses the imported English `native-*-en.png`
files. The repository READMEs retain their separate English and Chinese
recordings and complete 960 × 612 GIFs. Their masters and exports are
documented in [README visual assets](../docs/images/readme/README.md).

The native status character and brand chapter adapt
[bloub](https://github.com/jeremy-prt/bloub) under the retained MIT license.
The brand engine's source and original attribution are in `src/vendor/bloub/`.
Fonts and GSAP / ScrollTrigger keep their original licenses and source notices
in `dist/assets/fonts/` and `dist/assets/vendor/`.

Every download button points to the current AIsland release asset:

https://github.com/SeanLiew523/aisland/releases/latest/download/AIsland.dmg

The project icon links open https://github.com/SeanLiew523/aisland. The app
requires macOS 14+, supports Apple Silicon and Intel, and the initial
development release is not Apple-notarized. Binary packages are served from
GitHub Releases rather than embedded in the website.

## Preview and build

The checked-in page needs no build to preview:

```sh
python3 aisland-website/media/preview.py --port 4327
```

Open http://127.0.0.1:4327/. The preview server supports video byte ranges.

To rebuild the brand chapter from its included TypeScript source:

```sh
cd aisland-website
npm ci
npm run build
```

The historical native capture scripts in `media/` are retained as capture
reference; they do not rebuild the currently published English master.
To regenerate the README GIFs from their committed, language-specific masters,
run `sh scripts/export-readme-demo.sh en` and
`sh scripts/export-readme-demo.sh zh` from the repository root.
