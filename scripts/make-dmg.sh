#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

./build_app.sh

VERSION_FILE="Sources/opaq/AppVersion.swift"
MARKETING=$(sed -n 's/^[[:space:]]*static let marketing = "\([^"]*\)".*/\1/p' "$VERSION_FILE")
if [ -z "$MARKETING" ]; then
    echo "Error: could not read AppVersion.marketing from $VERSION_FILE"
    exit 1
fi

STAGE="$(mktemp -d)"
cleanup() {
    rm -rf "$STAGE"
}
trap cleanup EXIT

cp -R opaq.app "$STAGE/opaq.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
DMG="dist/opaq-${MARKETING}.dmg"
rm -f "$DMG"
hdiutil create -volname "opaq" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "Wrote $DMG"
