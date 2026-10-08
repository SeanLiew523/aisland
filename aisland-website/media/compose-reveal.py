"""Export real native pixels as an alpha foreground, separate from wallpaper.

Compact native layers were captured at 8x. Expanded native content stays at its
original 2x density; no view, glyph, text, shape, or animation is recreated.
"""
import argparse
import bisect
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("recording", type=Path)
parser.add_argument("assets", type=Path)
args = parser.parse_args()
rows = [[float(v) for v in line.split(",")] for line in
        (args.recording / "frames/timing.csv").read_text().splitlines()]
times = [row[1] for row in rows]
edit = json.loads(Path(__file__).with_name("reveal-edit.json").read_text())
assert edit["playback_speed"] == 1
segments, duration = [], 0
for clip in edit["clips"]:
    assert 0 <= clip["start"] < clip["end"] <= times[-1]
    end = round(duration + clip["end"] - clip["start"], 6)
    segments.append(dict(start=duration, end=end, chapter=clip["chapter"]))
    duration = end
chapter_times = [next(s["start"] for clip,s in zip(edit["clips"],segments)
                if clip["scene"] == name) + .5 for name in
                ["running", "answer-expanded", "approval-expanded", "sessions", "done"]]
timeline = dict(duration=duration, chapters=chapter_times, segments=segments)
(args.assets.parent / "demo-timeline.js").write_text(
    "// Generated from the genuine native capture by media/compose-reveal.py.\n"
    + "const DEMO_TIMELINE = Object.freeze(" + json.dumps(timeline, indent=2) + ");\n")

catalogs = {}
for name in ["frames", "frames-compact"]:
    catalog = [[float(v) for v in line.split(",")] for line in
               (args.recording / name / "timing.csv").read_text().splitlines()]
    catalogs[name] = (catalog, [r[1] for r in catalog])
last_index, last_image = None, None
def frame(time):
    global last_index, last_image
    normal_rows, normal_times = catalogs["frames"]
    normal_index = max(0, bisect.bisect_right(normal_times, time) - 1)
    compact = int(normal_rows[normal_index][4]) in [0, 1, 2, 4, 8]
    name = "frames-compact" if compact else "frames"
    catalog, timestamps = catalogs[name]
    index = max(0, bisect.bisect_right(timestamps, time) - 1)
    key = (name, index)
    if key != last_index:
        last_image = Image.open(args.recording / name / f"frame-{int(catalog[index][0]):04d}.png").convert("RGBA")
        last_index = key
    return last_image

def at(time):
    for clip, segment in zip(edit["clips"], segments):
        if time < segment["end"]:
            return clip["start"] + time - segment["start"]
    return edit["clips"][-1]["end"] - .01

def encode(filename, size, seconds, source):
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo",
           "-pix_fmt", "rgba", "-s", f"{size[0]}x{size[1]}", "-r", "30", "-i", "pipe:0",
           "-an", "-c:v", "libvpx-vp9", "-deadline", "good", "-cpu-used", "6",
           "-threads", "8", "-row-mt", "1", "-tile-columns", "2", "-b:v", "0",
           "-crf", "18", "-auto-alt-ref", "0", "-pix_fmt", "yuva420p", str(args.assets / filename)]
    encoder = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    cached_index, cached_bytes = None, None
    for n in range(round(seconds * 30)):
        native = frame(source(n / 30))
        if last_index != cached_index:
            native = native.resize((size[0], round(native.height * size[0] / native.width)), Image.Resampling.LANCZOS)
            canvas = Image.new("RGBA", size)
            canvas.paste(native, (0, 0))
            cached_bytes, cached_index = canvas.tobytes(), last_index
        encoder.stdin.write(cached_bytes)
    encoder.stdin.close()
    if encoder.wait():
        raise RuntimeError(filename)
    print(f"Exported {filename}: {(args.assets / filename).stat().st_size / 1024**2:.2f} MiB", flush=True)

intro = edit["intro"]
encode("native-idle-hd.webm", (3072, 342), intro["end"] - intro["start"], lambda t: intro["start"] + t)
frame(8).resize((3072, 342), Image.Resampling.LANCZOS).save(args.assets / "native-idle-hd.png")
encode("native-reveal-en.webm", (1536, 1308), duration, at)

verification = json.loads((args.recording / "native-view-verification.json").read_text())
provenance = dict(
    source_commit=(args.recording / "source-commit.txt").read_text().strip(),
    configuration=dict(compact_pass=json.loads((args.recording / "recording-config-compact.json").read_text()),
        expanded_pass=json.loads((args.recording / "recording-config.json").read_text())),
    production_view_verification=verification,
    native_frames={name: len(catalog[0]) for name, catalog in catalogs.items()}, actual_capture_seconds=times[-1], edit=edit,
    playback_speed=1, output_fps=30,
    timing="Last captured native frame at each output timestamp; duplicates, no motion interpolation",
    presentation="Native alpha foreground, at 576pt / 1728pt screen width; original Apple wallpaper is a separate static layer",
    compact_source_pixels=[4608,512], expanded_source_pixels="1152 wide, native variable height",
    output_pixels=dict(intro=[3072,342], main=[1536,1308]),
    playback_density_note="1536-pixel native foreground exceeds the 720 CSS-pixel close-up at 2x display density; expanded UI is shown only after the camera pulls back",
    render_density_note="Two native takes: compact vector layers at 8x, and a separate take entirely at unchanged 2x backing density for correct expanded text throughout native transitions",
    capture_timing_by_segment={str(i): dict(frames=len(r), median_interval_seconds=round(statistics.median(
        [b[1]-a[1] for a,b in zip(r,r[1:])]),4)) for i in range(9)
        if len(r := [r for r in rows if int(r[4])==i]) > 1},
)
provenance["assets_sha256"] = {name: hashlib.sha256((args.assets / name).read_bytes()).hexdigest()
    for name in ["native-idle-hd.webm", "native-idle-hd.png", "native-reveal-en.webm"]}
(args.assets / "reveal-capture-provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
