# AIsland native-motion website

The AIsland website accompanies the independent public repository
https://github.com/SeanLiew523/aisland. Its public GitHub Pages address is
https://seanliew523.github.io/aisland/. The existing Sites deployment retains its
own audience and is updated from the same static output.

## Source and demonstration

The C1 / Curious Gaze icon matches the shipped application. Native footage was
captured from the previous Alsland bundle before public AIsland naming, using
production views, geometry and Core Animation presentation layers with example
sessions. The new public application retains those animations. Recording
provenance preserves the original source commit and identifies equivalent code
in this repository; sample approvals and navigation are not live-agent claims.

The 20-second video covers idle, thinking, approvals, answers, sessions and
completion. `media/demo-edit.json` removes long holds while preserving native
transitions and animation speed. It generates the video and player chapter times
together. The repository READMEs use separate English and Chinese native
recordings as looping 960 × 520 close-up GIFs; clicking them opens
https://aisland.brianliew.chatgpt.site/. The original recording and repeatable
export are documented in [README visual assets](../docs/images/readme/README.md).
Four native close-ups render `BloubLayerView` at 192 points / 384
pixels. Timing, colors and paths come from the production component; the footage
has no invented UI interpolation. Reduced Motion uses static status frames and
stops decorative animation. Apple wallpapers are composited behind native pixels;
source and export metadata live under `dist/assets/`.

## Download

Every download button points to:

https://github.com/SeanLiew523/aisland/releases/latest/download/AIsland.dmg

The release contains **AIsland.app**, with bundle ID `dev.aisland.app`, the C1
icon and live bloub style. It requires macOS 14+ and supports Apple Silicon and
Intel. The initial release is ad-hoc signed, not Apple-notarized. ZIP, checksums
and exact-source metadata are published beside the DMG. Binary packages are not
embedded in website source, so redeploying the site cannot serve an old trial
bundle; subsequent AIsland releases retain the same asset name.

## Reproduce media

With Swift, Python/Pillow and FFmpeg on a MacBook with a built-in notch:

```sh
python3 media/capture.py /path/to/aisland /path/to/recording --bundle-plist /path/to/AIsland.app/Contents/Info.plist
python3 media/compose.py /path/to/recording dist/assets
python3 media/extract-status.py /path/to/aisland /path/to/status-export dist/assets
```

Temporary native capture packages do not replace installed applications or
modify hook settings. The recorder uses example snapshots with bridge/discovery
disabled and sends no permission responses or session jumps.

To regenerate the current README GIFs from their committed masters, run
`sh scripts/export-readme-demo.sh en` and `sh scripts/export-readme-demo.sh zh`
from the repository root. The legacy
`compose.py --readme-gif` option generates the older Sonoma demonstration and
should not replace the approved English README recording.

## Preview and publishing

Run `python3 media/preview.py` and open http://127.0.0.1:4319/?style=matrix.
Use `--port` to choose another local preview port.
All three visual directions preserve playback position when switched. The
server supports video byte ranges. GitHub Pages deploys `aisland-website/dist`
from `main`; `.openai/hosting.json` identifies the separate existing Site.

The status component adapts [bloub](https://github.com/jeremy-prt/bloub) under
its included MIT notice. The tagline remains **All agents. One island.**
