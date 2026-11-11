#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/dist/MIRA.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" /tmp/mira-swift-cache
# Info.plist declares macOS 13. Without an explicit target the toolchain stamps
# the build host's version, so the bundle cannot launch on older systems.
TARGET="${MIRA_TARGET:-$(uname -m)-apple-macos13.0}"
swiftc -target "$TARGET" -parse-as-library -module-cache-path /tmp/mira-swift-cache Sources/*.swift -o "$APP/Contents/MacOS/MIRA" -framework SwiftUI -framework AppKit -framework UserNotifications -framework ServiceManagement
EXPECTED_MIN="${TARGET##*-macos}"
BUILT_MIN="$(otool -l "$APP/Contents/MacOS/MIRA" | awk '$1 == "minos" { print $2; exit }')"
if [ "$BUILT_MIN" != "$EXPECTED_MIN" ]; then
  echo "构建产物的最低系统版本是 $BUILT_MIN，但目标是 $EXPECTED_MIN；应用可能在声明的 macOS 版本上无法启动。" >&2
  exit 1
fi
cp Info.plist "$APP/Contents/Info.plist"
cp integrations/codex/receive.py "$APP/Contents/Resources/receive.py"
cp integrations/dsh/index.js integrations/dsh/entry.js "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"
echo "$APP"
