#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
LABEL=com.markpinero.granola-autostart
BIN="$HOME/.local/bin/granola-autostart"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/granola-autostart.log"

./build.sh
./build/granola-autostart --selftest
mkdir -p "$(dirname "$BIN")" "$(dirname "$PLIST")"
# Stop first, then replace the file (new inode). cp over a running signed
# binary makes macOS kill the new one with "Code Signature Invalid".
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
cp build/granola-autostart "$BIN.new" && mv -f "$BIN.new" "$BIN"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLIST

launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo
echo "Installed. Log: $LOG"
echo "Load the Meet extension once: chrome://extensions → Developer mode → Load unpacked → $(pwd)/extension"
