#!/bin/zsh

set -euo pipefail

SCRIPT_DIRECTORY=${0:A:h}
PROJECT_DIRECTORY=${SCRIPT_DIRECTORY:h}
NOTARY_PROFILE=${NOTARY_PROFILE:-Liddddd-notary}

cd "${PROJECT_DIRECTORY}"
"${SCRIPT_DIRECTORY}/build-release.sh"

APP_BUNDLE="${PROJECT_DIRECTORY}/build/Liddddd.app"
VERSION=$(/usr/libexec/PlistBuddy \
    -c "Print :CFBundleShortVersionString" \
    "${APP_BUNDLE}/Contents/Info.plist")
NOTARIZATION_ARCHIVE="${PROJECT_DIRECTORY}/build/Liddddd-${VERSION}-notarization.zip"
DMG="${PROJECT_DIRECTORY}/build/Liddddd-${VERSION}.dmg"
CHECKSUM="${DMG}.sha256"

xcrun notarytool submit \
    "${NOTARIZATION_ARCHIVE}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait
xcrun stapler staple "${APP_BUNDLE}"
xcrun stapler validate "${APP_BUNDLE}"

"${SCRIPT_DIRECTORY}/create-dmg.sh" "${APP_BUNDLE}" "${DMG}"

xcrun notarytool submit \
    "${DMG}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait
xcrun stapler staple "${DMG}"
xcrun stapler validate "${DMG}"

codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
spctl --assess --type execute --verbose=2 "${APP_BUNDLE}"
spctl --assess \
    --type open \
    --context context:primary-signature \
    --verbose=2 \
    "${DMG}"
/usr/bin/shasum -a 256 "${DMG}" > "${CHECKSUM}"

echo "Built, notarized, and stapled ${DMG}"
echo "Built ${CHECKSUM}"
