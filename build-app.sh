#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/MacIsland.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/MacIsland "$APP/Contents/MacOS/"
cp Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl "$APP/Contents/Resources/"
./scripts/build-mediaremote-adapter.sh "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>MacIsland</string>
    <key>CFBundleIdentifier</key><string>com.enes.macisland</string>
    <key>CFBundleName</key><string>MacIsland</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSCalendarsFullAccessUsageDescription</key><string>MacIsland shows your upcoming events and reminds you a few minutes before they start.</string>
    <key>NSBluetoothAlwaysUsageDescription</key><string>MacIsland shows a notice with battery level when your headphones connect.</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>com.enes.macisland</string>
            <key>CFBundleURLSchemes</key><array><string>macisland</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# A stable identity keeps macOS privacy permissions (Calendar, Downloads...) across
# rebuilds; ad-hoc signatures change every build, so macOS would ask again each time.
IDENTITY="MacIsland Local Signing"
if security find-identity -p codesigning | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "Signing ad-hoc (no \"$IDENTITY\" certificate); permissions will be asked again after each rebuild."
    codesign --force --sign - "$APP"
fi
echo "Built $APP"
