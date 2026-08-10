#!/bin/bash
# Build TouchBarApp and assemble a .app bundle by hand (no Xcode required).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP="$ROOT/build/TouchBarApp.app"
BUNDLE_ID="com.pedro.touchbarapp"

# A stable self-signed identity keeps TCC grants (Accessibility, Automation)
# across rebuilds. Pure ad-hoc signing changes the code identity every build,
# which makes macOS forget every permission you granted.
#   Create one: Keychain Access > Certificate Assistant > Create a Certificate…
#   name "TouchBarApp Dev", type "Code Signing", self-signed.
SIGN_IDENTITY="${SIGN_IDENTITY:-TouchBarApp Dev}"

echo "==> swift build -c $CONFIGURATION"
cd "$ROOT"
swift build -c "$CONFIGURATION"
BIN="$(swift build -c "$CONFIGURATION" --show-bin-path)/TouchBarApp"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TouchBarApp"
cp "$ROOT/Resources/config.example.json" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>TouchBarApp</string>
  <key>CFBundleDisplayName</key><string>TouchBarApp</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>TouchBarApp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <!-- Menu-bar agent: no Dock icon. -->
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>TouchBarApp asks Music and Spotify what is playing to show it on the Touch Bar.</string>
  <key>NSHumanReadableCopyright</key><string>Personal project.</string>
</dict>
</plist>
PLIST

echo "==> codesign"
if security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none "$APP"
  echo "    signed with '$SIGN_IDENTITY'"
else
  codesign --force --sign - "$APP"
  echo "    WARNING: identity '$SIGN_IDENTITY' not found, used ad-hoc signing."
  echo "    Accessibility/Automation permissions will reset on every rebuild."
fi

# Install into ~/Applications. Launchers (Raycast, Spotlight) only index the
# standard app directories — a bundle sitting in build/ is invisible to them.
# INSTALL=0 to skip.
if [ "${INSTALL:-1}" = "1" ]; then
  DEST="$HOME/Applications/TouchBarApp.app"
  echo "==> installing to $DEST"
  pkill -f "$DEST/Contents/MacOS/TouchBarApp" 2>/dev/null || true
  rm -rf "$DEST"
  mkdir -p "$HOME/Applications"
  cp -R "$APP" "$DEST"
  mdimport "$DEST" >/dev/null 2>&1 || true
fi

echo "==> done: $APP"
