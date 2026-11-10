#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="$(pwd)/dist/Leaf.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Leaf "$APP/Contents/MacOS/Leaf"
cp Sources/Leaf/Resources/LocalKokoro.py Sources/Leaf/Resources/LocalKokoro.requirements.txt "$APP/Contents/Resources/"
ICONSET="$(pwd)/.build/Leaf.iconset"
mkdir -p "$ICONSET"
swift packaging/generate-icon.swift "$ICONSET/icon_512x512@2x.png"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    if [ "$SIZE" != 512 ]; then
        sips -z "$DOUBLE" "$DOUBLE" "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
    fi
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Leaf.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp docs/THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp packaging/Info.plist "$APP/Contents/Info.plist"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
if [ "$SIGNING_IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"
touch "$APP"
if [ "${REGISTER_APP:-1}" = "1" ]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
fi
echo "Built $APP"
