#!/bin/bash
# Claude FM.app 을 빌드해 build/ 에 만든다. --install 을 주면 ~/Applications 로 복사한다.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Claude FM.app"

swift build -c release --product ClaudeFM
BIN="$(swift build -c release --show-bin-path)/ClaudeFM"

mkdir -p .build/tools
swiftc -O scripts/render/main.swift Sources/ClaudeFM/ClawdSprite.swift -o .build/tools/render
rm -rf .build/AppIcon.iconset
.build/tools/render icon .build/AppIcon.iconset

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeFM"
cp Resources/Info.plist "$APP/Contents/Info.plist"
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "built: $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  pkill -x ClaudeFM 2>/dev/null || true
  rm -rf ~/Applications/"Claude FM.app"
  cp -R "$APP" ~/Applications/
  echo "installed: ~/Applications/Claude FM.app"
fi
