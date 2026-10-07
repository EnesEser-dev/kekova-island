#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/KekovaIsland.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/KekovaIsland "$APP/Contents/MacOS/"
cp Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl "$APP/Contents/Resources/"
./scripts/build-mediaremote-adapter.sh "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>KekovaIsland</string>
    <key>CFBundleIdentifier</key><string>com.enes.kekovaisland</string>
    <key>CFBundleName</key><string>Kekova Island</string>
    <key>CFBundleDisplayName</key><string>Kekova Island</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSCalendarsFullAccessUsageDescription</key><string>Kekova Island shows your upcoming events and reminds you a few minutes before they start.</string>
    <key>NSBluetoothAlwaysUsageDescription</key><string>Kekova Island shows a notice with battery level when your headphones connect.</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>com.enes.kekovaisland</string>
            <key>CFBundleURLSchemes</key><array><string>kekova</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# A stable identity keeps macOS privacy permissions (Calendar, Downloads...) across
# rebuilds; ad-hoc signatures change every build, so macOS would ask again each time.
# The identity name lives in an untracked .signing-identity file (or $SIGNING_IDENTITY).
IDENTITY="${SIGNING_IDENTITY:-$(cat .signing-identity 2>/dev/null || true)}"
if [[ -n "$IDENTITY" ]] && security find-identity -p codesigning | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "Signing ad-hoc (no signing identity configured); macOS will ask for permissions again after each rebuild."
    codesign --force --sign - "$APP"
fi
echo "Built $APP"
