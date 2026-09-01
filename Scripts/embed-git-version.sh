#!/bin/bash
set -euo pipefail

PLIST="${DERIVED_FILE_DIR}/Nab-Info.plist"
BUNDLE_VERSION="${CURRENT_PROJECT_VERSION}"
GIT_VERSION="unknown"

cd "${SRCROOT}"

if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    GIT_VERSION=$(git describe --always --dirty --abbrev=7 2>/dev/null || echo "unknown")
    BUNDLE_VERSION=$(git rev-list --count HEAD)
fi

case "${BUNDLE_VERSION}" in
    "" | *[!0-9]*)
        echo "error: bundle version must contain only digits: ${BUNDLE_VERSION}" >&2
        exit 1
        ;;
esac

/usr/bin/plutil -create xml1 "${PLIST}"
/usr/bin/plutil -insert CFBundleVersion -string "${BUNDLE_VERSION}" "${PLIST}"
/usr/bin/plutil -insert NabGitVersion -string "${GIT_VERSION}" "${PLIST}"
/usr/bin/plutil -insert LSUIElement -bool YES "${PLIST}"

echo "Generated Info.plist with bundle version ${BUNDLE_VERSION} and Git version ${GIT_VERSION}"
