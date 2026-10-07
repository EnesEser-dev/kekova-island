#!/bin/zsh
# Builds MacIsland and installs it to ~/Applications, replacing any running copy.
set -euo pipefail
cd "$(dirname "$0")"

./build-app.sh

DEST="$HOME/Applications/MacIsland.app"
pkill -x MacIsland || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R build/MacIsland.app "$DEST"
open "$DEST"
echo "Installed to $DEST"
