#!/bin/bash
set -euo pipefail

echo "========================================"
echo " Building opaq (Release) "
echo "========================================"

# Determine project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 1. Compile the release executable once. --show-bin-path only prints the
# output directory; it does not compile.
echo "==> Running swift build -c release..."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="$BIN_DIR/opaq"
if [ ! -f "$BIN_PATH" ]; then
    echo "Error: Binary not found at $BIN_PATH"
    exit 1
fi
echo "==> Found binary at $BIN_PATH"

# 2. Create app bundle structure
APP_BUNDLE="opaq.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Creating $APP_BUNDLE directory structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 3. Copy binary
echo "==> Copying executable..."
cp "$BIN_PATH" "$MACOS_DIR/opaq"
chmod +x "$MACOS_DIR/opaq"

# 4. Copy the app icon when another step has generated it.
if [ -f "Resources/opaq.icns" ]; then
    echo "==> Copying app icon..."
    cp "Resources/opaq.icns" "$RESOURCES_DIR/opaq.icns"
else
    echo "WARNING: Resources/opaq.icns is missing; the bundle will have no app icon."
fi

# 5. Write Info.plist
echo "==> Generating Info.plist..."
cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleName</key>
    <string>opaq</string>
    <key>CFBundleDisplayName</key>
    <string>opaq</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.opaq</string>
    <key>CFBundleExecutable</key>
    <string>opaq</string>
    <key>CFBundleIconFile</key>
    <string>opaq</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSContactsUsageDescription</key>
    <string>opaq needs access to your contacts to match phone numbers and email addresses with names and avatars.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026. All rights reserved.</string>
</dict>
</plist>
EOF

# 6. Sign with a stable identity when one is installed.
# Ad-hoc signatures change cdhash every rebuild and macOS drops Full Disk Access.
IDENTITY="${OPAQ_SIGN_IDENTITY:-opaq-dev}"
if security find-identity -v -p codesigning | grep -F -q -- "$IDENTITY"; then
    echo "==> Signing $APP_BUNDLE with identity $IDENTITY..."
    codesign --force --deep --sign "$IDENTITY" "$APP_BUNDLE"
else
    echo "WARNING: No code signing identity named \"$IDENTITY\" was found."
    echo "WARNING: Ad-hoc signing (--sign -) changes the cdhash on every rebuild, so macOS will drop Full Disk Access."
    echo "WARNING: Run scripts/setup-signing.sh once, or set OPAQ_SIGN_IDENTITY to an existing identity."
    echo "==> Ad-hoc signing $APP_BUNDLE..."
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

# 7. Verify code signature
echo "==> Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "========================================"
echo " Successfully built $APP_BUNDLE! "
echo "========================================"
