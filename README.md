# Black Label Live Wallpaper

Native macOS live-wallpaper helper. The app bundle is built reproducibly under this repo's
`build/` directory.

## Build and install safety

```bash
./build.command  # ad-hoc development build -> ./build/; never touches /Applications
SIGN_ID="Developer ID Application: Your Name (TEAMID)" RELEASE_INSTALL=1 ./build.command
                 # explicit production install -> /Applications/Black Label Live Wallpaper.app
```

The canonical install path is fail-closed: `RELEASE_INSTALL=1` must be explicit and the
finished app must verify as a non-ad-hoc `Developer ID Application` signature. Legacy
`INSTALL=1` without release mode is rejected before compilation.
