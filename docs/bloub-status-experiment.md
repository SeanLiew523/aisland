# Native Status Animations

AIsland adapts the bloub character to the closed island's 24 pt left slot and the matching Settings preview. The component is implemented in `Sources/OpenIslandApp/Views/BloubStatusGlyph.swift`; production rendering is enabled by `OpenIslandLiveBloubStyle`.

## State presentation

| State | Presentation |
|---|---|
| Idle | Warm-paper circle, subtle gaze drift and occasional blinks |
| Running | Three dots pulse in sequence |
| Waiting for approval | Pink character and a gently breathing blue notification badge |
| Waiting for an answer | Warm-yellow character and the same blue badge |

Waiting takes priority over running. Completed sessions resolve to idle. The waiting character blinks approximately once every five seconds, with slow gaze movement over a 25-second loop. The resting face is 20 pt inside the 24 pt slot.

## Rendering and lifecycle

The native view samples paths when configuration changes and uses Core Animation for playback, without a repeating SwiftUI frame timer. State paths preserve their topology, and transitions begin from the current presentation paths. Unchanged model updates do not restart playback.

The body, eyes and badge cutout use separate contour layers. Eyes are clipped to the body and use the host background color. Badge breathing uses smooth radius changes with constant brightness.

Expanded surfaces, hidden or detached views, invisible windows, and Reduce Motion stop repeating animation. Restoring visibility resumes the applicable state. Settings manual state selection ends automatic preview cycling.

## Development tools

- `scripts/preview-bloub.sh` shows the native glyph at 24 pt and 48 pt.
- `scripts/preview-bloub.sh --verify-lifecycle` checks visibility and animation lifecycle behavior.
- `scripts/build-bloub-trial.sh --launch` creates an isolated native preview bundle with example sessions and its bridge disabled.
- `scripts/test-bloub-isolated.py` runs the glyph's geometry and lifecycle tests in a disposable package.

Production app packages use normal discovery and bridge behavior. Preview tools are for local development; they do not send agent approvals or perform conversation jumps.

## Source and license

Adapted from [jeremy-prt/bloub](https://github.com/jeremy-prt/bloub), pinned to `b4bb3c1b5f93c7b87a2e8d620f667c4093d97749`. Face projection, dimensions, dot pulse, notification position and cubic contours derive from `face.ts`, `states.ts`, `decor.ts` and `shape.ts`. The native component implements the idle, thinking and notification states, with framing and motion suited to the small macOS surface.

The source's MIT notice is retained in [bloub-MIT.txt](./licenses/bloub-MIT.txt). The upstream project's design attribution remains applicable; AIsland does not imply affiliation with x.ai.
