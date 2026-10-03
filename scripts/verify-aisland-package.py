#!/usr/bin/env python3
"""Verify identity, universal binaries, signatures and both release archives."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("package", type=Path)
parser.add_argument("--require-notarized", action="store_true")
parser.add_argument("--team-id", help="Required Developer ID team, when verifying notarized packages")
args = parser.parse_args()
if args.team_id and not args.require_notarized:
    parser.error("--team-id requires --require-notarized")
package = args.package.resolve()
app = package / "AIsland.app"


def signature_details(code: Path, arch: str | None = None) -> str:
    command = ["codesign", "-dv", "--verbose=4"]
    if arch:
        command += ["--arch", arch]
    result = subprocess.run(command + [str(code)], check=True, text=True, capture_output=True)
    return result.stderr


def validate_notarized_app(bundle: Path) -> None:
    for relative in ["", "Contents/Helpers/OpenIslandHooks", "Contents/Helpers/OpenIslandSetup"]:
        for arch in ["arm64", "x86_64"]:
            details = signature_details(bundle / relative, arch)
            assert "Authority=Developer ID Application:" in details, (relative, arch, "Not Developer ID signed")
            assert re.search(r"^CodeDirectory .*flags=.*\bruntime\b", details, re.MULTILINE), (relative, arch, "No hardened runtime")
            assert re.search(r"^Timestamp=", details, re.MULTILINE), (relative, arch, "No secure timestamp")
            if args.team_id:
                assert f"TeamIdentifier={args.team_id}" in details.splitlines(), (relative, arch, "Wrong signing team")
    subprocess.run(["xcrun", "stapler", "validate", str(bundle)], check=True)
    subprocess.run(["spctl", "--assess", "--type", "execute", "--verbose=2", str(bundle)], check=True)


details = signature_details(app)
team_match = re.search(r"^TeamIdentifier=(.+)$", details, re.MULTILINE)
signing_team = team_match.group(1) if team_match and team_match.group(1) != "not set" else None
developer_id_signed = "Authority=Developer ID Application:" in details
# Detect real tickets; never infer notarization from an environment variable.
notarized = False
if developer_id_signed:
    ticket = subprocess.run(["xcrun", "stapler", "validate", str(app)], capture_output=True)
    notarized = ticket.returncode == 0
if args.require_notarized or notarized:
    validate_notarized_app(app)
plist = plistlib.loads((app / "Contents/Info.plist").read_bytes())
assert plist["CFBundleDisplayName"] == plist["CFBundleName"] == "AIsland"
assert plist["CFBundleIdentifier"] == "dev.aisland.app"
assert plist["CFBundleExecutable"] == "OpenIslandApp"
assert plist["LSMinimumSystemVersion"] == "14.0"
assert plist["OpenIslandLiveBloubStyle"] is True
assert plist["OpenIslandDisableUpdates"] is True
assert "SUFeedURL" not in plist and "SUPublicEDKey" not in plist
assert "OpenIslandBloubTrial" not in plist
assert len(plist["AIslandSourceCommit"]) == 40
for binary in ["MacOS/OpenIslandApp", "Helpers/OpenIslandHooks", "Helpers/OpenIslandSetup"]:
    archs = subprocess.check_output(["lipo", "-archs", str(app / "Contents" / binary)], text=True).split()
    assert set(archs) == {"arm64", "x86_64"}, (binary, archs)
for resource in ["AIsland.icns", "LICENSE", "bloub-MIT.txt", "OpenIsland_OpenIslandApp.bundle"]:
    assert (app / "Contents/Resources" / resource).exists(), resource
assert (app / "Contents/Frameworks/Sparkle.framework").is_dir()
subprocess.run(["codesign", "--verify", "--deep", "--strict", "--all-architectures", str(app)], check=True)
dmg, archive = package / "AIsland.dmg", package / "AIsland.zip"
subprocess.run(["hdiutil", "verify", str(dmg)], check=True, stdout=subprocess.DEVNULL)
if args.require_notarized or notarized:
    assert "Authority=Developer ID Application:" in signature_details(dmg), "DMG is not Developer ID signed"
    if args.team_id:
        assert f"TeamIdentifier={args.team_id}" in signature_details(dmg).splitlines(), "Wrong DMG signing team"
    subprocess.run(["codesign", "--verify", "--strict", str(dmg)], check=True)
    subprocess.run(["xcrun", "stapler", "validate", str(dmg)], check=True)
    subprocess.run(["spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=2", str(dmg)], check=True)
with tempfile.TemporaryDirectory(prefix="aisland-dmg-verify-") as directory:
    mount = Path(directory) / "volume"
    subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(dmg)], check=True, stdout=subprocess.DEVNULL)
    try:
        shipped = mount / "AIsland.app"
        assert plistlib.loads((shipped / "Contents/Info.plist").read_bytes()) == plist
        assert (mount / "Applications").is_symlink()
        assert (mount / "Applications").readlink() == Path("/Applications")
        subprocess.run(["codesign", "--verify", "--deep", "--strict", "--all-architectures", str(shipped)], check=True)
        if args.require_notarized or notarized:
            validate_notarized_app(shipped)
        for relative in ["Contents/MacOS/OpenIslandApp", "Contents/Resources/AIsland.icns"]:
            assert (shipped / relative).read_bytes() == (app / relative).read_bytes()
    finally:
        subprocess.run(["hdiutil", "detach", str(mount)], check=True, stdout=subprocess.DEVNULL)
with tempfile.TemporaryDirectory(prefix="aisland-zip-verify-") as directory:
    subprocess.run(["ditto", "-x", "-k", str(archive), directory], check=True)
    zipped = Path(directory) / "AIsland.app"
    assert plistlib.loads((zipped / "Contents/Info.plist").read_bytes()) == plist
    subprocess.run(["codesign", "--verify", "--deep", "--strict", "--all-architectures", str(zipped)], check=True)
    if args.require_notarized or notarized:
        validate_notarized_app(zipped)
hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [dmg, archive]}
(package / "SHA256SUMS.txt").write_text("".join(f"{digest}  {name}\n" for name, digest in hashes.items()))
(package / "release-metadata.json").write_text(json.dumps({
    "name": "AIsland", "version": plist["CFBundleShortVersionString"],
    "bundle_identifier": plist["CFBundleIdentifier"], "source_commit": plist["AIslandSourceCommit"],
    "architectures": ["arm64", "x86_64"], "minimum_macos": "14.0",
    "live_bloub_style": True, "updates_enabled": False,
    "developer_id_signed": developer_id_signed, "signing_team": signing_team,
    "notarized": notarized, "sha256": hashes,
}, indent=2) + "\n")
print("Verified AIsland identity, universal binaries, C1 resources, signatures, ZIP and mounted DMG.")
