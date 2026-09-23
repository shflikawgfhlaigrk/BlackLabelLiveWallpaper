#!/bin/bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT/scripts/production-install-guard.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
contains() { /usr/bin/grep -Fq "$2" "$1" || fail "$1 missing: $2"; }
[[ -f "$HELPER" ]] || fail "missing repo-owned production install guard"
# shellcheck source=/dev/null
source "$HELPER"

APP="$(mktemp -d)/LiveWallpaper.app"
mkdir -p "$APP"
codesign() { printf '%s\n' "$FAKE_CODESIGN" >&2; }
expect_rc() {
  local expected="$1" release="$2" signature="$3" rc
  FAKE_CODESIGN="$signature"
  production_install_guard "$release" "$APP" >/dev/null 2>&1
  rc=$?
  [[ "$rc" -eq "$expected" ]] || fail "guard rc=$rc, expected $expected"
}
expect_rc 64 0 'Signature=adhoc'
expect_rc 65 1 'Signature=adhoc'
expect_rc 65 1 'Authority=Apple Development: Example'
expect_rc 0 1 'Authority=Developer ID Application: Example (TEAM)'
contains "$ROOT/build.command" 'production_install_guard "$RELEASE_INSTALL" "$APP"'
contains "$ROOT/build.command" 'WALLPAPER="$SRC/assets/wallpaper.png"'
contains "$ROOT/build.command" 'APP_BUILD="3"'
if /usr/bin/grep -Fq '$HOME/Pictures' "$ROOT/build.command" "$ROOT/Sources/main.swift"; then
  fail "build/runtime still depends on a user-home wallpaper path"
fi
EXPECTED_WALLPAPER_SHA256="50a72694b84b348aa146b87a0d1a311a91b16725ade3f607197c00c100440acd"
ACTUAL_WALLPAPER_SHA256="$(shasum -a 256 "$ROOT/assets/wallpaper.png" | awk '{print $1}')"
[[ "$ACTUAL_WALLPAPER_SHA256" == "$EXPECTED_WALLPAPER_SHA256" ]] ||
  fail "repo-owned wallpaper digest mismatch: $ACTUAL_WALLPAPER_SHA256"

echo "production install guard contract PASS"
