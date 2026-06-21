#!/bin/bash

set -euo pipefail

MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
BUILD_VERSION="${BUILD_VERSION:-1}"
RELEASE_DIR="${RELEASE_DIR:-dist/release}"
ARCHIVE_BASENAME="${ARCHIVE_BASENAME:-EasyZip-$MARKETING_VERSION-$BUILD_VERSION}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DMG_PATH="${1:-${DMG_PATH:-$REPO_ROOT/$RELEASE_DIR/$ARCHIVE_BASENAME.dmg}}"

fail() {
    echo "公证失败: $*" >&2
    exit 1
}

if [[ "$DMG_PATH" != /* ]]; then
    DMG_PATH="$REPO_ROOT/$DMG_PATH"
fi

if [[ ! -f "$DMG_PATH" ]]; then
    fail "文件不存在: $DMG_PATH"
fi

if ! xcrun notarytool --help > /dev/null 2>&1; then
    fail "找不到 notarytool"
fi

if [[ -n "$NOTARY_KEYCHAIN_PROFILE" ]]; then
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
        --wait
else
    if [[ -z "$APPLE_ID" || -z "$APPLE_TEAM_ID" || -z "$APPLE_APP_SPECIFIC_PASSWORD" ]]; then
        fail "需要设置 NOTARY_KEYCHAIN_PROFILE 或 APPLE_ID, APPLE_TEAM_ID, APPLE_APP_SPECIFIC_PASSWORD"
    fi

    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_SPECIFIC_PASSWORD" \
        --wait
fi

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "公证完成: $DMG_PATH"
