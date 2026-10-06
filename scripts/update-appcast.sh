#!/bin/zsh
# Prepare the signed per-release feed; never insert unsigned repository entries.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$repo_root/scripts/prepare-release-updates.py" "$@"
