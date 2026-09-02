#!/bin/bash
# SessionDock.app 을 빌드한다.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$DIR/build/SessionDock.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SessionDock</string>
    <key>CFBundleIdentifier</key><string>com.minsujang.sessiondock</string>
    <key>CFBundleExecutable</key><string>SessionDock</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST

cp "$DIR/hooks/scan.py" "$DIR/hooks/record.py" "$APP/Contents/Resources/"
cp "$DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

swiftc -O -target arm64-apple-macosx13.0 \
    -o "$APP/Contents/MacOS/SessionDock" \
    "$DIR/src/Log.swift" "$DIR/src/Session.swift" "$DIR/src/Settings.swift" "$DIR/src/Route.swift" \
    "$DIR/src/Dock.swift" "$DIR/src/main.swift"

IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
            | awk 'NR==1 && /[0-9]+\)/ {print $2}')"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "빌드 완료: $APP"
