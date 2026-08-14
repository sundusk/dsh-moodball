#!/bin/bash
# 构建并打包成 .app（LSUIElement 纯菜单栏应用），然后启动
set -euo pipefail
cd "$(dirname "$0")"

EXEC_NAME="Waterball"
APP_NAME="Waterball"
BUNDLE_ID="com.linxin666.waterball-mac"
BUILD_DIR=".build/release"
APP_DIR="dist/${APP_NAME}.app"

echo "==> swift build -c release"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/$EXEC_NAME" "$APP_DIR/Contents/MacOS/$EXEC_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>水球</string>
	<key>CFBundleDisplayName</key>
	<string>水球</string>
	<key>CFBundleIdentifier</key>
	<string>com.linxin666.waterball-mac</string>
	<key>CFBundleExecutable</key>
	<string>Waterball</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

# 本地 ad-hoc 签名（未签名二进制在 arm64 上也能跑，签名更稳）
codesign --force --sign - "$APP_DIR" 2>/dev/null || true

echo "==> 打开 $APP_DIR"
open "$APP_DIR"

echo "✅ 完成"
