#!/bin/bash
# macOS: build_usage.py を 1 時間ごとに実行する launchd ジョブを登録する
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3)"
LABEL="local.claude-usage-dashboard"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$LABEL</string>
	<key>ProgramArguments</key>
	<array><string>$PY</string><string>$DIR/build_usage.py</string></array>
	<key>RunAtLoad</key><true/>
	<key>StartInterval</key><integer>3600</integer>
	<key>StandardOutPath</key><string>$DIR/build_usage.log</string>
	<key>StandardErrorPath</key><string>$DIR/build_usage.log</string>
</dict>
</plist>
PLIST
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "登録しました: $PLIST（1時間ごとに集計）"
