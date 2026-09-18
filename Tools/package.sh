#!/bin/bash
# Builds Release and zips the app for a GitHub release.
#
# Note what this produces: an app signed for development, not for
# distribution. Gatekeeper will block it on every Mac but this one until
# it is signed with a Developer ID certificate and notarised, and the
# signature carries the signing account's email address, which anyone who
# downloads it can read with: codesign -dvvv Kivo.app
set -e
cd "$(dirname "$0")/.."

xcodebuild -scheme Kivo -configuration Release -derivedDataPath build build >/dev/null

mkdir -p dist
rm -f dist/Kivo.zip

# ditto rather than zip: it keeps the bundle's symlinks and the signature
# intact, which a plain zip does not.
ditto -c -k --keepParent build/Build/Products/Release/Kivo.app dist/Kivo.zip

echo "dist/Kivo.zip  $(du -h dist/Kivo.zip | cut -f1)"
codesign -dvvv build/Build/Products/Release/Kivo.app 2>&1 | grep -E "Authority=|flags="
