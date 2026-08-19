#!/bin/zsh

set -euo pipefail

SCRIPT_DIRECTORY=${0:A:h}
PROJECT_DIRECTORY=${SCRIPT_DIRECTORY:h}
APP_BUNDLE=${1:-"${PROJECT_DIRECTORY}/build/Liddddd.app"}

if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "App bundle not found: ${APP_BUNDLE}" >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy \
    -c "Print :CFBundleShortVersionString" \
    "${APP_BUNDLE}/Contents/Info.plist")
OUTPUT_DMG=${2:-"${PROJECT_DIRECTORY}/build/Liddddd-${VERSION}.dmg"}
VOLUME_NAME=Liddddd
WORK_DIRECTORY=$(mktemp -d "${TMPDIR:-/tmp}/liddddd-dmg.XXXXXX")
SOURCE_DIRECTORY="${WORK_DIRECTORY}/source"
MOUNT_DIRECTORY="${WORK_DIRECTORY}/mount"
READ_WRITE_DMG="${WORK_DIRECTORY}/Liddddd-read-write.dmg"
ATTACHED_DEVICE=""

cleanup() {
    set +e
    if [[ -n "${ATTACHED_DEVICE}" ]]; then
        hdiutil detach "${ATTACHED_DEVICE}" -quiet
    fi
    rm -rf "${WORK_DIRECTORY}"
}
trap cleanup EXIT

mkdir -p "${SOURCE_DIRECTORY}" "${MOUNT_DIRECTORY}" "${OUTPUT_DMG:h}"
/usr/bin/ditto "${APP_BUNDLE}" "${SOURCE_DIRECTORY}/Liddddd.app"
ln -s /Applications "${SOURCE_DIRECTORY}/Applications"

hdiutil create \
    -quiet \
    -fs HFS+ \
    -volname "${VOLUME_NAME}" \
    -srcfolder "${SOURCE_DIRECTORY}" \
    -format UDRW \
    -ov \
    "${READ_WRITE_DMG}"

ATTACH_OUTPUT=$(hdiutil attach \
    -readwrite \
    -noverify \
    -noautoopen \
    -mountpoint "${MOUNT_DIRECTORY}" \
    "${READ_WRITE_DMG}")
ATTACHED_DEVICE=$(print -r -- "${ATTACH_OUTPUT}" | awk 'END { print $1 }')

if [[ -z "${ATTACHED_DEVICE}" ]]; then
    echo "Could not identify the mounted disk image device." >&2
    exit 1
fi

osascript <<APPLESCRIPT
tell application "Finder"
    set mountedFolder to folder (POSIX file "${MOUNT_DIRECTORY}" as text)
    open mountedFolder
    set dmgWindow to container window of mountedFolder
    set current view of dmgWindow to icon view
    set toolbar visible of dmgWindow to false
    set statusbar visible of dmgWindow to false
    set pathbar visible of dmgWindow to false
    set bounds of dmgWindow to {100, 100, 660, 460}
    set arrangement of icon view options of dmgWindow to not arranged
    set icon size of icon view options of dmgWindow to 128
    set text size of icon view options of dmgWindow to 14
    set position of item "Liddddd.app" of mountedFolder to {155, 180}
    set position of item "Applications" of mountedFolder to {405, 180}
    update mountedFolder without registering applications
    delay 2
    close dmgWindow
end tell
APPLESCRIPT

/bin/rm -rf \
    "${MOUNT_DIRECTORY}/.fseventsd" \
    "${MOUNT_DIRECTORY}/.Spotlight-V100" \
    "${MOUNT_DIRECTORY}/.Trashes"
sync
hdiutil detach "${ATTACHED_DEVICE}" -quiet
ATTACHED_DEVICE=""

hdiutil convert \
    "${READ_WRITE_DMG}" \
    -quiet \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "${OUTPUT_DMG}"
hdiutil verify "${OUTPUT_DMG}"

echo "Built ${OUTPUT_DMG}"
