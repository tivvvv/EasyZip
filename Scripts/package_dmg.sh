#!/bin/bash

set -euo pipefail

APP_NAME="${APP_NAME:-易压缩}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.tiv.easyzip}"
EXTENSION_BUNDLE_IDENTIFIER="${EXTENSION_BUNDLE_IDENTIFIER:-$BUNDLE_IDENTIFIER.findersync}"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
BUILD_VERSION="${BUILD_VERSION:-1}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
RELEASE_DIR="${RELEASE_DIR:-dist/release}"
ARCHIVE_BASENAME="${ARCHIVE_BASENAME:-EasyZip-$MARKETING_VERSION-$BUILD_VERSION}"
VOLUME_NAME="${VOLUME_NAME:-$APP_NAME $MARKETING_VERSION}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="${1:-${APP_PATH:-$REPO_ROOT/$OUTPUT_DIR/$APP_NAME.app}}"
DMG_PATH="${2:-${DMG_PATH:-$REPO_ROOT/$RELEASE_DIR/$ARCHIVE_BASENAME.dmg}}"
STAGING_DIR=""

fail() {
    echo "DMG 打包失败: $*" >&2
    exit 1
}

cleanup() {
    if [[ -n "$STAGING_DIR" ]]; then
        rm -rf "$STAGING_DIR"
    fi
}

normalize_path() {
    local path="$1"

    if [[ "$path" == /* ]]; then
        echo "$path"
    else
        echo "$REPO_ROOT/$path"
    fi
}

ensure_path_inside_repo() {
    local path="$1"

    case "$path" in
        "$REPO_ROOT"/*) ;;
        *) fail "路径不在仓库内: $path" ;;
    esac
}

trap cleanup EXIT

APP_PATH="$(normalize_path "$APP_PATH")"
DMG_PATH="$(normalize_path "$DMG_PATH")"
STAGING_DIR="$(dirname "$DMG_PATH")/$ARCHIVE_BASENAME-dmg"

ensure_path_inside_repo "$DMG_PATH"
ensure_path_inside_repo "$STAGING_DIR"

if [[ "$DMG_PATH" == "$REPO_ROOT" || "$STAGING_DIR" == "$REPO_ROOT" || "$STAGING_DIR" == "/" ]]; then
    fail "输出路径不安全"
fi

if [[ ! -d "$APP_PATH" ]]; then
    fail "应用不存在: $APP_PATH"
fi

APP_NAME="$APP_NAME" \
BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
EXTENSION_BUNDLE_IDENTIFIER="$EXTENSION_BUNDLE_IDENTIFIER" \
MARKETING_VERSION="$MARKETING_VERSION" \
BUILD_VERSION="$BUILD_VERSION" \
"$SCRIPT_DIR/check_app_bundle.sh" "$APP_PATH"

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR" "$(dirname "$DMG_PATH")"

ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG_PATH" > /dev/null

APP_NAME="$APP_NAME" \
BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
EXTENSION_BUNDLE_IDENTIFIER="$EXTENSION_BUNDLE_IDENTIFIER" \
MARKETING_VERSION="$MARKETING_VERSION" \
BUILD_VERSION="$BUILD_VERSION" \
"$SCRIPT_DIR/check_dmg.sh" "$DMG_PATH"

echo "DMG 产物: $DMG_PATH"
