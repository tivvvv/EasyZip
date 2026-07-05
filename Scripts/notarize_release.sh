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
STAPLE_PATH="${STAPLE_PATH:-}"
STAPLE_PATH_INPUT="$STAPLE_PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUBMISSION_PATH="${1:-${SUBMISSION_PATH:-${DMG_PATH:-$REPO_ROOT/$RELEASE_DIR/$ARCHIVE_BASENAME.dmg}}}"
STAPLE_PATH_INPUT="${2:-$STAPLE_PATH_INPUT}"

fail() {
    echo "公证失败: $*" >&2
    exit 1
}

normalize_path() {
    local path="$1"

    if [[ "$path" == /* ]]; then
        echo "$path"
    else
        echo "$REPO_ROOT/$path"
    fi
}

SUBMISSION_PATH="$(normalize_path "$SUBMISSION_PATH")"

if [[ -z "$STAPLE_PATH_INPUT" ]]; then
    case "$SUBMISSION_PATH" in
        *.zip)
            STAPLE_PATH="-"
            ;;
        *)
            STAPLE_PATH="$SUBMISSION_PATH"
            ;;
    esac
elif [[ "$STAPLE_PATH_INPUT" == "-" ]]; then
    STAPLE_PATH="-"
else
    STAPLE_PATH="$(normalize_path "$STAPLE_PATH_INPUT")"
fi

if [[ ! -e "$SUBMISSION_PATH" ]]; then
    fail "文件不存在: $SUBMISSION_PATH"
fi

if [[ "$STAPLE_PATH" != "-" && ! -e "$STAPLE_PATH" ]]; then
    fail "staple 目标不存在: $STAPLE_PATH"
fi

if ! xcrun notarytool --help > /dev/null 2>&1; then
    fail "找不到 notarytool"
fi

if [[ -n "$NOTARY_KEYCHAIN_PROFILE" ]]; then
    xcrun notarytool submit "$SUBMISSION_PATH" \
        --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
        --wait
else
    if [[ -z "$APPLE_ID" || -z "$APPLE_TEAM_ID" || -z "$APPLE_APP_SPECIFIC_PASSWORD" ]]; then
        fail "需要设置 NOTARY_KEYCHAIN_PROFILE 或 APPLE_ID, APPLE_TEAM_ID, APPLE_APP_SPECIFIC_PASSWORD"
    fi

    xcrun notarytool submit "$SUBMISSION_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_SPECIFIC_PASSWORD" \
        --wait
fi

if [[ "$STAPLE_PATH" == "-" ]]; then
    echo "跳过 staple: $SUBMISSION_PATH"
else
    xcrun stapler staple "$STAPLE_PATH"
    xcrun stapler validate "$STAPLE_PATH"
fi

echo "公证完成: $SUBMISSION_PATH"
