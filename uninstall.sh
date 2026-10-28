#!/bin/bash
set -uo pipefail
LABEL=com.markpinero.granola-autostart
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/.local/bin/granola-autostart"
echo "Uninstalled. Left in place: ~/.config/granola-autostart/token and ~/Library/Logs/granola-autostart.log"
echo "Remove the 'Granola Auto-start (Meet)' extension in chrome://extensions yourself."
