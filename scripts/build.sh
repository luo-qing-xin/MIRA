#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/dist/MIRA.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" /tmp/mira-swift-cache
swiftc -parse-as-library -module-cache-path /tmp/mira-swift-cache Sources/*.swift -o "$APP/Contents/MacOS/MIRA" -framework SwiftUI -framework AppKit -framework UserNotifications -framework ServiceManagement
cp Info.plist "$APP/Contents/Info.plist"
cp integrations/codex/receive.py "$APP/Contents/Resources/receive.py"
cp integrations/dsh/index.js integrations/dsh/entry.js "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"
echo "$APP"
