#!/bin/bash
# macOS: 専用ウィンドウのネイティブアプリ「Claude使用履歴.app」を作る
#   必要なもの: Xcode Command Line Tools（`xcode-select --install`）と Python 3
#   使い方: ./make_native_app.sh            → ~/Applications/Claude使用履歴.app
#           ./make_native_app.sh /出力先     → 指定フォルダに作る
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3 || true)"
[ -n "$PY" ] || { echo "python3 が見つかりません" >&2; exit 1; }
command -v swiftc >/dev/null || { echo "swiftc が見つかりません。'xcode-select --install' を実行してください" >&2; exit 1; }
OUT_DIR="${1:-$HOME/Applications}"
APP="$OUT_DIR/Claude使用履歴.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O "$DIR/native/main.swift" -o "$APP/Contents/MacOS/ClaudeUsage" -framework Cocoa -framework WebKit
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>Claude使用履歴</string>
	<key>CFBundleDisplayName</key><string>Claude使用履歴</string>
	<key>CFBundleIdentifier</key><string>local.claude-usage-dashboard.native</string>
	<key>CFBundleExecutable</key><string>ClaudeUsage</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>DashboardDir</key><string>$DIR</string>
	<key>PythonPath</key><string>$PY</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "作成しました: $APP"
echo "Dock にドラッグしておくと、いつでも起動できます。（⌘R で最新に更新）"
