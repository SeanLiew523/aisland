"use strict";
(() => {
  const duration = 22;
  const requiredTimes = ["agents", "gather", "approval", "answer", "back", "completed", "dock", "settled"];

  function cueSheet(timeline) {
    if (!timeline || requiredTimes.some(key => !Number.isFinite(timeline[key]))) {
      throw new TypeError("Intro audio requires a complete finite timeline.");
    }
    if (timeline.duration !== undefined && timeline.duration !== duration) {
      throw new RangeError("Intro audio is composed for a 22-second scene.");
    }
    const cues = [];
    const tone = (label, freq, at, length, volume, type = "sine", endFreq = freq) =>
      cues.push({label, kind: "tone", at, length, volume, args: [freq, at, length, volume, type, endFreq]});
    const air = (label, at, length, volume, pan = 0) =>
      cues.push({label, kind: "air", at, length, volume, args: [at, length, volume, pan]});
    const swell = (label, freq, at, length, volume, pan = 0) =>
      cues.push({label, kind: "swell", at, length, volume, args: [freq, at, length, volume, pan]});

    // Preserve the approved opening, including its single brand gesture at 1.35s.
    swell("opening-low", 65.41, .08, 1.27, .12, -.25);
    swell("opening-mid", 130.81, .2, 1.12, .065, .25);
    air("opening-breath", .28, 1.06, .095, -.45);
    tone("opening-resonance-low", 65.41, 1.35, 1.45, .23, "sine", 49);
    tone("opening-resonance-mid", 130.81, 1.35, 1.1, .14, "sine", 123.47);
    tone("opening-resonance-upper", 196, 1.37, 1, .075);
    [261.63, 392, 523.25].forEach((freq, index) =>
      tone("opening-signature-" + index, freq, 1.35 + index * .12, .95 - index * .1, .12));
    air("opening-release", 1.42, 1.18, .038, .5);

    // A separate logo-to-task breath begins after the opening has fully stopped.
    // Overlapping soft envelopes create a continuous process, not repeated taps.
    const textureStart = timeline.agents + .3;
    air("gather-breath", textureStart, 3.7, .027, -.22);
    swell("gather-low", 130.81, textureStart, 1.75, .036, -.25);
    swell("gather-middle", 174.61, timeline.agents + 1, 2.35, .043, .23);
    swell("gather-upper", 196, timeline.gather - .55, 2.3, .04);
    swell("gather-light", 261.63, timeline.gather + .35, 1.6, .021, -.12);
    tone("task-arrival", 146.83, timeline.gather + .15, .23, .09, "sine", 82.41);
    air("task-arrival-breath", timeline.gather + .08, .3, .031, .25);

    // Leave the permission prompt alone: one short downward, restrained tone.
    tone("approval", 246.94, timeline.approval, .31, .105, "sine", 220);

    // The answer has a softer reed-like triangle body and a faint high shimmer.
    tone("answer-body", 329.63, timeline.answer, .68, .066, "triangle", 392);
    tone("answer-shimmer", 659.25, timeline.answer + .08, .43, .018);
    air("answer-breath", timeline.answer + .03, .42, .013, .15);

    // The task resumes through a low, slow bloom rather than another alert.
    air("resume-breath", timeline.back, 1.1, .026, -.12);
    swell("resume-body", 164.81, timeline.back + .05, 1.35, .027, .1);

    // Keep the recognizable completion pair unchanged.
    tone("completion-first", 392, timeline.completed, .65, .14);
    tone("completion-second", 587.33, timeline.completed + .14, .65, .1);

    // A quiet inward breath follows the physical collapse; no second signature.
    const collapseLength = timeline.settled - timeline.dock;
    swell("dock-low", 98, timeline.dock, collapseLength - .05, .037, -.1);
    air("dock-breath", timeline.dock + .07, collapseLength - .17, .024);
    swell("dock-mid", 146.83, timeline.dock + .7, collapseLength - .75, .024, .1);
    tone("settled", 110, timeline.settled, .2, .07, "sine", 73.42);
    air("settled-breath", timeline.settled, .13, .025);

    // Validate the whole score before creating any source. tone/swell stop 20ms
    // after their envelope, matching the host primitives and cancellation path.
    for (const cue of cues) {
      cue.stopAt = cue.at + cue.length + (cue.kind === "air" ? 0 : .02);
      if (cue.at < 0 || cue.length <= 0 || cue.stopAt > duration) {
        throw new RangeError("Intro audio cue is outside the 22-second scene: " + cue.label);
      }
    }
    return cues.sort((a, b) => a.at - b.at);
  }

  function schedule(base, timeline, API) {
    if (!Number.isFinite(base) || base < 0) {
      throw new TypeError("Intro audio base must be a finite shared audio-clock time.");
    }
    if (!API || ["tone", "air", "swell"].some(kind => typeof API[kind] !== "function")) {
      throw new TypeError("Intro audio requires the host tone, air and swell primitives.");
    }
    const cues = cueSheet(timeline);
    for (const cue of cues) {
      const args = cue.args.slice();
      args[cue.kind === "air" ? 0 : 1] += base;
      API[cue.kind](...args);
    }
    // Metadata only. All sources belong to the host primitives' track/stopSounds.
    return cues;
  }

  window.AIslandIntroAudio = Object.freeze({schedule, cueSheet, duration});
})();
