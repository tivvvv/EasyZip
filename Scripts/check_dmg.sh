#!/bin/bash

set -euo pipefail

APP_NAME="${APP_NAME:-易压缩}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.tiv.easyzip}"
EXTENSION_BUNDLE_IDENTIFIER="${EXTENSION_BUNDLE_IDENTIFIER:-$BUNDLE_IDENTIFIER.findersync}"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
BUILD_VERSION="${BUILD_VERSION:-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DMG_PATH="${1:-${DMG_PATH:-}}"
MOUNT_POINT=""
DMG_ATTACHED=0

fail() {
    echo "DMG 完整性检查失败: $*" >&2
    exit 1
}

cleanup() {
    if [[ "$DMG_ATTACHED" == "1" && -n "$MOUNT_POINT" ]]; then
        hdiutil detach "$MOUNT_POINT" -quiet || true
    fi

    if [[ -n "$MOUNT_POINT" ]]; then
        rmdir "$MOUNT_POINT" 2> /dev/null || true
    fi
}

trap cleanup EXIT

if [[ -z "$DMG_PATH" ]]; then
    fail "未提供 DMG 路径"
fi

if [[ "$DMG_PATH" != /* ]]; then
    DMG_PATH="$REPO_ROOT/$DMG_PATH"
fi

if [[ ! -f "$DMG_PATH" ]]; then
    fail "文件不存在: $DMG_PATH"
fi

hdiutil verify "$DMG_PATH" > /dev/null

MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/easyzip-dmg.XXXXXX")"
hdiutil attach "$DMG_PATH" -readonly -nobrowse -mountpoint "$MOUNT_POINT" > /dev/null
DMG_ATTACHED=1

APP_PATH="$MOUNT_POINT/$APP_NAME.app"
APPLICATIONS_LINK="$MOUNT_POINT/Applications"

if [[ ! -d "$APP_PATH" ]]; then
    fail "应用不存在: $APP_PATH"
fi

if [[ ! -L "$APPLICATIONS_LINK" && ! -d "$APPLICATIONS_LINK" ]]; then
    fail "Applications 入口不存在: $APPLICATIONS_LINK"
fi

APP_NAME="$APP_NAME" \
BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
EXTENSION_BUNDLE_IDENTIFIER="$EXTENSION_BUNDLE_IDENTIFIER" \
MARKETING_VERSION="$MARKETING_VERSION" \
BUILD_VERSION="$BUILD_VERSION" \
"$SCRIPT_DIR/check_app_bundle.sh" "$APP_PATH"

echo "DMG 完整性检查通过: $DMG_PATH"
