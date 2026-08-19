#!/bin/zsh

set -euo pipefail

SCRIPT_DIRECTORY=${0:A:h}
PROJECT_DIRECTORY=${SCRIPT_DIRECTORY:h}
SIGNING_IDENTITY=${CODESIGN_IDENTITY:-}

if [[ -z "${SIGNING_IDENTITY}" || "${SIGNING_IDENTITY}" == "-" ]]; then
    echo "Set CODESIGN_IDENTITY to a Developer ID Application certificate." >&2
    exit 1
fi

if [[ "${SIGNING_IDENTITY}" != "Developer ID Application: "* ]]; then
    echo "CODESIGN_IDENTITY must be a Developer ID Application certificate." >&2
    exit 1
fi

if ! security find-identity -v -p codesigning | \
    grep -Fq "\"${SIGNING_IDENTITY}\""
then
    echo "The requested Developer ID Application identity is not installed." >&2
    exit 1
fi

cd "${PROJECT_DIRECTORY}"
"${SCRIPT_DIRECTORY}/build-app.sh"

APP_BUNDLE="${PROJECT_DIRECTORY}/build/Liddddd.app"
for development_resource in \
    "${APP_BUNDLE}/Contents/Resources/manage-local-helper.sh" \
    "${APP_BUNDLE}/Contents/Resources/io.github.leejaywon.liddddd.helper.legacy.plist"
do
    if [[ -e "${development_resource}" ]]; then
        echo "Release build contains a development-only helper resource." >&2
        exit 1
    fi
done

codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
if ! codesign -dvvv "${APP_BUNDLE}" 2>&1 | \
    grep -Fq "Authority=Developer ID Application:"
then
    echo "The app is not signed with a Developer ID Application certificate." >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy \
    -c "Print :CFBundleShortVersionString" \
    "${APP_BUNDLE}/Contents/Info.plist")
ARCHIVE="${PROJECT_DIRECTORY}/build/Liddddd-${VERSION}-notarization.zip"

/usr/bin/ditto -c -k --keepParent "${APP_BUNDLE}" "${ARCHIVE}"

echo "Built ${ARCHIVE}"
echo "Submit this archive for notarization before creating the release DMG."
