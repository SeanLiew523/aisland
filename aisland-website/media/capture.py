"""Build a disposable recording harness from a pinned real app source commit.

Only sample data and capture scheduling are added. No view, shape, or animation
implementation is replaced. Output is native AppKit/SwiftUI window pixels.
"""
import argparse
import os
from pathlib import Path
import subprocess
import tarfile
import io
import plistlib
import shutil

parser = argparse.ArgumentParser()
parser.add_argument("repository", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--bundle-plist", type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
package = args.output / "native-package"
package.mkdir(exist_ok=True)
sha = subprocess.check_output(["git", "-C", str(args.repository), "rev-parse", "HEAD"], text=True).strip()
archive = subprocess.check_output(["git", "-C", str(args.repository), "archive", sha, "Package.swift", "Sources", "Tests"])
with tarfile.open(fileobj=io.BytesIO(archive)) as source:
    source.extractall(package, filter="data")
app = package / "Sources/OpenIslandApp"
(app / "NativeDemoCapture.swift").write_text(Path(__file__).with_name("NativeDemoCapture.swift").read_text())
delegate = app / "OpenIslandApp.swift"
text = delegate.read_text()
needle = 'harnessRuntimeMonitor.recordMilestone("bootstrapCompleted")'
assert text.count(needle) == 1
delegate.write_text(text.replace(needle, needle + "\n            NativeDemoCapture.start(model: model)"))
# Select the app's observed "agents" compact slot for this process only.
# A volatile argument domain preserves the user's installed app preferences.
text = delegate.read_text()
assert text.count("let model = AppModel()") == 1
text = text.replace("let model = AppModel()", '''let model: AppModel = {
        UserDefaults.standard.setVolatileDomain(["appearance.island.v8.notch.rightSlot": "agents"], forName: UserDefaults.argumentDomain)
        return AppModel()
    }()''')
delegate.write_text(text)
frames = args.output / "frames"
frames.mkdir(exist_ok=True)
env = dict(os.environ, OPEN_ISLAND_HARNESS_SCENARIO="closed", OPEN_ISLAND_HARNESS_PRESENT_OVERLAY="1", OPEN_ISLAND_HARNESS_START_BRIDGE="0", OPEN_ISLAND_HARNESS_BOOT_ANIMATION="0", AGENT_ISLAND_MEDIA_DIR=str(frames.resolve()))
(args.output / "source-commit.txt").write_text(sha + "\n")
build = ["swift", "build", "--package-path", str(package), "--scratch-path", str(args.output / "build")]
subprocess.run(build + ["--product", "OpenIslandApp"], check=True)
bin_dir = Path(subprocess.check_output(build + ["--show-bin-path"], text=True).strip())
bundle = args.output / "Native Recording.app"
contents = bundle / "Contents"
(contents / "MacOS").mkdir(parents=True)
(contents / "Resources").mkdir()
shutil.copy2(bin_dir / "OpenIslandApp", contents / "MacOS/OpenIslandApp")
shutil.copytree(bin_dir / "OpenIsland_OpenIslandApp.bundle", contents / "Resources/OpenIsland_OpenIslandApp.bundle", symlinks=True)
(contents / "Frameworks").mkdir()
shutil.copytree(bin_dir / "Sparkle.framework", contents / "Frameworks/Sparkle.framework", symlinks=True)
plist = plistlib.loads(args.bundle_plist.read_bytes())
assert plist.get("OpenIslandLiveBloubStyle") is True
assert not plist.get("OpenIslandBloubTrial")
plist["CFBundleIdentifier"] = "dev.alsland.website-recording"
plist.pop("CFBundleIconFile", None)
(contents / "Info.plist").write_bytes(plistlib.dumps(plist))
subprocess.run(["install_name_tool", "-add_rpath", "@loader_path/../Frameworks", str(contents / "MacOS/OpenIslandApp")], check=True)
subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(bundle)], check=True)
(args.output / "recording-config.json").write_text(__import__("json").dumps({"bundle_name": plist["CFBundleDisplayName"], "live_bloub_style": True, "bridge_started": False, "session_data": "examples", "source_commit": sha}, indent=2) + "\n")
subprocess.run([str(contents / "MacOS/OpenIslandApp")], env=env, check=True)
