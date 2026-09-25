#!/bin/bash
# Reproducible local build + guarded production install for Black Label Live Wallpaper.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/production-install-guard.sh
source "$SRC/scripts/production-install-guard.sh"
RELEASE_INSTALL="${RELEASE_INSTALL:-0}"
SIGN_ID="${SIGN_ID:--}"
if [[ "${INSTALL:-0}" == "1" && "$RELEASE_INSTALL" != "1" ]]; then
  echo "ABORT: INSTALL=1 cannot install a development build over the production app. Use RELEASE_INSTALL=1 with a Developer ID SIGN_ID." >&2
  exit 64
fi
APP_NAME="Black Label Live Wallpaper"
EXE="LiveWallpaper"
BUILD="$SRC/build"
APP="$BUILD/$APP_NAME.app"
WALLPAPER="$HOME/Pictures/BlackLabelBots_wallpaper_5504x3072.png"
MIN_OS="13.0"
APP_BUILD="2"
ARCHS=(arm64 x86_64)
SDK="$(xcrun --sdk macosx --show-sdk-path)"

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
  <key>CFBundleVersion</key><string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Bundle the art so the app is self-contained.
[ -f "$WALLPAPER" ] || { echo "ABORT: missing wallpaper asset at $WALLPAPER"; exit 1; }
"$SRC/scripts/validate-wallpaper-asset.sh" "$WALLPAPER"
cp "$WALLPAPER" "$APP/Contents/Resources/wallpaper.png"

echo "==> Compiling Swift (universal2: ${ARCHS[*]})"
ARCH_BINS=()
for ARCH in "${ARCHS[@]}"; do
  xcrun swiftc -O \
    -sdk "$SDK" \
    -target "$ARCH-apple-macosx$MIN_OS" \
    -o "$BUILD/$EXE-$ARCH" \
    "$SRC/Sources/main.swift" \
    -framework Cocoa -framework SwiftUI
  ARCH_BINS+=("$BUILD/$EXE-$ARCH")
done
lipo -create "${ARCH_BINS[@]}" -output "$APP/Contents/MacOS/$EXE"
rm -f "${ARCH_BINS[@]}"
echo "    archs: $(lipo -archs "$APP/Contents/MacOS/$EXE")"

codesign --force --deep --options runtime --timestamp -s "$SIGN_ID" "$APP"
codesign --verify --deep --strict "$APP"
echo "built: $APP"

if [[ "$RELEASE_INSTALL" == "1" ]]; then
  production_install_guard "$RELEASE_INSTALL" "$APP"
  DEST="/Applications/$APP_NAME.app"
  STAGE_INSTALL="$DEST.staging.$$"
  OLD="$DEST.old.$$"
  rm -rf "$STAGE_INSTALL" "$OLD"
  cp -R "$APP" "$STAGE_INSTALL"
  test -f "$STAGE_INSTALL/Contents/Info.plist"
  test -f "$STAGE_INSTALL/Contents/MacOS/$EXE"
  test -f "$STAGE_INSTALL/Contents/Resources/wallpaper.png"
  codesign --verify --deep --strict "$STAGE_INSTALL"
  [ -d "$DEST" ] && mv "$DEST" "$OLD"
  mv "$STAGE_INSTALL" "$DEST"
  rm -rf "$OLD"
  codesign --verify --deep --strict "$DEST"
  echo "installed atomically: $DEST"
fi
