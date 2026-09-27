#!/usr/bin/env bash
# Builds build/NotchLimits.app (ad-hoc signed). `--install` copies it to
# ~/Applications and relaunches it.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
APP="build/NotchLimits.app"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/NotchLimits"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/NotchLimits"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.isachivka.notch-limits</string>
    <key>CFBundleName</key><string>Notch Limits</string>
    <key>CFBundleDisplayName</key><string>Notch Limits</string>
    <key>CFBundleExecutable</key><string>NotchLimits</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "built $APP"

if [[ "${1:-}" == "--install" ]]; then
    DEST="$HOME/Applications/NotchLimits.app"
    pkill -x NotchLimits 2>/dev/null || true
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "installed $DEST"
fi
