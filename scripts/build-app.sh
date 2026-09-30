#!/bin/bash
set -euo pipefail

BOBBY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BOBBY_ROOT"
BOBBY_CONFIGURATION="${1:-release}"
export CLANG_MODULE_CACHE_PATH="$BOBBY_ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BOBBY_ROOT/.build/module-cache"
BOBBY_SWIFT_OPTIONS=(--disable-sandbox --cache-path "$BOBBY_ROOT/.build/swiftpm-cache" --config-path "$BOBBY_ROOT/.build/swiftpm-config" --security-path "$BOBBY_ROOT/.build/swiftpm-security" --manifest-cache local)
swift build "${BOBBY_SWIFT_OPTIONS[@]}" -c "$BOBBY_CONFIGURATION"
BOBBY_BIN="$(swift build "${BOBBY_SWIFT_OPTIONS[@]}" -c "$BOBBY_CONFIGURATION" --show-bin-path)"
BOBBY_APP="$BOBBY_ROOT/build/Bobby.app"
mkdir -p "$BOBBY_APP/Contents/MacOS" "$BOBBY_APP/Contents/Resources"
cp "$BOBBY_BIN/Bobby" "$BOBBY_APP/Contents/MacOS/Bobby"
swift "$BOBBY_ROOT/scripts/make-icon.swift" "$BOBBY_ROOT/.build/Bobby.iconset"
iconutil -c icns "$BOBBY_ROOT/.build/Bobby.iconset" -o "$BOBBY_APP/Contents/Resources/Bobby.icns"
cat > "$BOBBY_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>Bobby</string>
    <key>CFBundleIdentifier</key><string>com.dodoturkoz.bobby</string>
    <key>CFBundleName</key><string>Bobby</string>
    <key>CFBundleIconFile</key><string>Bobby</string>
    <key>CFBundleDisplayName</key><string>Bobby</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$BOBBY_APP"
printf 'Built %s\n' "$BOBBY_APP"
