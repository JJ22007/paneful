#!/bin/bash
# Build Paneful.app.
#   bash build.sh            compile to build/Paneful.app and run the self-test
#   bash build.sh install    also copy it to ~/Applications and launch it
#   bash build.sh snapshot   re-render the welcome screens into docs/
#
# Signing, in order of preference:
#   1. SIGN_ID="Developer ID Application: You" bash build.sh install
#   2. the local identity created by scripts/setup-signing.sh (used automatically)
#   3. ad-hoc. Works, but macOS forgets the Accessibility grant on every rebuild.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Paneful.app"
BIN="$APP/Contents/MacOS/Paneful"
LOCAL_ID="Paneful Local Signing"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# Compile for the oldest macOS we claim (LSMinimumSystemVersion below), so a newer-only API fails here
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13" Sources/*.swift -o "$BIN"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>io.github.paneful</string>
    <key>CFBundleName</key><string>Paneful</string>
    <key>CFBundleDisplayName</key><string>Paneful</string>
    <key>CFBundleExecutable</key><string>Paneful</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

IDENTITY="${SIGN_ID:-}"
if [[ -z "$IDENTITY" ]] && security find-identity -p codesigning 2>/dev/null | grep -q "\"$LOCAL_ID\""; then
    IDENTITY="$LOCAL_ID"
fi
if [[ -n "$IDENTITY" ]]; then
    codesign --force --sign "$IDENTITY" ${SIGN_KEYCHAIN:+--keychain "$SIGN_KEYCHAIN"} "$APP"
    echo "signed with: $IDENTITY"
else
    codesign --force --sign - "$APP" 2>/dev/null
    echo "signed ad-hoc (run scripts/setup-signing.sh once to keep the Accessibility grant across rebuilds)"
fi

"$BIN" --selftest | grep -v '^ok' || { echo "self-test failed"; exit 1; }
for f in examples/*.json; do "$BIN" --check "$f" >/dev/null || { echo "bad example config: $f"; exit 1; }; done

case "${1:-}" in
install)
    DEST="$HOME/Applications/Paneful.app"
    pkill -x Paneful 2>/dev/null || true
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "installed and launched: $DEST"
    ;;
snapshot)
    "$BIN" --snapshot docs
    ;;
esac
