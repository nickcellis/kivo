#!/bin/bash
# One command from a clean tree to a notarised, stapled DMG.
#
#   ./Tools/release.sh
#
# Needs two things this script cannot create for you, because both are
# tied to an Apple account:
#
#   1. A "Developer ID Application" certificate. Xcode ▸ Settings ▸
#      Accounts ▸ Manage Certificates ▸ + ▸ Developer ID Application.
#      It requires a paid Apple Developer Program membership — the fee is
#      for the certificate, not for charging users, so a free app needs it
#      too. An "Apple Development" certificate is NOT this, and will not
#      notarise.
#
#   2. Credentials for the notary service, stored once:
#
#        xcrun notarytool store-credentials kivo \
#            --apple-id you@example.com \
#            --team-id HHHAPHWV9Z \
#            --password <app-specific-password>
#
#      The password is an app-specific one from appleid.apple.com, never
#      your Apple ID password.
#
# What it then does, and why in this order: the app is signed, notarised
# and stapled first, so the app works offline on its own once dragged out
# of the image; then the image is built around the stapled app, notarised
# and stapled in turn, so the download itself passes Gatekeeper before it
# is ever opened.
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE=${KIVO_NOTARY_PROFILE:-kivo}
APP=build/Build/Products/Release/Kivo.app

step() { printf "\n\033[1m%s\033[0m\n" "$1"; }
fail() { printf "\n\033[31m%s\033[0m\n" "$1" >&2; exit 1; }

step "Checking what this needs"

IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)

[ -n "$IDENTITY" ] || fail "No 'Developer ID Application' certificate in the keychain.
Create one in Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates, then run this again.
An 'Apple Development' certificate is a different thing and cannot be notarised."

xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || fail "No notary credentials stored under the profile '$PROFILE'.
Run: xcrun notarytool store-credentials $PROFILE --apple-id <you> --team-id HHHAPHWV9Z --password <app-specific-password>"

echo "  signing as: $IDENTITY"

step "Building Release"
xcodebuild -scheme Kivo -configuration Release -derivedDataPath build build >/dev/null

step "Signing the app"
# --timestamp and --options runtime are both required for notarisation.
codesign --force --options runtime --timestamp \
    --entitlements kivo/kivo.entitlements \
    --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=1 "$APP"

step "Notarising the app"
ZIP=$(mktemp -d)/Kivo.zip
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

step "Stapling the app"
# Stapled before packaging, so the app still validates on a Mac that is
# offline when it first runs.
xcrun stapler staple "$APP"

step "Building the disk image"
VERSION=$(xcodebuild -scheme Kivo -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ MARKETING_VERSION /{print $2; exit}')
VERSION=${VERSION:-1.0}
DMG="dist/Kivo-$VERSION.dmg"

mkdir -p dist
rm -f "$DMG"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/Kivo.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Kivo" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"

step "Signing, notarising and stapling the image"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

step "Verifying the way Gatekeeper will"
spctl -a -vvv -t install "$DMG" 2>&1 | sed 's/^/  /'
xcrun stapler validate "$DMG" | sed 's/^/  /'
codesign -dvvv "$APP" 2>&1 | grep -E "Authority=|flags=|Timestamp=" | sed 's/^/  /'

printf "\n\033[32m%s\033[0m\n" "$DMG is notarised and stapled. It will open on any Mac without a warning."
