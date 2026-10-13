#!/bin/bash
# macOS: クリックすると「最新に集計 → ブラウザで開く」ランチャーアプリを作る
#   使い方: ./make_app.sh            → ~/Applications/Claude使用履歴.app
#           ./make_app.sh /出力先     → 指定フォルダに作る
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3 || true)"
[ -n "$PY" ] || { echo "python3 が見つかりません" >&2; exit 1; }
HTML_URL="$("$PY" -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).as_uri())' "$DIR/claude-usage-dashboard.html")"
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
# ログはアプリ用の場所に出す（フォルダの権限に左右されないように）
LOG="\$HOME/Library/Logs/claude-usage-dashboard.log"
mkdir -p "\$(dirname "\$LOG")"
{
  echo "== \$(date)"
  cd "$DIR" || exit 1
  "$PY" build_usage.py
} >> "\$LOG" 2>&1
if [ \$? -ne 0 ]; then
  osascript -e 'display dialog "集計に失敗しました。~/Library/Logs/claude-usage-dashboard.log を確認してください。" buttons {"OK"} default button 1 with icon caution' >/dev/null 2>&1
  exit 1
fi
# Chrome 系ブラウザがあれば、タブやアドレスバーの無い「アプリ用ウィンドウ」で開く
for B in "Google Chrome" "Microsoft Edge" "Brave Browser"; do
  if [ -d "/Applications/\$B.app" ]; then
    open -na "\$B" --args --app="$HTML_URL" && exit 0
  fi
done
open "$DIR/claude-usage-dashboard.html"
LAUNCHER
chmod +x "$APP/Contents/MacOS/launcher"
echo "作成しました: $APP"
echo "Finder で開いて、Dock にドラッグすると、いつでも起動できます。"
