#!/usr/bin/env bash
# Builds Sound Control.app in ./build. Pass --install to copy it to /Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Sound Control.app"

cd "$ROOT"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/SoundControl" "$APP/Contents/MacOS/SoundControl"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

codesign --force --sign - --timestamp=none "$APP"
echo "App generada en: $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x SoundControl 2>/dev/null || true
    rm -rf "/Applications/Sound Control.app"
    cp -R "$APP" /Applications/
    echo "Instalada en /Applications/Sound Control.app"
    open "/Applications/Sound Control.app"
fi
