#!/bin/zsh

set -euo pipefail

SCRIPT_DIRECTORY=${0:A:h}
PROJECT_DIRECTORY=${SCRIPT_DIRECTORY:h}
OUTPUT_DIRECTORY="${PROJECT_DIRECTORY}/build"
APP_BUNDLE="${OUTPUT_DIRECTORY}/Liddddd.app"
CONTENTS_DIRECTORY="${APP_BUNDLE}/Contents"
SIGNING_IDENTITY=${CODESIGN_IDENTITY:--}
MODULE_CACHE_DIRECTORY="${TMPDIR:-/tmp}/liddddd-module-cache"
SIGNING_ARGUMENTS=(--force --sign "${SIGNING_IDENTITY}")
SWIFT_BUILD_ARGUMENTS=(--disable-sandbox -c release)
if [[ "${SIGNING_IDENTITY}" != "-" ]]; then
    SIGNING_ARGUMENTS+=(--options runtime --timestamp)
else
    # Local ad-hoc builds explicitly opt into identifier-only helper access.
    # Developer ID builds omit this flag and fail closed when no Team ID exists.
    SWIFT_BUILD_ARGUMENTS+=(-Xswiftc -D -Xswiftc LIDDDDD_ALLOW_ADHOC)
fi

cd "${PROJECT_DIRECTORY}"
SWIFTPM_MODULECACHE_OVERRIDE="${MODULE_CACHE_DIRECTORY}" \
    CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIRECTORY}" \
    swift build "${SWIFT_BUILD_ARGUMENTS[@]}" --product LidddddApp
SWIFTPM_MODULECACHE_OVERRIDE="${MODULE_CACHE_DIRECTORY}" \
    CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIRECTORY}" \
    swift build "${SWIFT_BUILD_ARGUMENTS[@]}" --product LidddddHelper

BIN_DIRECTORY=$(SWIFTPM_MODULECACHE_OVERRIDE="${MODULE_CACHE_DIRECTORY}" \
    CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIRECTORY}" \
    swift build "${SWIFT_BUILD_ARGUMENTS[@]}" --show-bin-path)

rm -rf "${APP_BUNDLE}"
mkdir -p "${CONTENTS_DIRECTORY}/MacOS"
mkdir -p "${CONTENTS_DIRECTORY}/Library/LaunchDaemons"
mkdir -p "${CONTENTS_DIRECTORY}/Library/LaunchServices"
mkdir -p "${CONTENTS_DIRECTORY}/Resources"

cp Resources/Info.plist "${CONTENTS_DIRECTORY}/Info.plist"
cp Resources/Liddddd.icns "${CONTENTS_DIRECTORY}/Resources/Liddddd.icns"
cp Resources/io.github.leejaywon.liddddd.helper.plist \
    "${CONTENTS_DIRECTORY}/Library/LaunchDaemons/io.github.leejaywon.liddddd.helper.plist"
if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
    cp Resources/io.github.leejaywon.liddddd.helper.legacy.plist \
        "${CONTENTS_DIRECTORY}/Resources/io.github.leejaywon.liddddd.helper.legacy.plist"
    cp Resources/manage-local-helper.sh \
        "${CONTENTS_DIRECTORY}/Resources/manage-local-helper.sh"
    chmod 755 "${CONTENTS_DIRECTORY}/Resources/manage-local-helper.sh"
fi
cp "${BIN_DIRECTORY}/LidddddApp" "${CONTENTS_DIRECTORY}/MacOS/Liddddd"
cp "${BIN_DIRECTORY}/LidddddHelper" \
    "${CONTENTS_DIRECTORY}/Library/LaunchServices/LidddddHelper"

xcrun strip -x \
    "${CONTENTS_DIRECTORY}/MacOS/Liddddd" \
    "${CONTENTS_DIRECTORY}/Library/LaunchServices/LidddddHelper"

codesign "${SIGNING_ARGUMENTS[@]}" \
    --identifier io.github.leejaywon.liddddd.helper \
    "${CONTENTS_DIRECTORY}/Library/LaunchServices/LidddddHelper"
codesign "${SIGNING_ARGUMENTS[@]}" \
    --identifier io.github.leejaywon.liddddd \
    "${APP_BUNDLE}"

codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
echo "Built ${APP_BUNDLE}"
