#!/bin/zsh
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
export OPEN_ISLAND_APP_NAME="AIsland"
export OPEN_ISLAND_BUNDLE_ID="dev.aisland.app"
export OPEN_ISLAND_VERSION="${OPEN_ISLAND_VERSION:-0.1.1}"
export OPEN_ISLAND_DISABLE_UPDATES="${OPEN_ISLAND_DISABLE_UPDATES:-false}"
export OPEN_ISLAND_UNIVERSAL="${OPEN_ISLAND_UNIVERSAL:-true}"
export OPEN_ISLAND_DMG_SKIP_FINDER="${OPEN_ISLAND_DMG_SKIP_FINDER:-true}"
export OPEN_ISLAND_PACKAGE_ROOT="${OPEN_ISLAND_PACKAGE_ROOT:-$repo_root/output/aisland}"
if [[ "$OPEN_ISLAND_DISABLE_UPDATES" == "false" ]]; then
    export OPEN_ISLAND_EDDSA_PUBLIC_KEY="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["public_key"])' "$repo_root/config/packaging/AIslandUpdates.json")"
    export AISLAND_UPDATE_SIGNING_IDENTITY="aisland-ed25519-v1"
    export OPEN_ISLAND_SIGN_IDENTITY="${OPEN_ISLAND_SIGN_IDENTITY:-Developer ID Application: Sean Liew (RNH9Q85QDQ)}"
    [[ "$OPEN_ISLAND_SIGN_IDENTITY" == "Developer ID Application:"* ]] || { echo "Release updates require Developer ID Application signing." >&2; exit 1; }
    [[ "${OPEN_ISLAND_HARDENED_SIGNING:-true}" == "true" ]] || { echo "Release signing requires Hardened Runtime." >&2; exit 1; }
    python3 "$repo_root/scripts/prepare-release-updates.py" --preflight
    python3 - "$repo_root" "$OPEN_ISLAND_PACKAGE_ROOT" <<'PY'
import pathlib, subprocess, sys
root, output = map(pathlib.Path, sys.argv[1:])
output = output.resolve()
assert output.is_relative_to(root / 'output'), 'Release output must be inside repository output.'
assert not subprocess.check_output(['git', '-C', str(root), 'status', '--porcelain']), 'Commit source changes before release packaging.'
assert not any((output / name).exists() for name in ['AIsland.app', 'AIsland.zip', 'AIsland.dmg', 'appcast.xml']), 'Choose a fresh release output; existing artifacts are preserved.'
PY
elif [[ "$OPEN_ISLAND_DISABLE_UPDATES" != "true" ]]; then
    echo "OPEN_ISLAND_DISABLE_UPDATES must be true or false." >&2; exit 1
fi
if [[ "${OPEN_ISLAND_SIGN_IDENTITY:-}" == "Open Island Dev Local" ]]; then
    export OPEN_ISLAND_HARDENED_SIGNING="false"
fi
release_snapshot="$(python3 "$repo_root/scripts/prepare-release-updates.py" --source-snapshot)"
# Release UI verification uses a separately admitted copy, never a second live
# production-domain smoke process. CI retains its isolated-machine smoke run.
if [[ "$OPEN_ISLAND_DISABLE_UPDATES" == "false" ]]; then
    export OPEN_ISLAND_PACKAGE_SMOKE="false"
fi
zsh "$repo_root/scripts/package-app.sh"
[[ "$release_snapshot" == "$(python3 "$repo_root/scripts/prepare-release-updates.py" --source-snapshot)" ]] || { echo "Source inputs changed during packaging; release refused." >&2; exit 1; }
if [[ "$OPEN_ISLAND_DISABLE_UPDATES" == "false" ]]; then
    python3 "$repo_root/scripts/prepare-release-updates.py" "$OPEN_ISLAND_PACKAGE_ROOT"
fi
