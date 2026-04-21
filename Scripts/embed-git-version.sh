#!/bin/bash
set -euo pipefail

PLIST="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"
if [[ ! -f "${PLIST}" ]]; then
    echo "warning: Info.plist not found at ${PLIST}, skipping git version embed"
    exit 0
fi

cd "${SRCROOT}"

if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "warning: not a git checkout, skipping git version embed"
    exit 0
fi

GIT_VERSION=$(git describe --always --dirty --abbrev=7 2>/dev/null || echo "unknown")

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${GIT_VERSION}" "${PLIST}"

echo "Embedded git version into CFBundleVersion: ${GIT_VERSION}"
