"""Preserve native frame pixels and timings over original macOS wallpapers.

No UI is drawn or interpolated. The wallpaper is decoration, and the website
labels both example sessions and the composited desktop explicitly.
"""
import argparse
import bisect
import json
from pathlib import Path
import subprocess
import tempfile

from PIL import Image, ImageOps

parser = argparse.ArgumentParser()
parser.add_argument("recording", type=Path)
parser.add_argument("assets", type=Path)
parser.add_argument("--readme-gif", type=Path, help="Export the same edit as a native close-up GIF")
args = parser.parse_args()
args.assets.mkdir(parents=True, exist_ok=True)
rows = [[float(v) for v in row.split(",")] for row in (args.recording / "frames/timing.csv").read_text().splitlines()]
times = [row[1] for row in rows]
w, h, fps = 1536, 992, 30
edit = json.loads(Path(__file__).with_name("demo-edit.json").read_text())
if edit["playback_speed"] != 1:
    raise ValueError("Native animations must retain their recorded playback speed")
segments = []
duration = 0
previous_end = 0
for clip in edit["clips"]:
    if not previous_end <= clip["start"] < clip["end"] <= times[-1]:
        raise ValueError(f"Invalid source range: {clip}")
    end = round(duration + clip["end"] - clip["start"], 6)
    segments.append({"start": duration, "end": end, "chapter": clip["chapter"]})
    duration, previous_end = end, clip["end"]
chapters = [next(s["start"] for s in segments if s["chapter"] == chapter) + .5 for chapter in range(5)]
timeline = {"duration": duration, "chapters": chapters, "segments": segments}
(args.assets.parent / "demo-timeline.js").write_text(
    "// Generated from media/demo-edit.json by media/compose.py.\n"
    + "const DEMO_TIMELINE = Object.freeze(" + json.dumps(timeline, indent=2) + ");\n"
)
wallpapers = json.loads((args.assets / "wallpapers/sources.json").read_text())

def source_time(time):
    for clip, segment in zip(edit["clips"], segments):
        if time < segment["end"]:
            return clip["start"] + time - segment["start"]
    return edit["clips"][-1]["end"]

def native_frame(time):
    index = max(0, bisect.bisect_right(times, time) - 1)
    return Image.open(args.recording / "frames" / f"frame-{int(rows[index][0]):04d}.png").convert("RGBA")

def composite(time, wallpaper, native_width=512):
    image = wallpaper.copy()
    native = native_frame(time)
    # Actual panel was 576pt on a 1728pt built-in MacBook screen (@2x).
    # Keep this screen ratio and the top edge exactly.
    native = native.resize((native_width, round(native.height * native_width / native.width)), Image.Resampling.LANCZOS)
    image.paste(native, ((image.width - native.width) // 2, 0), native)
    return image

for theme, metadata in wallpapers.items():
    suffix = "" if theme == "signal" else f"-{theme}"
    wallpaper = ImageOps.fit(Image.open(args.assets / metadata["file"]).convert("RGB"), (w, h), method=Image.Resampling.LANCZOS)
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{w}x{h}", "-r", str(fps), "-i", "pipe:0", "-an", "-c:v", "libx264", "-preset", "slow", "-crf", "19", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(args.assets / f"native-demo{suffix}.mp4")]
    encoder = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for f in range(round(duration * fps)):
        encoder.stdin.write(composite(source_time(f / fps), wallpaper).tobytes())
    encoder.stdin.close()
    if encoder.wait(): raise RuntimeError(f"Video encoding failed: {theme}")
    composite(8.0, wallpaper).save(args.assets / f"demo-poster{suffix}.jpg", quality=92)
    print(f"Encoded {theme} with macOS {metadata['name']}", flush=True)
for filename, time in [("native-sessions.png", 26.0), ("native-approval.png", 14.5), ("native-complete.png", 29.2)]:
    frame = native_frame(time)
    frame.crop(frame.getbbox()).save(args.assets / filename)
provenance_path = args.assets / "capture-provenance.json"
# Keep the public-repository commit mapping and historical recording details.
provenance = json.loads(provenance_path.read_text()) if provenance_path.exists() else {
    "source_repository": "https://github.com/SeanLiew523/aisland",
    "source_commit": (args.recording / "source-commit.txt").read_text().strip(),
    "recording_configuration": json.loads((args.recording / "recording-config.json").read_text()),
    "recorded_seconds": 34,
    "interface": "Unmodified native app views, shapes, and animations",
    "sessions": "Example data supplied to the app's existing debug snapshot API",
    "external_actions": "No permissions were sent and no session jumps were simulated",
}
provenance.update({"native_frames": len(rows), "published_seconds": duration, "video_fps": fps,
    "edit": edit, "desktop": {"type": "Original Apple macOS wallpapers composited behind native UI", "wallpapers": wallpapers}})

if args.readme_gif:
    args.readme_gif.parent.mkdir(parents=True, exist_ok=True)
    gif_size, gif_fps = (960, 680), 15
    wallpaper = ImageOps.fit(Image.open(args.assets / wallpapers["matrix"]["file"]).convert("RGB"), gif_size, method=Image.Resampling.LANCZOS)
    with tempfile.TemporaryDirectory(prefix="aisland-demo-") as temporary:
        master = Path(temporary) / "close-up.mkv"
        palette = Path(temporary) / "palette.png"
        cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{gif_size[0]}x{gif_size[1]}", "-r", str(gif_fps), "-i", "pipe:0", "-an", "-c:v", "ffv1", str(master)]
        encoder = subprocess.Popen(cmd, stdin=subprocess.PIPE)
        for f in range(round(duration * gif_fps)):
            encoder.stdin.write(composite(source_time(f / gif_fps), wallpaper, native_width=900).tobytes())
        encoder.stdin.close()
        if encoder.wait(): raise RuntimeError("README master encoding failed")
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(master), "-vf", "palettegen=stats_mode=diff", "-frames:v", "1", str(palette)], check=True)
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(master), "-i", str(palette), "-lavfi", "paletteuse=dither=sierra2_4a:diff_mode=rectangle", "-loop", "0", str(args.readme_gif)], check=True)
    provenance["readme_preview"] = {"format": "GIF", "size": list(gif_size), "fps": gif_fps,
        "published_seconds": duration, "native_width": 900, "presentation": "Native close-up; same clips at recorded speed; Sonoma background"}
    print(f"Encoded README GIF: {args.readme_gif.stat().st_size / 1024 / 1024:.2f} MiB", flush=True)

provenance_path.write_text(json.dumps(provenance, indent=2) + "\n")
print(f"Encoded {duration}s native demonstration from {len(rows)} captured frames")
