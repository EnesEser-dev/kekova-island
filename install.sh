#!/bin/zsh
# Builds Kekova Island and installs it to ~/Applications, replacing any running copy.
set -euo pipefail
cd "$(dirname "$0")"

./build-app.sh

DEST="$HOME/Applications/KekovaIsland.app"
pkill -x KekovaIsland || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R build/KekovaIsland.app "$DEST"
open "$DEST"
echo "Installed to $DEST"
