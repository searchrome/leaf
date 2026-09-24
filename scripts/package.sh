#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="$(pwd)/dist/Leaf.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Leaf "$APP/Contents/MacOS/Leaf"
cp packaging/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
