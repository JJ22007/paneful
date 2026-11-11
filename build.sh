#!/bin/bash
# 编译 Fenping.app。用法:
#   bash build.sh            编译到 build/Fenping.app 并跑自测
#   bash build.sh install    编译后安装到 ~/Applications 并启动
#   bash build.sh snapshot   把欢迎界面重新渲染到 docs/
#
# 默认用临时(ad-hoc)签名。有 Apple 开发者证书的话:
#   SIGN_ID="Developer ID Application: 你的名字" bash build.sh install
# 这样重新编译后不用再重新授权辅助功能。
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Fenping.app"
BIN="$APP/Contents/MacOS/Fenping"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 Sources/*.swift -o "$BIN"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.fenping</string>
    <key>CFBundleName</key><string>Fenping</string>
    <key>CFBundleDisplayName</key><string>分屏</string>
    <key>CFBundleExecutable</key><string>Fenping</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign "${SIGN_ID:--}" "$APP" 2>/dev/null

"$BIN" --selftest | grep -v '^ok' || { echo "自测失败"; exit 1; }
for f in examples/*.json; do "$BIN" --check "$f" >/dev/null || { echo "示例配置有问题:$f"; exit 1; }; done

case "${1:-}" in
install)
    DEST="$HOME/Applications/Fenping.app"
    pkill -x Fenping 2>/dev/null || true
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "已安装并启动:$DEST"
    ;;
snapshot)
    "$BIN" --snapshot docs
    ;;
esac
