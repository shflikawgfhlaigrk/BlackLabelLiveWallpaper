#!/bin/bash
# Reproducible build + install for Black Label Live Wallpaper.
set -euo pipefail
SRC="$HOME/BlackLabelLiveWallpaper"
APP_NAME="Black Label Live Wallpaper"
EXE="LiveWallpaper"
BUILD="$SRC/build"
APP="$BUILD/$APP_NAME.app"
WALLPAPER="$HOME/Pictures/BlackLabelBots_wallpaper_5504x3072.png"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$EXE</string>
  <key>CFBundleIdentifier</key><string>com.blacklabel.livewallpaper</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Bundle the art so the app is self-contained.
[ -f "$WALLPAPER" ] && cp "$WALLPAPER" "$APP/Contents/Resources/wallpaper.png"

swiftc -O -o "$APP/Contents/MacOS/$EXE" "$SRC/Sources/main.swift" \
  -framework Cocoa -framework SwiftUI

codesign --force --deep -s - "$APP" 2>/dev/null || true

rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP" "/Applications/$APP_NAME.app"
echo "built + installed: /Applications/$APP_NAME.app"
