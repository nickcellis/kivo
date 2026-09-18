#!/bin/bash
# Refreshes the README's screenshots.
#
# Builds Debug, then launches the app once per page with the demo data
# loaded, captures the window and quits. The data is invented (see
# DemoData.swift), so nothing here photographs the developer's own disk.
set -e
cd "$(dirname "$0")/.."

APP="build/Build/Products/Debug/Kivo.app/Contents/MacOS/Kivo"
OUT="docs/screenshots"

xcodebuild -scheme Kivo -configuration Debug -derivedDataPath build build >/dev/null
mkdir -p "$OUT"

for page in overview clean leftovers applications duplicates; do
    KIVO_DEMO="$page" KIVO_SHOT="$PWD/$OUT/$page.png" \
        "$APP" -appearance dark -AppleInterfaceStyle Dark || true
    echo "captured $page"
done
