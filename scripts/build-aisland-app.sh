#!/bin/zsh
# Build the current branch as a live local app. Does not install/rewrite hooks.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
# v0.1.1 is this development line's default; release builds pass it explicitly.
version="${OPEN_ISLAND_VERSION:-0.1.1}"
build_number="${OPEN_ISLAND_BUILD_NUMBER:-$(git rev-list --count HEAD)}"
bundle="$repo_root/output/aisland/AIsland.app"
install_app=false
validate_only=false
usage() {
    echo "Usage: $0 [--version X.Y.Z] [--build-number N] [--output PATH.app] [--install] [--validate-only]"
}
while (( $# )); do
    case "$1" in
        --version|--build-number|--output)
            (( $# >= 2 )) && [[ "$2" != --* ]] || { usage >&2; exit 2; }
            case "$1" in
                --version) version="$2" ;;
                --build-number) build_number="$2" ;;
                --output) bundle="$2" ;;
            esac
            shift 2 ;;
        --install) install_app=true; shift ;;
        --validate-only) validate_only=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
# Preflight is deliberately read-only, so parameter tests need no compiler,
# signing identity, source app, configuration write, or GUI action.
plan="$(python3 - "$repo_root" "$version" "$build_number" "$bundle" <<'PY_PLAN'
import hashlib, json, os, pathlib, re, subprocess, sys
root = pathlib.Path(sys.argv[1]).resolve()
version, number, output = sys.argv[2:]
def run(*args):
    return subprocess.check_output(["git", "-C", str(root), *args])
if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
    raise SystemExit("Version must be an explicit numeric X.Y.Z value.")
if not re.fullmatch(r"[1-9][0-9]{0,8}", number):
    raise SystemExit("Build number must be a positive integer (up to nine digits).")
if any(ord(c) < 32 for c in output):
    raise SystemExit("Output path contains control characters.")
requested = pathlib.Path(output)
if not requested.is_absolute(): requested = root / requested
output_root = root / "output"
if output_root.resolve() != output_root:
    raise SystemExit("Repository output directory must not be a symlink.")
target = requested.resolve()
if not target.is_relative_to(output_root) or target.suffix != ".app":
    raise SystemExit("Output must be an .app inside this repository's output directory.")
if os.path.lexists(requested) or os.path.lexists(target):
    raise SystemExit("Output already exists; choose another path. No bundle was overwritten.")
if run("status", "--porcelain", "--untracked-files=all"):
    raise SystemExit("Source tree must be clean before building or stamping a source commit.")
commit = run("rev-parse", "HEAD").decode().strip()
# A reverted edit during compilation still changes input mtimes. Track all Git
# inputs, rather than considering only the final porcelain state.
snapshot = hashlib.sha256()
for name in sorted(run("ls-files", "-z").split(b"\0")):
    if not name: continue
    path = root / os.fsdecode(name)
    stat = path.lstat()
    snapshot.update(name + b"\0" + str((stat.st_mode, stat.st_size, stat.st_mtime_ns)).encode() + b"\0")
print(json.dumps(dict(version=version, build_number=number, output=str(target),
    source_commit=commit, input_snapshot=snapshot.hexdigest(), bundle_identifier="dev.aisland.app",
    localizations=["en", "zh-Hans", "zh-Hant"], runtime_mode="normal"), sort_keys=True))
PY_PLAN
)"
if [[ "$validate_only" == true ]]; then
    echo "$plan"
    exit 0
fi
bundle="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["output"])' <<< "$plan")"
source_commit="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["source_commit"])' <<< "$plan")"
# Require the existing stable development identity. Never auto-create a key or
# silently replace a stable TCC identity with an ad-hoc signature.
identity="${OPEN_ISLAND_SIGN_IDENTITY:-Open Island Dev Local}"
[[ -n "$identity" && "$identity" != "-" ]] || { echo "A stable signing identity is required." >&2; exit 1; }
security find-identity -p codesigning -v "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null \
    | IDENTITY_TO_MATCH="$identity" python3 -c 'import os,sys; raise SystemExit(0 if "\""+os.environ["IDENTITY_TO_MATCH"]+"\"" in sys.stdin.read() else 1)' \
    || { echo "The configured stable signing identity is unavailable." >&2; exit 1; }
# A fresh staging directory leaves incomplete or source-stale bundles unpublished.
mkdir -p "${bundle:h}"
stage_dir="$(mktemp -d "${bundle:h}/.aisland-build.XXXXXX")"
trap 'rm -rf -- "$stage_dir"' EXIT
stage_bundle="$stage_dir/AIsland.app"
verify_source() {
    local current_plan
    current_plan="$(zsh "$repo_root/scripts/build-aisland-app.sh" --version "$version" --build-number "$build_number" --output "$bundle" --validate-only)" || return 1
    [[ "$current_plan" == "$plan" ]] || { echo "Source inputs changed during build; refusing to publish a source stamp." >&2; return 1; }
}
for product in OpenIslandApp OpenIslandHooks OpenIslandSetup MiniMaxCodeSourceProbe; do
    swift build -c debug --product "$product"
done
bin_dir="$(swift build -c debug --show-bin-path)"
verify_source
mkdir -p "$stage_bundle/Contents/"{MacOS,Helpers,Resources,Frameworks}
cp "$bin_dir/OpenIslandApp" "$stage_bundle/Contents/MacOS/OpenIslandApp"
for helper in OpenIslandHooks OpenIslandSetup MiniMaxCodeSourceProbe; do
    cp "$bin_dir/$helper" "$stage_bundle/Contents/Helpers/$helper"
done
ditto "$bin_dir/OpenIsland_OpenIslandApp.bundle" "$stage_bundle/Contents/Resources/OpenIsland_OpenIslandApp.bundle"
ditto "$bin_dir/Sparkle.framework" "$stage_bundle/Contents/Frameworks/Sparkle.framework"
cp "$repo_root/Assets/Brand/AIsland/AIsland.icns" "$stage_bundle/Contents/Resources/AIsland.icns"
cp "$repo_root/docs/licenses/bloub-MIT.txt" "$stage_bundle/Contents/Resources/bloub-MIT.txt"
cp "$repo_root/LICENSE" "$stage_bundle/Contents/Resources/LICENSE"
install_name_tool -add_rpath '@loader_path/../Frameworks' "$stage_bundle/Contents/MacOS/OpenIslandApp"
python3 - "$stage_bundle/Contents/Info.plist" "$plan" <<'PY_PLIST'
import json, pathlib, plistlib, sys
plan = json.loads(sys.argv[2])
info = dict(CFBundleIdentifier="dev.aisland.app", CFBundleName="AIsland", CFBundleDisplayName="AIsland",
    CFBundleExecutable="OpenIslandApp", CFBundlePackageType="APPL", CFBundleVersion=plan["build_number"],
    CFBundleShortVersionString=plan["version"], CFBundleIconFile="AIsland.icns", LSMinimumSystemVersion="14.0",
    CFBundleDevelopmentRegion="en", CFBundleLocalizations=plan["localizations"], NSHighResolutionCapable=True,
    NSPrincipalClass="NSApplication", NSAppleEventsUsageDescription="AIsland uses automation to return to your agent sessions.",
    OpenIslandLiveBloubStyle=True, OpenIslandDisableUpdates=True, AIslandSourceCommit=plan["source_commit"])
pathlib.Path(sys.argv[1]).write_bytes(plistlib.dumps(info, sort_keys=True))
PY_PLIST
codesign --force --deep --sign "$identity" "$stage_bundle"
codesign --verify --deep --strict "$stage_bundle"
verify_source
# Darwin's exclusive atomic rename also rejects an output which appears after
# preflight; unlike mv, it cannot accidentally nest the bundle into a new dir.
python3 - "$stage_bundle" "$bundle" <<'PY_PUBLISH'
import ctypes, os, sys
library = ctypes.CDLL(None, use_errno=True)
rename = library.renamex_np
rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
rename.restype = ctypes.c_int
if rename(os.fsencode(sys.argv[1]), os.fsencode(sys.argv[2]), 4):  # RENAME_EXCL
    raise SystemExit("Could not exclusively publish bundle: " + os.strerror(ctypes.get_errno()))
PY_PUBLISH
echo "AIsland $version build $build_number · source $source_commit" >&2
if [[ "$install_app" == true ]]; then
    destination="$HOME/Applications/AIsland.app"
    # Never copy over a running instance or a bundle belonging to another app.
    if pgrep -f "^$destination/Contents/MacOS/OpenIslandApp" >/dev/null; then
        echo "Quit AIsland before installing a new build." >&2; exit 1
    fi
    if [[ -d "$destination" ]]; then
        existing_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")
        [[ "$existing_id" == "dev.aisland.app" ]] || { echo "Destination belongs to another app." >&2; exit 1; }
        backup_dir="$repo_root/output/aisland/backups/$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        mv "$destination" "$backup_dir/AIsland.app"
    fi
    mkdir -p "$HOME/Applications"
    ditto "$bundle" "$destination"
    codesign --verify --deep --strict "$destination"
    echo "$destination"
else
    echo "$bundle"
fi
