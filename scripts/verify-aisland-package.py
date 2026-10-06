#!/usr/bin/env python3
"""Verify identity, universal binaries, signatures and both release archives."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("package", type=Path)
parser.add_argument("--require-notarized", action="store_true")
parser.add_argument("--expected-source")
args = parser.parse_args()
package = args.package.resolve()
app = package / "AIsland.app"
plist = plistlib.loads((app / "Contents/Info.plist").read_bytes())
assert plist["CFBundleDisplayName"] == plist["CFBundleName"] == "AIsland"
assert plist["CFBundleIdentifier"] == "dev.aisland.app"
assert plist["CFBundleExecutable"] == "OpenIslandApp"
assert plist["LSMinimumSystemVersion"] == "14.0"
assert plist["OpenIslandLiveBloubStyle"] is True
updates_enabled = plist.get("OpenIslandDisableUpdates") is False
if updates_enabled:
    subprocess.run(["python3", str(Path(__file__).with_name("verify-update-configuration.py")),
                    "--app", str(app)], check=True)
else:
    assert plist["OpenIslandDisableUpdates"] is True
    assert "SUFeedURL" not in plist and "SUPublicEDKey" not in plist
assert "OpenIslandBloubTrial" not in plist
assert len(plist["AIslandSourceCommit"]) == 40
if args.expected_source:
    assert plist["AIslandSourceCommit"] == args.expected_source, "Package does not match tagged source."
for binary in ["MacOS/OpenIslandApp", "Helpers/OpenIslandHooks", "Helpers/OpenIslandSetup", "Helpers/MiniMaxCodeSourceProbe"]:
    archs = subprocess.check_output(["lipo", "-archs", str(app / "Contents" / binary)], text=True).split()
    assert set(archs) == {"arm64", "x86_64"}, (binary, archs)
for resource in ["AIsland.icns", "LICENSE", "bloub-MIT.txt", "OpenIsland_OpenIslandApp.bundle"]:
    assert (app / "Contents/Resources" / resource).exists(), resource
assert (app / "Contents/Frameworks/Sparkle.framework").is_dir()
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
dmg, archive = package / "AIsland.dmg", package / "AIsland.zip"
subprocess.run(["hdiutil", "verify", str(dmg)], check=True, stdout=subprocess.DEVNULL)
with tempfile.TemporaryDirectory(prefix="aisland-dmg-verify-") as directory:
    mount = Path(directory) / "volume"
    subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(dmg)], check=True, stdout=subprocess.DEVNULL)
    try:
        shipped = mount / "AIsland.app"
        assert plistlib.loads((shipped / "Contents/Info.plist").read_bytes()) == plist
        assert (mount / "Applications").is_symlink()
        assert (mount / "Applications").readlink() == Path("/Applications")
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(shipped)], check=True)
        for relative in ["Contents/MacOS/OpenIslandApp", "Contents/Resources/AIsland.icns"]:
            assert (shipped / relative).read_bytes() == (app / relative).read_bytes()
    finally:
        subprocess.run(["hdiutil", "detach", str(mount)], check=True, stdout=subprocess.DEVNULL)
with tempfile.TemporaryDirectory(prefix="aisland-zip-verify-") as directory:
    subprocess.run(["ditto", "-x", "-k", str(archive), directory], check=True)
    zipped = Path(directory) / "AIsland.app"
    assert plistlib.loads((zipped / "Contents/Info.plist").read_bytes()) == plist
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(zipped)], check=True)
notarized = all(subprocess.run(["xcrun", "stapler", "validate", str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0 for path in [app, dmg])
if args.require_notarized:
    assert updates_enabled and notarized, "Public releases require enabled updates and both notarization tickets."
    subprocess.run(["spctl", "--assess", "--type", "execute", str(app)], check=True)
if updates_enabled:
    import xml.etree.ElementTree as ET
    config = json.loads((Path(__file__).resolve().parent.parent / "config/packaging/AIslandUpdates.json").read_text())
    subprocess.run(["swift", str(Path(__file__).with_name("verify-release-updates.swift")), str(package), config["public_key"]], check=True)
    items = ET.parse(package / "appcast.xml").findall("./channel/item")
    assert len(items) == 1
    ns = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    assert items[0].findtext(ns + "version") == plist["CFBundleVersion"]
    assert items[0].findtext(ns + "shortVersionString") == plist["CFBundleShortVersionString"]
    assert items[0].find("enclosure").get("url") == "https://github.com/SeanLiew523/aisland/releases/download/v" + plist["CFBundleShortVersionString"] + "/AIsland.zip"
hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in ([dmg, archive, package / "appcast.xml"] if updates_enabled else [dmg, archive])}
(package / "SHA256SUMS.txt").write_text("".join(f"{digest}  {name}\n" for name, digest in hashes.items()))
(package / "release-metadata.json").write_text(json.dumps({
    "name": "AIsland", "version": plist["CFBundleShortVersionString"],
    "bundle_identifier": plist["CFBundleIdentifier"], "source_commit": plist["AIslandSourceCommit"],
    "architectures": ["arm64", "x86_64"], "minimum_macos": "14.0",
    "live_bloub_style": True, "updates_enabled": updates_enabled, "notarized": notarized, "sha256": hashes,
}, indent=2) + "\n")
print("Verified AIsland identity, universal binaries, C1 resources, signatures, ZIP and mounted DMG.")
