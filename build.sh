#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
swiftc -O Sources/*.swift -o build/granola-autostart \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist

# Shared secret between the background app and the Meet extension.
TOKEN_FILE="$HOME/.config/granola-autostart/token"
if [ ! -s "$TOKEN_FILE" ]; then
  mkdir -p "$(dirname "$TOKEN_FILE")"
  (umask 077; openssl rand -hex 16 > "$TOKEN_FILE")
fi
printf 'const TOKEN = "%s";\n' "$(cat "$TOKEN_FILE")" > extension/config.js
