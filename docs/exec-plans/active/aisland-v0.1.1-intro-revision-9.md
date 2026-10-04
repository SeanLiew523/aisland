# v0.1.1 intro R9 — smaller home character and distinct contact sound

Date: 2026-10-04. Status: `READY_FOR_VISUAL_AND_AUDIO_REVIEW`.

**Superseded review gate:** the user approved R9 visuals on 2026-10-04 and
requested R8 home audio, then authorized native synchronization, a new full App
build and remaining tests. See `v0.1.1-approved-r9-r8-native.md` for the current
contract. The rejected R9 contact sound and its historical measurements below
remain evidence of that earlier review, not the final audio acceptance target.

This prototype starts from `feat/v0.1.1` at `11037b9`. R8 and R9 remain
unapproved. The approved V6 tag and production onboarding media are untouched.
No formal app build, native synchronization, source configuration changes or
GUI operation was performed in this round.

## Requested slice

The home character's diameter is exactly 70% of R8:
`min(width * .68, height * .66) * .7`. Its center remains
`(width / 2, height * .55)`. The unchanged original website Bloub `orbit` state
still morphs from triangle to sphere, using the same SVG masks/layer order and
0–3.3-second engine sample fitted to the last three seconds. The island shell,
four task cards, left-wing character, 22-second timeline and setup flow remain
unchanged. Review labels identify revision 09 in both languages.

At 1702 × 1016, diameter changes from 670.56 to 469.392 pixels; at 380 × 500,
258.4 to 180.88 pixels. The same-time resize cache still includes geometry.
Reduced motion retains its original static 2.5-second engine pose.

The old three swelling/breathing dock layers and two settled sounds are replaced
by one original deterministic stereo PCM contact sequence. Short damped
inharmonic resonances descend in pitch as contacts slow down and stereo width
narrows. The final contact is centered and slightly stronger, giving the home
gesture a physical landing instead of another sustained pad. This description
is an implementation intent; subjective sound quality requires actual audition.

Key times:

- 18.1 s: dock sound begins, coinciding with the island's existing ascent.
- 18.1–20.02 s: seven short contacts at relative times
  0, .12, .29, .53, .87, 1.33 and 1.92 seconds.
- 18.9 s: unchanged central orbit character appears.
- 20.7 s: final low, centered contact, matching `settled`.
- 21.4 s: final contact envelope reaches zero; source stops at 21.5 s.
- 22 s: unchanged introduction ends.

All cues before 18.1 s remain structurally equal to approved V6, including
frequency, envelope, volume, pan and stop time. Original `tone`, `air`, `swell`,
master gain .7, compressor and event-sound implementations are unchanged.

## Source and native handoff

Visual source remains `aisland-website/src/vendor/bloub/*` and the site's
`integrated-motion.ts` SVG painter. `assets/intro-bloub-source.json` records
their hashes, adapter hash and rebuilt esbuild 0.25.11 bundle hash. No new
silhouette, screenshot blend or external asset was introduced.

`intro-audio.js` exports `dockPCM(sampleRate, length, volume, settleOffset)`,
which returns two Float32 channel arrays. The browser's new `dock` primitive
copies those exact arrays into an AudioBuffer, connects it to the existing
master, and tracks/stops the BufferSource in the ordinary intro lifecycle.
`assets/intro-audio-source.json` records the new original sound and source hashes.

Repository inspection found `prepare-native-media.py` generates visual atlases
only. Native `PROVENANCE.md` documents that V6 WAV was rendered through
OfflineAudioContext, but no callable full-score audio generation script is
checked in. Root's later native rendering must add the `dock` buffer primitive
using these same arrays to its existing OfflineAudioContext graph, supply
`{tone, air, swell, dock}` to `schedule`, render the full 22-second score with
unchanged .7 master/compressor settings, quantize PCM16, and update native media
provenance. The new API explicitly rejects a missing dock implementation, so a
renderer cannot silently omit the home sound. Do this only after user approval.

The local 3.4-second WAV excerpt is the shared 48 kHz PCM scaled by .7. It omits
the compressor and every other cue. It is an audition aid, not native/full-score
evidence. No production WAV or Swift renderer changed.

## Offline verification

Commands, from the R9 worktree:

```sh
npm exec --offline --package=esbuild@0.25.11 -- esbuild prototypes/v0.1.1-review/intro-bloub.ts --bundle --format=iife --target=es2022 --outfile=prototypes/v0.1.1-review/assets/intro-bloub.js
NODE_PATH=/Users/seanliew/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules node prototypes/v0.1.1-review/verify-r9.cjs
```

`verify-r9.cjs` replaces R8's check and passes:

- Six same-time window → fullscreen-size → window checks, with normal/reduced
  motion, exact .7 diameter and unchanged center.
- Six actual original-engine morph frames, static reduced pose and no intro
  copy/Agent labels; 24 offline canvas/SVG images covering zh/en and wide/narrow
  dimensions. These are static source renders, not actual browser fullscreen.
- All pre-dock cues equal V6; 22-second timeline, shell/card paths and R8
  setup/install/review logic unchanged except the audio primitive/call.
- Cue scheduling at a nonzero shared audio clock, strict required primitive,
  actual host PCM BufferSource copying and existing track/stop/onended cleanup.
- Deterministic Float32 PCM at 32000/44100/48000/96000/192000 Hz; finite samples,
  zero envelope endpoints, separate contact energy, centered final contact,
  no clipping and bounded adjacent-sample steps.

At 48 kHz: 163200 stereo frames, raw peak 0.1201186553, RMS 0.0151299126,
maximum adjacent step 0.0039285496. Master-scaled excerpt peak is about .08408;
zero clipped samples. Results and 24 stills are in
`output/verification/v0.1.1-intro-revision-9/offline-checks.json`. The WAV is
`dock-r9-48000-stereo-excerpt.wav` in that directory. Generated local evidence is
ignored, while reproducible source checks and provenance are committed.

## Root review entry and remaining gate

After root integrates this commit into the checkout served on port 49161:
`http://127.0.0.1:49161/?revision=9#intro`. Confirm the visible label is
revision 09, choose either language, keep sound enabled and select Play preview
or replay. Listen to the complete 22 seconds, focusing on 18.1–21.5 seconds.
Triangle/Sphere buttons inspect 19.8/21.6-second static frames without sound.
Existing fullscreen, mute, exit and reduced-motion review controls remain.

### Root browser verification

The first browser replay exposed stale cached scripts: the page displayed 09
but still scheduled R8's home sound. The six script references now include their
SHA-256 content prefixes. After reloading, the actual browser reported exactly
one home cue, `dock-contacts`, at 18.1 s with stopAt 21.5 s. A label alone is not
version evidence.

Actual 22-second playback completed: 2649 recorded frames, maximum gap 11.5 ms,
approval/answer transition maximum gap 9.5 ms, no gaps over 50 ms, audio context
running, and zero owned audio sources at natural completion. These measurements
describe this run, not a guarantee on all hardware. Evidence is
`output/verification/v0.1.1-intro-revision-9/browser-playback.json`.

The actual window stage (477 × 498) produced diameter 227.046875 px, matching
the .7 formula within pixel rounding. The actual 1728 × 1080 fullscreen sphere
screenshot shows the smaller centered character and unchanged top island;
diameter is approximately 499 px. Screenshot:
`output/verification/v0.1.1-intro-revision-9/browser-zh-fullscreen-sphere.png`.
The screenshot is a fullscreen static frame; full playback timing was recorded
in the ordinary browser view.

Perceived material/volume and user approval remain pending. Native
synchronization and formal app build remain gated on user confirmation;
waveform checks and a running audio context do not approve the sound.
