#!/bin/zsh

set -euo pipefail

ACTION=${1:-}
APP_BUNDLE=/Applications/Liddddd.app
HELPER_SOURCE="${APP_BUNDLE}/Contents/Library/LaunchServices/LidddddHelper"
PLIST_SOURCE="${APP_BUNDLE}/Contents/Resources/io.github.leejaywon.liddddd.helper.legacy.plist"
HELPER_DESTINATION=/Library/PrivilegedHelperTools/io.github.leejaywon.liddddd.helper
PLIST_DESTINATION=/Library/LaunchDaemons/io.github.leejaywon.liddddd.helper.plist
STATE_DIRECTORY="/Library/Application Support/Liddddd"
STATE_FILE="${STATE_DIRECTORY}/active-session.json"
SERVICE_TARGET=system/io.github.leejaywon.liddddd.helper

case "${ACTION}" in
    install|repair|uninstall) ;;
    *)
        echo "Unsupported helper management action." >&2
        exit 9
        ;;
esac

if [[ "${ACTION}" == "uninstall" ]]; then
    /bin/launchctl bootout "${SERVICE_TARGET}" >/dev/null 2>&1 || true
    if [[ -f "${STATE_FILE}" ]]; then
        /usr/bin/pmset -a disablesleep 0
    fi
    /bin/rm -f "${PLIST_DESTINATION}"
    /bin/rm -f "${HELPER_DESTINATION}"
    /bin/rm -f "${STATE_DIRECTORY}/active-session.json"
    /bin/rm -f "${STATE_DIRECTORY}/last-stop.json"
    /bin/rmdir "${STATE_DIRECTORY}" >/dev/null 2>&1 || true
    exit 0
fi

if [[ ! -f "${HELPER_SOURCE}" || ! -f "${PLIST_SOURCE}" ]]; then
    echo "Liddddd installation files are missing." >&2
    exit 10
fi

if [[ "${ACTION}" == "install" ]] \
    && [[ -e "${HELPER_DESTINATION}" || -e "${PLIST_DESTINATION}" ]]; then
    echo "A Liddddd helper installation already exists." >&2
    exit 11
fi

if [[ "${ACTION}" == "repair" ]]; then
    /bin/launchctl bootout "${SERVICE_TARGET}" >/dev/null 2>&1 || true
fi

/usr/bin/install -o root -g wheel -m 755 "${HELPER_SOURCE}" "${HELPER_DESTINATION}"
/usr/bin/install -o root -g wheel -m 644 "${PLIST_SOURCE}" "${PLIST_DESTINATION}"

if ! /bin/launchctl bootstrap system "${PLIST_DESTINATION}"; then
    if [[ -f "${STATE_FILE}" ]]; then
        /usr/bin/pmset -a disablesleep 0 || true
        /bin/rm -f "${STATE_FILE}"
    fi
    /bin/rm -f "${PLIST_DESTINATION}"
    /bin/rm -f "${HELPER_DESTINATION}"
    exit 12
fi

/bin/launchctl enable "${SERVICE_TARGET}"
