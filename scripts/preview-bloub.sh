#!/bin/zsh
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
preview_dir="$repo_root/output/bloub-preview"
preview_bundle="$preview_dir/Bloub Status Preview.app"
mkdir -p "$preview_bundle/Contents/MacOS"
cat > "$preview_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.openisland.bloub-preview</string>
<key>CFBundleName</key><string>Bloub Status Preview</string>
<key>CFBundleExecutable</key><string>BloubStatusPreview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
swiftc -parse-as-library -swift-version 6 \
    "$repo_root/Sources/OpenIslandApp/Views/UnifiedBars.swift" \
    "$repo_root/Sources/OpenIslandApp/Views/BloubStatusGlyph.swift" \
    "$repo_root/scripts/preview-bloub.swift" \
    -o "$preview_bundle/Contents/MacOS/BloubStatusPreview"
exec "$preview_bundle/Contents/MacOS/BloubStatusPreview" "$@"
