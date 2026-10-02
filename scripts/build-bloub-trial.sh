#!/bin/zsh
# A separate local bundle of the canonical app, with simulated sessions only.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
swift build --product OpenIslandApp
bin_dir="$(swift build --show-bin-path)"
trial_bundle="$repo_root/output/bloub-trial/Open Island Bloub Trial.app"
mkdir -p "$trial_bundle/Contents/"{MacOS,Resources,Frameworks}
cp "$bin_dir/OpenIslandApp" "$trial_bundle/Contents/MacOS/OpenIslandApp"
ditto "$bin_dir/OpenIsland_OpenIslandApp.bundle" "$trial_bundle/Contents/Resources/OpenIsland_OpenIslandApp.bundle"
ditto "$bin_dir/Sparkle.framework" "$trial_bundle/Contents/Frameworks/Sparkle.framework"
cp "$repo_root/Assets/Brand/OpenIsland.icns" "$trial_bundle/Contents/Resources/OpenIsland.icns"
cp "$repo_root/docs/licenses/bloub-MIT.txt" "$trial_bundle/Contents/Resources/bloub-MIT.txt"
cp "$repo_root/LICENSE" "$trial_bundle/Contents/Resources/LICENSE"
install_name_tool -add_rpath '@loader_path/../Frameworks' "$trial_bundle/Contents/MacOS/OpenIslandApp"
cat > "$trial_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.openisland.bloub-trial</string>
<key>CFBundleName</key><string>Open Island Bloub Trial</string>
<key>CFBundleDisplayName</key><string>Open Island Bloub Trial</string>
<key>CFBundleExecutable</key><string>OpenIslandApp</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleIconFile</key><string>OpenIsland.icns</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>OpenIslandBloubTrial</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$trial_bundle"
codesign --verify --deep --strict "$trial_bundle"
echo "$trial_bundle"
if [[ "${1:-}" == "--launch" ]]; then
    open -na "$trial_bundle"
fi
