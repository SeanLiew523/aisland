#!/usr/bin/env python3
"""Plan/build a separate full v0.1.1 acceptance app; never install or launch it.

Default invocation only prints the plan. The main agent must finish the real
currently approved real-source verification before explicitly invoking --build. This builder does
not claim source acceptance, playback, first launch or integration succeeded.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parent.parent
PREFIX = "dev.aisland.v011.acceptance."
V6 = "32c94f2fb0282242d17ef4db63f6c169a874e25f"
IDENTITY = "Open Island Dev Local"
APPROVED_NATIVE_R9 = "932c7caf4a6090b7660f0adc0f1e2f22e95feed2"
APPROVED_SHARP_R9 = "007f131dac35e9a50a83a408667b0e30ad457171"
SOURCE_SETUP_AGENTS = ("hermes", "deepSeekDesktop", "miniMaxCodeDesktop", "ohMyPi")
PRODUCTS = ("OpenIslandApp", "OpenIslandHooks", "OpenIslandSetup", "MiniMaxCodeSourceProbe")


def run(arguments, *, capture=False):
    result = subprocess.run(arguments, cwd=REPO, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def admission(case, socket, build_number):
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,31}", case):
        raise ValueError("Case must be 1–32 lowercase letters, digits or hyphens.")
    if build_number < 6:
        raise ValueError("v0.1.1 acceptance build number must be at least 6.")
    directory = Path("/private/tmp/aisland-v011-acceptance") / case
    candidate = Path(socket)
    # Only this dedicated case tree may host the Unix listener/registry/receipt.
    # Resolve parent symlinks to reject redirects into production paths.
    if not candidate.is_absolute() or candidate.resolve() != directory / "bridge.sock":
        raise ValueError(f"Socket must be /tmp/aisland-v011-acceptance/{case}/bridge.sock.")
    if len(str(candidate).encode()) >= 104 or directory.resolve() != directory:
        raise ValueError("Unsafe or too-long Unix socket path.")
    return directory, candidate.resolve()


def verify_v6_assets():
    """Check exact source captures/score without launching any renderer."""
    resources = REPO / "Sources/OpenIslandApp/Resources/Onboarding"
    manifest = json.loads((resources / "native-media.json").read_text())
    expected = set()
    for language, clips in manifest["clips"].items():
        for key, clip in clips.items():
            expected.add(f"native-{key}-{language}-still.png")
            expected.update(page["file"] for page in clip["pages"])
        expected.update(f"native-row-{agent}-{'zh-Hans' if language == 'zh' else 'en'}@2x.png"
                        for agent in ("claude", "codex", "gemini", "workbuddy"))
    if set(file.name for file in resources.glob("native-*.png")) != expected:
        raise ValueError("Native V6 capture inventory is incomplete or changed.")
    approved_manifest = subprocess.check_output(["git", "show", f"{V6}:prototypes/v0.1.1-review/assets/native-media.json"], cwd=REPO)
    if (resources / "native-media.json").read_bytes() != approved_manifest:
        raise ValueError("Native V6 manifest changed.")
    # Native PNG captures are byte-identical to the approved prototype.
    for file in resources.glob("native-*.png"):
        approved = subprocess.check_output(
            ["git", "show", f"{V6}:prototypes/v0.1.1-review/assets/{file.name}"], cwd=REPO)
        if file.read_bytes() != approved:
            raise ValueError(f"Native V6 capture changed: {file.name}")
    for name in ("intro-v6.wav", "native-media.json", "PROVENANCE.md"):
        if not (resources / name).is_file():
            raise ValueError(f"Missing native welcome media: {name}")
    approved_audio = subprocess.check_output(["git", "show", f"{APPROVED_NATIVE_R9}:Sources/OpenIslandApp/Resources/Onboarding/intro-v6.wav"], cwd=REPO)
    if (resources / "intro-v6.wav").read_bytes() != approved_audio:
        raise ValueError("Approved R8 home score changed (same source as the retained V6 WAV).")
    hashes = {name: hashlib.sha256((resources / name).read_bytes()).hexdigest()
              for name in ("intro-v6.wav", "native-media.json")}
    hashes.update(verify_r9_assets(resources))
    return hashes


def verify_r9_assets(resources):
    provenance_path = "Sources/OpenIslandApp/Resources/Onboarding/bloub-r9-provenance.json"
    approved = subprocess.check_output(["git", "show", f"{APPROVED_SHARP_R9}:{provenance_path}"], cwd=REPO)
    if (resources / "bloub-r9-provenance.json").read_bytes() != approved:
        raise ValueError("Approved R9 provenance changed.")
    provenance = json.loads(approved)
    manifest_bytes = (resources / "bloub-r9.json").read_bytes()
    manifest = json.loads(manifest_bytes)
    if provenance["revision"] != 9 or manifest["revision"] != 9 or manifest["fps"] != 30:
        raise ValueError("Invalid approved native R9 revision/rate.")
    if hashlib.sha256(manifest_bytes).hexdigest() != provenance["manifest_sha256"]:
        raise ValueError("Native R9 manifest checksum changed.")
    expected = set()
    for name, sequence in manifest["sequences"].items():
        if name not in ("idle", "thinking", "orbit"):
            raise ValueError("Unknown native R9 sequence.")
        expected.update(sequence["files"]); expected.add(sequence["stillFile"])
    if set(file.name for file in resources.glob("bloub-r9-*.png")) != expected or len(expected) != 191 or set(provenance["generated_files_sha256"]) != expected:
        raise ValueError("Native R9 inventory changed.")
    for name in expected:
        if Path(name).name != name or hashlib.sha256((resources / name).read_bytes()).hexdigest() != provenance["generated_files_sha256"][name]:
            raise ValueError("Native R9 capture checksum changed.")
    for path, digest in provenance["source_files_sha256"].items():
        if Path(path).is_absolute() or ".." in Path(path).parts or hashlib.sha256((REPO / path).read_bytes()).hexdigest() != digest:
            raise ValueError("Approved native R9 source checksum changed.")
    if (resources / "bloub-MIT.txt").read_bytes() != (REPO / "prototypes/v0.1.1-review/assets/bloub-MIT.txt").read_bytes():
        raise ValueError("Native R9 license changed.")
    return {"bloub-r9.json": hashlib.sha256(manifest_bytes).hexdigest(), "bloub-r9-provenance.json": hashlib.sha256(approved).hexdigest()}



def make_plist(case, directory, socket, build_number, commit, source_setup_agents=()):
    name = f"AIsland v0.1.1 Acceptance {case}"
    plist = {
        "CFBundleDevelopmentRegion": "en", "CFBundleLocalizations": ["en", "zh-Hans", "zh-Hant"],
        "CFBundleName": name, "CFBundleDisplayName": name,
        "CFBundleExecutable": "OpenIslandApp", "CFBundleIdentifier": PREFIX + case,
        "CFBundleInfoDictionaryVersion": "6.0", "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "0.1.1", "CFBundleVersion": str(build_number),
        "CFBundleIconFile": "AIsland.icns", "LSMinimumSystemVersion": "14.0",
        "NSPrincipalClass": "NSApplication", "NSHighResolutionCapable": True,
        "NSAppleEventsUsageDescription": "AIsland uses automation to return to your agent sessions.",
        "OpenIslandLiveBloubStyle": True, "OpenIslandDisableUpdates": True,
        "OpenIslandRuntimeAcceptance": True, "AIslandUpdaterFixtureSupported": True,
        "OpenIslandAcceptanceSocketPath": str(socket),
        "OpenIslandAcceptanceRegistryPath": str(directory / "runtime-lifecycle.json"),
        "AIslandSourceCommit": commit, "AIslandApprovedV6Commit": V6,
    }
    if source_setup_agents:
        if not (case.startswith("setup-") or case == "runtime-live") or not set(source_setup_agents).issubset(SOURCE_SETUP_AGENTS) or len(set(source_setup_agents)) != len(source_setup_agents):
            raise ValueError("Source setup requires a setup- case and an explicit unique reviewed source list.")
        plist.update(AIslandSourceSetupAcceptance=True, AIslandSourceSetupAgents=list(source_setup_agents),
                     AIslandSourceSetupSupportPath=str(directory / "support"))
    return plist


def build(plan, plist, configuration):
    destination = Path(plan["bundle"])
    output = destination.parent
    if output.resolve() != output:
        raise ValueError("Acceptance output must not resolve through a symlink.")
    if destination.exists() or destination.is_symlink():
        raise ValueError("Destination already exists; choose another build number. Existing apps are never overwritten.")
    identities = run(["security", "find-identity", "-p", "codesigning", "-v"], capture=True)
    if f'"{IDENTITY}"' not in identities:
        raise ValueError("Existing Open Island Dev Local identity is required; no certificate will be created/imported.")
    for product in PRODUCTS:
        run(["swift", "build", "-c", configuration, "--product", product])
    bin_dir = Path(run(["swift", "build", "-c", configuration, "--show-bin-path"], capture=True))
    if run(["git", "rev-parse", "HEAD"], capture=True) != plan["source_commit"] or run(["git", "status", "--porcelain"], capture=True):
        raise ValueError("Source changed during compilation; commit and rebuild.")
    required = [bin_dir / p for p in PRODUCTS] + [
        bin_dir / "OpenIsland_OpenIslandApp.bundle", bin_dir / "Sparkle.framework",
        REPO / "Assets/Brand/AIsland/AIsland.icns", REPO / "LICENSE", REPO / "docs/licenses/bloub-MIT.txt"]
    if not all(path.exists() for path in required):
        raise ValueError("Missing built product, helper, resource bundle, Sparkle, icon or license.")
    output = destination.parent
    if output.resolve() != output:
        raise ValueError("Acceptance output must not resolve through a symlink.")
    output.mkdir(parents=True, exist_ok=True)
    destination = Path(plan["bundle"])
    if destination.exists() or destination.is_symlink():
        raise ValueError("Destination already exists; choose another build number. Existing apps are never overwritten.")
    with tempfile.TemporaryDirectory(prefix=".acceptance-stage-", dir=output) as temporary:
        app = Path(temporary) / destination.name
        for folder in ("MacOS", "Helpers", "Resources", "Frameworks"):
            (app / "Contents" / folder).mkdir(parents=True)
        shutil.copy2(bin_dir / "OpenIslandApp", app / "Contents/MacOS/OpenIslandApp")
        for product in PRODUCTS[1:]:
            shutil.copy2(bin_dir / product, app / "Contents/Helpers" / product)
        for source, target in [
            (bin_dir / "OpenIsland_OpenIslandApp.bundle", app / "Contents/Resources/OpenIsland_OpenIslandApp.bundle"),
            (bin_dir / "Sparkle.framework", app / "Contents/Frameworks/Sparkle.framework")]:
            run(["ditto", str(source), str(target)])
        for source in required[-3:]:
            shutil.copy2(source, app / "Contents/Resources" / source.name)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(plist))
        (app / "Contents/Resources/acceptance-build.json").write_text(json.dumps(plan, indent=2) + "\n")
        for binary in [app / "Contents/MacOS/OpenIslandApp"] + [app / "Contents/Helpers" / p for p in PRODUCTS[1:]]:
            binary.chmod(binary.stat().st_mode | 0o111)
        binary = app / "Contents/MacOS/OpenIslandApp"
        dependencies = run(["otool", "-l", str(binary)], capture=True)
        if "@loader_path/../Frameworks" not in dependencies:
            run(["install_name_tool", "-add_rpath", "@loader_path/../Frameworks", str(binary)])
        # Sign only the staged acceptance tree with an already existing local
        # identity. Never invoke setup, hook install, packaging smoke or notarize.
        run(["codesign", "--force", "--deep", "--sign", IDENTITY, str(app)])
        run(["codesign", "--verify", "--deep", "--strict", str(app)])
        app.rename(destination)
    print(json.dumps({"bundle": str(destination), "built": True,
                      "installed": False, "launched": False,
                      "runtime_acceptance_verified": False}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", required=True)
    parser.add_argument("--socket", required=True)
    parser.add_argument("--build-number", type=int, default=6)
    parser.add_argument("--configuration", choices=("debug", "release"), default="debug")
    parser.add_argument("--source-setup", action="store_true", help="Explicitly permit owned source hook setup by this isolated App at launch (builder itself never configures sources).")
    parser.add_argument("--source-setup-agent", action="append", choices=SOURCE_SETUP_AGENTS, default=[])
    parser.add_argument("--build", action="store_true", help="Explicit build only after the main agent's approved real-source gate passes.")
    args = parser.parse_args()
    directory, socket = admission(args.case, args.socket, args.build_number)
    commit = run(["git", "rev-parse", "HEAD"], capture=True)
    if args.build and run(["git", "status", "--porcelain"], capture=True):
        raise ValueError("Commit the source first; acceptance metadata must identify the exact clean revision.")
    if args.source_setup != bool(args.source_setup_agent):
        raise ValueError("Source setup needs both --source-setup and at least one explicit --source-setup-agent.")
    if args.source_setup and not (args.case.startswith("setup-") or args.case == "runtime-live"):
        raise ValueError("Source setup requires a distinct setup- case or the previously granted runtime-live identity.")
    hashes = verify_v6_assets()
    bundle = REPO / "output/v011-acceptance" / f"AIsland-v011-{args.case}-b{args.build_number}.app"
    if args.source_setup:
        bundle = directory / "app/AIsland.app"
    plan = {"case": args.case, "bundle": str(bundle), "bundle_identifier": PREFIX + args.case,
            "source_commit": commit, "approved_v6_commit": V6,
            "version": "0.1.1", "build_number": args.build_number,
            "socket": str(socket), "registry": str(directory / "runtime-lifecycle.json"),
            "receipt": str(directory / "welcome-receipts.jsonl"),
            "native_media_sha256": hashes, "signing_identity": IDENTITY,
            "configuration": args.configuration, "installs": False, "launches": False,
            "products": list(PRODUCTS), "helpers": list(PRODUCTS[1:]),
            "runtime_acceptance_verified": False,
            "source_setup_at_launch": args.source_setup, "source_setup_agents": args.source_setup_agent,
            "source_setup_support": str(directory / "support") if args.source_setup else None,
            "source_setup_boundaries": "Only explicitly listed, proven installed sources; owned hook pointers backed up; original wrappers/consent/unrelated sources preserved; no tasks or CLI mcode.",
            "language_instructions": "Use the same case bundle for first/second launch. Launch with -AppleLanguages '(zh-Hans)' or '(en)' for system-language checks; appLanguage stays system. Manual preference cases use their own domain."}
    plist = make_plist(args.case, directory, socket, args.build_number, commit, args.source_setup_agent)
    if args.build:
        build(plan, plist, args.configuration)
    else:
        print(json.dumps({"plan_only": True, **plan}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError, OSError) as error:
        raise SystemExit(str(error))
