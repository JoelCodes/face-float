#!/bin/bash
# Builds FaceFloat and assembles a runnable .app bundle in build/.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/FaceFloat.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/FaceFloat "$APP/Contents/MacOS/FaceFloat"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature so TCC remembers the camera permission grant.
codesign --force --sign - "$APP"

echo "Built $APP — run with: open $APP"

# --install: replace the copy in /Applications and relaunch it.
if [[ "${1:-}" == "--install" ]]; then
    pkill -x FaceFloat || true
    sleep 1
    rm -rf /Applications/FaceFloat.app
    cp -R "$APP" /Applications/FaceFloat.app
    open /Applications/FaceFloat.app
    echo "Installed and launched /Applications/FaceFloat.app"
fi
