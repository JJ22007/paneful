#!/bin/bash
# Build the release download: a universal (Apple silicon + Intel) Paneful.app, ad-hoc signed,
# zipped, with a checksum file. Both architectures run the self-test before anything is zipped.
#   bash scripts/package.sh        → dist/Paneful-universal.zip and dist/SHA256SUMS.txt
#
# Ad-hoc means every release has a different signature, so macOS asks for the Accessibility
# permission again after each update. Building from source with scripts/setup-signing.sh avoids that.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=dist
ZIP=Paneful-universal.zip
rm -rf "$OUT" && mkdir -p "$OUT"

bash build.sh                          # Info.plist, self-test, example configs
for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target "$arch-apple-macos13" Sources/*.swift -o "$OUT/Paneful-$arch"
done
cp -R build/Paneful.app "$OUT/"
lipo -create "$OUT/Paneful-arm64" "$OUT/Paneful-x86_64" -output "$OUT/Paneful.app/Contents/MacOS/Paneful"
rm "$OUT/Paneful-arm64" "$OUT/Paneful-x86_64"
codesign --force --sign - "$OUT/Paneful.app"

BIN="$OUT/Paneful.app/Contents/MacOS/Paneful"
echo "architectures: $(lipo -archs "$BIN")"
"$BIN" --selftest | tail -1
if arch -x86_64 /usr/bin/true 2>/dev/null; then
    arch -x86_64 "$BIN" --selftest | tail -1
else
    echo "warning: Rosetta is not installed, so the x86_64 self-test was skipped" >&2
fi

(cd "$OUT" && ditto -c -k --keepParent Paneful.app "$ZIP" && shasum -a 256 "$ZIP" > SHA256SUMS.txt && shasum -a 256 -c SHA256SUMS.txt)
echo "version $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$OUT/Paneful.app/Contents/Info.plist")"
ls -lh "$OUT/$ZIP" "$OUT/SHA256SUMS.txt"
