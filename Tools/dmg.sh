#!/bin/bash
# Builds a DMG for distribution.
#
#   ./Tools/dmg.sh            signed as built, with your certificate
#   ./Tools/dmg.sh --adhoc    re-signed with no certificate at all
#
# The disk image holds the app and a symlink to /Applications, which is
# how a Mac user expects to install one: open, drag across, eject. See
# package.sh for what each signing choice exposes, and note that neither
# gets past Gatekeeper until the app is signed with a Developer ID
# certificate and notarised — at which point the ticket is stapled to the
# .dmg itself, not only to the app inside it.
set -e
cd "$(dirname "$0")/.."

ADHOC=false
[ "$1" = "--adhoc" ] && ADHOC=true

VERSION=$(xcodebuild -scheme Kivo -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ MARKETING_VERSION /{print $2; exit}')
VERSION=${VERSION:-1.0}

xcodebuild -scheme Kivo -configuration Release -derivedDataPath build build >/dev/null

APP=build/Build/Products/Release/Kivo.app

mkdir -p dist
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/Kivo.app"

if $ADHOC; then
    codesign --force --sign - --options runtime \
        --entitlements kivo/kivo.entitlements "$STAGE/Kivo.app"
fi

ln -s /Applications "$STAGE/Applications"

DMG="dist/Kivo-$VERSION.dmg"
rm -f "$DMG"

# UDZO is the compressed read-only format every Mac can open without
# anything installed.
hdiutil create -volname "Kivo" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"

echo
echo "$DMG  $(du -h "$DMG" | cut -f1)"
echo "app inside:"
codesign -dvvv "$STAGE/Kivo.app" 2>&1 | grep -E "Authority=|Signature=|TeamIdentifier=|flags=" | sed 's/^/    /'
