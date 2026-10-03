# Review media sources

These assets are for the isolated AIsland onboarding effect review. The logo scene is a brand demonstration; it is not a supported-runtime or acceptance claim. Official marks remain their owners' marks. No user conversations or private task captures are included.

## Native demo

The native UI pixels come directly from the checked-in AIsland website snapshot:

- `aisland-website/dist/assets/native-demo-en.mp4`
- `docs/images/readme/native-demo-zh.mp4`
- `docs/images/readme/capture-provenance-zh.json` (retained here unchanged)
- `aisland-website/dist/assets/capture-provenance.json` (retained here unchanged)
- recorded native app commit `111b21950f2319213432e4464c3f6ee6862ff95b`

These are real AppKit/SwiftUI views with **example sessions** supplied by the debug snapshot API. No live approval was submitted and no real session jump occurred in the footage.

`../prepare-native-media.py` samples both published English and Chinese movies at its original 30 fps, crops the native panel and removes the surrounding Ventura wallpaper with a per-row alpha matte. Every retained task label, agent label, button, option and character comes from the recording; none is drawn anew. Stable in-points omit the original native expansion's overlapping and translucent frames. The remaining native animation plays at its original speed and then holds the last frame for the rest of the review scene. The closed pill uses source 0.05–1.35 seconds with crop `[1288,0,496,58]`: the actual character on the left and agent count grid on the right.

The original anti-aliased outer boundary is clipped with the wallpaper matte. `native-media.json` records exact source ranges, dimensions, pages and frame counts. Small PNG atlas pages are decoded and cropped into individual frame textures **before** the shared audio clock starts. One opaque native panel is revealed without crossfading a second island underneath. Static review / reduced motion uses a stable captured frame.

## Supplementary native task rows

The published list displays only Claude and Codex. Four rows for Claude, Codex, Gemini and WorkBuddy were additionally exported from the actual `IslandSessionRow` SwiftUI component, in English and Chinese, using `../native-capture/capture.py`. The renderer creates no window, `AppModel`, bridge, live session or approval callback. Language preference IO is replaced in the temporary capture source with an explicit capture locale; the row drawing code, native agent badge, fonts and colors remain production source. Demo task titles differ by agent and locale.

`native-row-manifest-{en,zh-Hans}.json` records the fixed example sessions, nil metadata/jump target, non-interactive callbacks and image dimensions. `native-row-provenance-{en,zh-Hans}.json` records extraction ranges, source SHA256, dependencies and image hashes. The recorded production source file hashes were compared with the current feature worktree and match. These are **new native component demo captures**, not frames previously published in the website movie and not real task results.

## Logo scene

Installed app icon resources were read without launching those apps, then converted to 128 px PNG for display:

| Mark | Installed original |
| --- | --- |
| Claude | `/Applications/Claude.app/Contents/Resources/electron.icns` |
| ChatGPT | `/Applications/ChatGPT.app/Contents/Resources/icon-chatgpt.png` |
| MiniMax Code | `/Applications/MiniMax Code.app/Contents/Resources/icon.icns` |
| ZCode | `/Applications/ZCode.app/Contents/Resources/icon.png` |
| WorkBuddy | `/Applications/WorkBuddy.app/Contents/Resources/icon.icns` |

Official web assets, retrieved 2026-10-03; PNG marks were reduced to 128 px, SVG paths are unmodified:

- [Gemini](https://gemini.google.com): [official icon](https://www.gstatic.com/lamda/images/gemini_sparkle_4g_512_lt_f94943af3be039176192d.png), URL read from the site's icon link.
- [Grok](https://grok.com): [official icon](https://grok.com/images/favicon.svg), URL read from the site's icon link.
- [Kimi](https://www.kimi.com): [official icon](https://www.kimi.com/pwa-192.png), URL read from the site's apple-touch-icon link.
- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/apps/web/public/favicon.svg): exact SVG from the official repository at that commit. [Official brand usage guidance](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15009ae1756c3afe0ae0cef1faafc290ccc/BRAND_GUIDELINES.md).

No logo is used as a substitute for task content. The nine-logo segment ends before the native task demonstration starts.
