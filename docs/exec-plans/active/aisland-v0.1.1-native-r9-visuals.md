# Native R9 visual synchronization

2026-10-04. Status: `IMPLEMENTED_OFFSCREEN_VERIFIED`; actual native fullscreen
acceptance belongs to the root flow. User approved the ninth visual revision
and requested the eighth revision's sound. This approval supersedes the earlier
V6-only synchronization gate. Existing V6/R5 rollback tags are preserved.

Worktree: `aisland-v0.1.1-native-r9`, branch `feat/v0.1.1-native-r9`, based on
root `54c4492b615f86a8d9dd05812aeac7fe67f5a4fd`. This slice changes native scene
geometry/media, new brand resources and visual verification only. It does not
change audio, prototype, controller/mandatory policy, acceptance configuration,
builder, coordinator, AppModel, source configuration or user settings. No GUI,
full App build, package, install or real task operation was performed.

## Result

`OnboardingSceneView` retains the existing island shell/proportions, logo
gathering, four actual recorded demo task rows and native task panels. Their
drawing methods remain byte-identical to the starting source. Task content
continues to be example UI rather than real runtime/source acceptance evidence.
All introduction titles are removed; task UI strings and the noninteractive
AIsland corner brand remain. The mandatory presentation already has no review
controls and is unchanged here.

At 5.3 seconds, a genuine site Bloub idle character appears only in the left
space of the existing pill, centered at `island.midX - island.width*.35`,
`island.midY`, with size `island.height*.82`. At 7.95 seconds, the last task has
arrived and this character changes to the site's thinking/running three dots.
It disappears at the original 8.2-second approval transition. No pill replacement
or new right-wing count grid was introduced.

The island starts its existing ascent at 18.1 seconds. The original site's orbit
triangle-to-sphere character appears separately at 18.9 seconds, centered at
`(viewportWidth/2, viewportHeight*.55)`, diameter
`min(viewportWidth*.68,viewportHeight*.66)*.7`. Opacity rises over .35 seconds.
Its original 0–3.3-second engine motion is sampled at 1.1x, matching R9. At
1702×1016 the diameter is 469.392 points; narrow 380×500 uses 180.88 points.
Screen/size changes recompute geometry even at a frozen time. Reduced motion
uses the same approved idle/thinking 1-second and orbit 2.5-second still poses.

## Exact original-engine sprite source

`scripts/generate-onboarding-r9-visuals.cjs` executes the actual approved local
`intro-bloub.js` adapter and engine's SVG painter offline. It does not draw a
new silhouette, blend screenshots, fetch the website, run a WebView or execute
JavaScript in production. Original mask/layer order, gradients, eyes, colors
and arcs are rasterized to transparent PNG; native CGContext draws these PNGs.
Original Bloub MIT attribution is retained as `bloub-MIT.txt`.

There are 191 PNGs: 80 idle + 8 thinking at 256×256, 100 orbit at 1024×1024,
plus three reduced-motion stills. Original state motion is sampled at 30 Hz,
the prototype's cache cadence; each sample holds until the next tick. Native
uses absolute scene ticks for glyphs and engine source ticks for orbit.
Thinking enters halfway through tick 238 at 7.95 seconds, then the next frame
starts at 239/30 = 7.96667, rather than incorrectly restarting its tick clock.
The prototype can sample within a tick on its first RAF; native raster sampling
fixes the exact tick boundary, so phase quantization is bounded by one 30 Hz
sample. This is a native sprite implementation, not a continuous vector engine
port, and is not presented as pixel identity for arbitrary sub-frame times.

`OnboardingBrandMedia` preloads compressed frame bytes, validates dimensions
before presentation, and decodes only the selected frame. It keeps one current
motion image per sequence plus the three stills. This avoids retaining all
100 expanded orbit textures (roughly 400 MiB at 1024² RGBA). Compressed motion
bytes total 26,530,790; resource file size is approximately 26 MiB. The cache
bound is an owned-object bound, not an assertion about macOS/GPU total memory.

## Machine-readable builder handoff

Paths under `Sources/OpenIslandApp/Resources/Onboarding/`:

- `bloub-r9.json`: `revision:9`, `fps:30`, and
  `sequences.{idle,thinking,orbit}` containing `sampleStart`, `sampleStep`,
  `width`, `height`, `files`, `stillFile`, `stillTime`.
- `bloub-r9-provenance.json`: `revision`, approved-visual description,
  `sourceCommit`, `source_files_sha256`, `manifest_file`, `manifest_sha256`,
  `generated_files_sha256` (all 191 PNG filenames/hashes), `geometry`, `timing`,
  `sampling`, `cache`, `scope`. Source hashes include the actual adapter/bundle,
  site's SVG painter/vendor engine, generator and MIT file. It deliberately
  excludes audio and any private runtime/session content.
- `bloub-MIT.txt`: byte-identical to the prototype's original license.

The builder should retain all existing V6 byte checks for task footage/logos/
rows and `native-media.json`, then validate this separate approved R9 visual
manifest, its geometry/time contract, source hashes and generated inventory.
Old `native-media.json`, task PNGs and the WAV are untouched. Root handles
restoring the R8 score; no new R9 contact sound is synchronized by this slice.

## Verification

Reproducible commands:

```sh
NODE_PATH=/Users/seanliew/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules node scripts/generate-onboarding-r9-visuals.cjs
AISLAND_ONBOARDING_FRAME_DIRECTORY=/Users/seanliew/aisland-v0.1.1-native-r9/output/verification/native-r9-visuals python3 scripts/test-onboarding-r9-isolated.py
```

The established disposable-package runner copies real production source and
resources unchanged. The new wrapper adds the three R9 tests without changing
the shared runner. Temporary package cleanup completes automatically.

Final result: **14 tests in four suites passed**, including three new visual
tests and the existing clock, media, first-launch, language, replay and mandatory
policy checks. New checks cover all four viewport sizes and same-time resize,
idle→thinking boundaries, orbit start/end, reduced motion, all 191 generated PNG
hashes and manifest hash, actual frame decode/caching, absence of localized
opening title pixels, and 32 new native offscreen pose images across zh/en,
wide/narrow and normal/reduced motion. The two opening locale images are pixel
equal, while the task scenes continue using their respective recorded language.

Additional checks read the actual rendered PNGs and verify the character pixels
at native geometry centers in all 32 combinations. Source inspection verifies
unchanged original background/logo/row/panel/closed/island drawing methods;
all generator/source/image hashes are current. `git diff --check` passes.

For 188 real ImageIO decodes, observed p95 is 9.13 ms and maximum 9.39 ms on this
machine. This measures CPU frame decode in the isolated test, not actual native
60 Hz window/GPU playback. The first run exposed two fixture assumptions:
literal 18.9 differs from `18.1 + .8` at floating-point precision, and compressed
frames exceed a guessed 20 MiB threshold. Fixtures now use the actual start
constant and a 32 MiB package ceiling; final tests pass. The half-tick thinking
clock was separately corrected and tested at 7.95/7.96667/8.0 seconds.

Local evidence: `output/verification/native-r9-visuals/isolated-tests.log`,
`visual-checks.json`, 32 `r9-*.png`, two opening renders and existing whole-scene
renders. They are ignored artifacts, not committed user captures.

Actual built-app fullscreen timing, smoothness, hardware-notch alignment,
restored audio/visual synchronization and first/second-launch end-to-end flows
remain for root's native acceptance. Approved prototype visuals and offscreen
checks do not substitute for those live results.
