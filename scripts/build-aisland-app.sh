#!/bin/zsh
# Build the current branch as a live local app. Does not install/rewrite hooks.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
install_app=false
for arg in "$@"; do
    case "$arg" in
        --install) install_app=true ;;
        *) echo "Usage: $0 [--install]" >&2; exit 2 ;;
    esac
done
for product in OpenIslandApp OpenIslandHooks OpenIslandSetup; do
    swift build -c debug --product "$product"
done
bin_dir="$(swift build -c debug --show-bin-path)"
bundle="$repo_root/output/aisland/AIsland.app"
mkdir -p "$bundle/Contents/"{MacOS,Helpers,Resources,Frameworks}
cp "$bin_dir/OpenIslandApp" "$bundle/Contents/MacOS/OpenIslandApp"
for helper in OpenIslandHooks OpenIslandSetup; do
    cp "$bin_dir/$helper" "$bundle/Contents/Helpers/$helper"
done
ditto "$bin_dir/OpenIsland_OpenIslandApp.bundle" "$bundle/Contents/Resources/OpenIsland_OpenIslandApp.bundle"
ditto "$bin_dir/Sparkle.framework" "$bundle/Contents/Frameworks/Sparkle.framework"
cp "$repo_root/Assets/Brand/AIsland/AIsland.icns" "$bundle/Contents/Resources/AIsland.icns"
cp "$repo_root/docs/licenses/bloub-MIT.txt" "$bundle/Contents/Resources/bloub-MIT.txt"
cp "$repo_root/LICENSE" "$bundle/Contents/Resources/LICENSE"
install_name_tool -add_rpath '@loader_path/../Frameworks' "$bundle/Contents/MacOS/OpenIslandApp"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.aisland.app</string>
<key>CFBundleName</key><string>AIsland</string>
<key>CFBundleDisplayName</key><string>AIsland</string>
<key>CFBundleExecutable</key><string>OpenIslandApp</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleIconFile</key><string>AIsland.icns</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSAppleEventsUsageDescription</key><string>AIsland uses automation to return to your agent sessions.</string>
<key>OpenIslandLiveBloubStyle</key><true/>
<key>OpenIslandDisableUpdates</key><true/>
</dict></plist>
PLIST
identity="-"
if security find-identity -p codesigning -v "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null \
    | rg -q '"Open Island Dev Local"'; then
    identity="Open Island Dev Local"
fi
codesign --force --deep --sign "$identity" "$bundle"
codesign --verify --deep --strict "$bundle"
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
