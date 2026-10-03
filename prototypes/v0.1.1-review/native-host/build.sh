#!/bin/zsh
set -euo pipefail

# The optional argument selects the prototype snapshot AND output repository.
HOST_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_REPO="${1:-$(cd "$HOST_DIR/../../.." && pwd)}"
SOURCE_REPO="$(cd "$SOURCE_REPO" && pwd)"
PROTOTYPE="$SOURCE_REPO/prototypes/v0.1.1-review"
OUTPUT="$SOURCE_REPO/output/verification/v0.1.1-intro-revision-5"
APP="$OUTPUT/AIsland Intro Review.app"
mkdir -p "$OUTPUT"
BUILD_DIR="$(mktemp -d "$OUTPUT-build.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

[[ -f "$PROTOTYPE/index.html" ]] || { print -u2 "Missing prototype: $PROTOTYPE"; exit 1; }
mkdir -p "$OUTPUT" "$BUILD_DIR/AIsland Intro Review.app/Contents/MacOS" "$BUILD_DIR/AIsland Intro Review.app/Contents/Resources"
BUNDLE="$BUILD_DIR/AIsland Intro Review.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -sdk "$SDK" -target "$(uname -m)-apple-macosx12.0" -O \
  -framework AppKit -framework WebKit -framework CoreGraphics \
  "$HOST_DIR/main.swift" -o "$BUNDLE/Contents/MacOS/AIslandIntroReview"
mkdir -p "$BUNDLE/Contents/Resources/prototype"
# Copy page assets only; omit host source, generated output and all symlinks.
/usr/bin/rsync -rt --exclude 'native-host/' --exclude 'native-capture/' --exclude 'output/' \
  "$PROTOTYPE/" "$BUNDLE/Contents/Resources/prototype/"
cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>AIslandIntroReview</string>
  <key>CFBundleIdentifier</key><string>dev.aisland.intro-review</string>
  <key>CFBundleName</key><string>AIsland Intro Review</string>
  <key>CFBundleDisplayName</key><string>AIsland Intro Review</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.1</string>
  <key>CFBundleVersion</key><string>5</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$BUNDLE/Contents/Info.plist"
codesign --force --sign - "$BUNDLE"
# Replaces only this explicitly named, generated reviewer bundle.
if [[ -e "$APP" ]]; then rm -rf "$APP"; fi
mv "$BUNDLE" "$APP"
print "Built (not launched): $APP"
print "Read-only geometry: $APP/Contents/MacOS/AIslandIntroReview --geometry-json"
