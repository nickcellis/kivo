#!/bin/bash
# Builds Release and zips the app for a GitHub release.
#
#   ./Tools/package.sh            signed as built, with your certificate
#   ./Tools/package.sh --adhoc    re-signed with no certificate at all
#
# Why --adhoc exists: a development signature carries the signing Apple
# ID's email address, and anyone who downloads the app can read it with
# "codesign -dvvv Kivo.app". Ad-hoc signing replaces that with nothing —
# no email, no team ID — and keeps the hardened runtime and entitlements.
#
# Neither option gets past Gatekeeper. Both are refused on another Mac
# until the app is signed with a Developer ID certificate and notarised;
# ad-hoc only decides whether the refusal names you.
set -e
cd "$(dirname "$0")/.."

ADHOC=false
[ "$1" = "--adhoc" ] && ADHOC=true

xcodebuild -scheme Kivo -configuration Release -derivedDataPath build build >/dev/null

APP=build/Build/Products/Release/Kivo.app

mkdir -p dist
rm -rf dist/Kivo.zip dist/Kivo.app

if $ADHOC; then
    # On a copy: the signature in build/ stays the one Xcode made.
    cp -R "$APP" dist/Kivo.app
    APP=dist/Kivo.app
    codesign --force --sign - --options runtime \
        --entitlements kivo/kivo.entitlements "$APP"
fi

# ditto rather than zip: it keeps the bundle's symlinks and its signature
# intact, and a plain zip does not.
ditto -c -k --keepParent "$APP" dist/Kivo.zip

echo
echo "dist/Kivo.zip  $(du -h dist/Kivo.zip | cut -f1)"
echo "what anyone who downloads it can read:"
codesign -dvvv "$APP" 2>&1 | grep -E "Authority=|Signature=|TeamIdentifier=|flags=" | sed 's/^/    /'
