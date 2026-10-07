#!/bin/zsh
# Builds Vendor/mediaremote-adapter into a framework without needing cmake.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Vendor/mediaremote-adapter"
OUT="${1:-build/MediaRemoteAdapter.framework}"

rm -rf "$OUT"
mkdir -p "$OUT/Resources"

clang -dynamiclib -arch arm64 -mmacosx-version-min=15.0 \
    -fobjc-arc -fvisibility=default \
    -I "$SRC/include" -I "$SRC/src" \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    -install_name "@rpath/MediaRemoteAdapter.framework/MediaRemoteAdapter" \
    "$SRC"/src/adapter/*.m "$SRC"/src/private/*.m "$SRC"/src/utility/*.m \
    -o "$OUT/MediaRemoteAdapter"

cat > "$OUT/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
    <key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$OUT"
