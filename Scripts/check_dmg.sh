#!/bin/bash

set -euo pipefail

APP_NAME="${APP_NAME:-易压缩}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.tiv.easyzip}"
EXTENSION_BUNDLE_IDENTIFIER="${EXTENSION_BUNDLE_IDENTIFIER:-$BUNDLE_IDENTIFIER.findersync}"
APP_GROUP_IDENTIFIER="${APP_GROUP_IDENTIFIER:-group.com.tiv.easyzip}"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
BUILD_VERSION="${BUILD_VERSION:-1}"
EXPECTED_CODE_SIGN_IDENTITY="${EXPECTED_CODE_SIGN_IDENTITY:-}"
EXPECTED_DMG_CODE_SIGN_IDENTITY="${EXPECTED_DMG_CODE_SIGN_IDENTITY:-}"
REQUIRE_DMG_SIGNATURE="${REQUIRE_DMG_SIGNATURE:-0}"
REQUIRE_DEVELOPER_ID="${REQUIRE_DEVELOPER_ID:-0}"
REQUIRE_HARDENED_RUNTIME="${REQUIRE_HARDENED_RUNTIME:-0}"
REQUIRE_STAPLED_TICKET="${REQUIRE_STAPLED_TICKET:-0}"
REQUIRE_APP_STAPLED_TICKET="${REQUIRE_APP_STAPLED_TICKET:-0}"

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

codesign_details() {
    local target="$1"

    codesign -dv --verbose=4 "$target" 2>&1
}

read_codesign_authorities() {
    local target="$1"

    codesign_details "$target" | awk -F= '$1 == "Authority" { print substr($0, length("Authority") + 2) }'
}

assert_dmg_signature() {
    codesign --verify --verbose=2 "$DMG_PATH" > /dev/null 2>&1 \
        || fail "DMG 签名校验失败: $DMG_PATH"
}

assert_dmg_code_sign_identity() {
    if [[ -z "$EXPECTED_DMG_CODE_SIGN_IDENTITY" || "$EXPECTED_DMG_CODE_SIGN_IDENTITY" == "-" ]]; then
        return
    fi

    if ! read_codesign_authorities "$DMG_PATH" | grep -Fx "$EXPECTED_DMG_CODE_SIGN_IDENTITY" > /dev/null; then
        fail "DMG 签名身份不匹配: $DMG_PATH"
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

if [[ "$REQUIRE_STAPLED_TICKET" == "1" ]]; then
    xcrun stapler validate "$DMG_PATH" > /dev/null 2>&1 \
        || fail "未通过公证票据校验: $DMG_PATH"
fi

if [[ "$REQUIRE_DMG_SIGNATURE" == "1" || -n "$EXPECTED_DMG_CODE_SIGN_IDENTITY" ]]; then
    assert_dmg_signature
    assert_dmg_code_sign_identity
fi

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
APP_GROUP_IDENTIFIER="$APP_GROUP_IDENTIFIER" \
MARKETING_VERSION="$MARKETING_VERSION" \
BUILD_VERSION="$BUILD_VERSION" \
EXPECTED_CODE_SIGN_IDENTITY="$EXPECTED_CODE_SIGN_IDENTITY" \
REQUIRE_DEVELOPER_ID="$REQUIRE_DEVELOPER_ID" \
REQUIRE_HARDENED_RUNTIME="$REQUIRE_HARDENED_RUNTIME" \
REQUIRE_STAPLED_TICKET="$REQUIRE_APP_STAPLED_TICKET" \
"$SCRIPT_DIR/check_app_bundle.sh" "$APP_PATH"

echo "DMG 完整性检查通过: $DMG_PATH"
