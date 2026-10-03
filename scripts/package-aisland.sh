#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

export OPEN_ISLAND_APP_NAME="${OPEN_ISLAND_APP_NAME:-AIsland}"
export OPEN_ISLAND_BUNDLE_ID="${OPEN_ISLAND_BUNDLE_ID:-dev.aisland.app}"
export OPEN_ISLAND_VERSION="${OPEN_ISLAND_VERSION:-0.1.0}"
export OPEN_ISLAND_DISABLE_UPDATES="${OPEN_ISLAND_DISABLE_UPDATES:-true}"
export OPEN_ISLAND_UNIVERSAL="${OPEN_ISLAND_UNIVERSAL:-true}"
export OPEN_ISLAND_DMG_SKIP_FINDER="${OPEN_ISLAND_DMG_SKIP_FINDER:-true}"
export OPEN_ISLAND_PACKAGE_ROOT="${OPEN_ISLAND_PACKAGE_ROOT:-$repo_root/output/aisland}"

# Public packages default to ad-hoc signing. An explicit identity is optional;
# never import or create certificates as part of packaging.
if [[ "${OPEN_ISLAND_SIGN_IDENTITY:-}" == "Open Island Dev Local" ]]; then
    export OPEN_ISLAND_HARDENED_SIGNING="false"
fi

exec zsh "$repo_root/scripts/package-app.sh"
