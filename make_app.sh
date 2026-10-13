#!/bin/bash
# macOS: クリックすると「最新に集計 → ブラウザで開く」ランチャーアプリを作る
#   使い方: ./make_app.sh            → ~/Applications/Claude使用履歴.app
#           ./make_app.sh /出力先     → 指定フォルダに作る
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3 || true)"
[ -n "$PY" ] || { echo "python3 が見つかりません" >&2; exit 1; }
OUT_DIR="${1:-$HOME/Applications}"
APP="$OUT_DIR/Claude使用履歴.app"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>Claude使用履歴</string>
	<key>CFBundleDisplayName</key><string>Claude使用履歴</string>
	<key>CFBundleIdentifier</key><string>local.claude-usage-dashboard.app</string>
	<key>CFBundleExecutable</key><string>launcher</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
cat > "$APP/Contents/MacOS/launcher" <<LAUNCHER
#!/bin/bash
cd "$DIR" || exit 1
if ! "$PY" build_usage.py >> build_usage.log 2>&1; then
  osascript -e 'display dialog "集計に失敗しました。build_usage.log を確認してください。" buttons {"OK"} default button 1 with icon caution' >/dev/null 2>&1
  exit 1
fi
open "$DIR/claude-usage-dashboard.html"
LAUNCHER
chmod +x "$APP/Contents/MacOS/launcher"
echo "作成しました: $APP"
echo "Finder で開いて、Dock にドラッグすると、いつでも起動できます。"
