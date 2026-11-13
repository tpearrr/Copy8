#!/bin/bash
# Compila Copy8 in release e crea build/Copy8.app, firmata ad-hoc.
# Uso: scripts/build-app.sh            → crea build/Copy8.app
#      scripts/build-app.sh --install  → la copia anche in /Applications
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Copy8"

APP=build/Copy8.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Copy8"
cp Support/Info.plist "$APP/Contents/Info.plist"

if [ ! -f build/AppIcon.icns ]; then
    rm -rf build/AppIcon.iconset
    swiftc -O scripts/make-icon.swift -o build/make-icon
    build/make-icon build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Creato $APP"

if [ "${1:-}" = "--install" ]; then
    pkill -x Copy8 2>/dev/null || true
    rm -rf /Applications/Copy8.app
    cp -R "$APP" /Applications/
    echo "Installato in /Applications/Copy8.app"
fi
