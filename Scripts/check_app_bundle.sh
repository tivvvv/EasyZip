#!/bin/bash

set -euo pipefail

APP_NAME="${APP_NAME:-易压缩}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.tiv.easyzip}"
EXTENSION_BUNDLE_IDENTIFIER="${EXTENSION_BUNDLE_IDENTIFIER:-$BUNDLE_IDENTIFIER.findersync}"
APP_GROUP_IDENTIFIER="${APP_GROUP_IDENTIFIER:-group.com.tiv.easyzip}"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
BUILD_VERSION="${BUILD_VERSION:-1}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
EXPECTED_CODE_SIGN_IDENTITY="${EXPECTED_CODE_SIGN_IDENTITY:-}"
REQUIRE_DEVELOPER_ID="${REQUIRE_DEVELOPER_ID:-0}"
REQUIRE_HARDENED_RUNTIME="${REQUIRE_HARDENED_RUNTIME:-0}"
REQUIRE_STAPLED_TICKET="${REQUIRE_STAPLED_TICKET:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="${1:-${APP_PATH:-$REPO_ROOT/$OUTPUT_DIR/$APP_NAME.app}}"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

if [[ "$APP_PATH" != /* ]]; then
    APP_PATH="$REPO_ROOT/$APP_PATH"
fi

fail() {
    echo "产物完整性检查失败: $*" >&2
    exit 1
}

read_plist_value() {
    local key_path="$1"
    local plist_path="$2"
    "$PLIST_BUDDY" -c "Print $key_path" "$plist_path"
}

assert_plist_value() {
    local key_path="$1"
    local expected="$2"
    local plist_path="$3"
    local actual

    actual="$(read_plist_value "$key_path" "$plist_path")"

    if [[ "$actual" != "$expected" ]]; then
        fail "$plist_path $key_path 应为 $expected, 实际为 $actual"
    fi
}

assert_plist_bool_true() {
    local key_path="$1"
    local plist_path="$2"
    local actual

    actual="$(read_plist_value "$key_path" "$plist_path")"

    if [[ "$actual" != "true" ]]; then
        fail "$plist_path $key_path 应为 true, 实际为 $actual"
    fi
}

assert_file_exists() {
    local path="$1"

    if [[ ! -f "$path" ]]; then
        fail "文件不存在: $path"
    fi
}

assert_executable_exists() {
    local path="$1"

    if [[ ! -x "$path" ]]; then
        fail "可执行文件不存在: $path"
    fi
}

assert_directory_exists() {
    local path="$1"

    if [[ ! -d "$path" ]]; then
        fail "目录不存在: $path"
    fi
}

assert_entitlement_bool_true() {
    local key_path="$1"
    local plist_path="$2"

    assert_plist_bool_true "$key_path" "$plist_path"
}

extract_entitlements() {
    local target="$1"
    local output="$2"

    codesign -d --entitlements :- "$target" > "$output" 2> /dev/null \
        || fail "无法读取签名授权: $target"
    plutil -lint "$output" > /dev/null
}

codesign_details() {
    local target="$1"

    codesign -dv --verbose=4 "$target" 2>&1
}

read_codesign_value() {
    local target="$1"
    local key="$2"

    codesign_details "$target" | awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); exit }'
}

read_codesign_authorities() {
    local target="$1"

    codesign_details "$target" | awk -F= '$1 == "Authority" { print substr($0, length("Authority") + 2) }'
}

read_codesign_authority_chain() {
    local target="$1"

    read_codesign_authorities "$target" | paste -sd '|' -
}

read_codesign_identity_marker() {
    local target="$1"
    local authority_chain
    local signature

    authority_chain="$(read_codesign_authority_chain "$target")"
    if [[ -n "$authority_chain" ]]; then
        echo "$authority_chain"
        return
    fi

    signature="$(read_codesign_value "$target" "Signature")"
    echo "$signature"
}

assert_expected_code_sign_identity() {
    local target="$1"

    if [[ -z "$EXPECTED_CODE_SIGN_IDENTITY" || "$EXPECTED_CODE_SIGN_IDENTITY" == "-" ]]; then
        return
    fi

    if ! read_codesign_authorities "$target" | grep -Fx "$EXPECTED_CODE_SIGN_IDENTITY" > /dev/null; then
        fail "签名身份不匹配: $target"
    fi
}

assert_developer_id_signature() {
    local target="$1"

    if ! read_codesign_authorities "$target" | grep -E '^Developer ID Application:' > /dev/null; then
        fail "不是 Developer ID Application 签名: $target"
    fi
}

assert_hardened_runtime() {
    local target="$1"
    local runtime_version

    runtime_version="$(read_codesign_value "$target" "Runtime Version")"
    if [[ -z "$runtime_version" ]]; then
        fail "未启用 Hardened Runtime: $target"
    fi
}

assert_stapled_ticket() {
    local target="$1"

    xcrun stapler validate "$target" > /dev/null 2>&1 \
        || fail "未通过公证票据校验: $target"
}

assert_signature_consistency() {
    local app_identity
    local extension_identity
    local app_team
    local extension_team

    app_identity="$(read_codesign_identity_marker "$APP_PATH")"
    extension_identity="$(read_codesign_identity_marker "$EXTENSION_PATH")"
    app_team="$(read_codesign_value "$APP_PATH" "TeamIdentifier")"
    extension_team="$(read_codesign_value "$EXTENSION_PATH" "TeamIdentifier")"

    if [[ -z "$app_identity" || -z "$extension_identity" ]]; then
        fail "无法读取签名身份"
    fi

    if [[ "$app_identity" != "$extension_identity" ]]; then
        fail "App 和 Finder Sync extension 签名身份不一致"
    fi

    if [[ "$app_team" != "$extension_team" ]]; then
        fail "App 和 Finder Sync extension TeamIdentifier 不一致"
    fi
}

APP_CONTENTS_PATH="$APP_PATH/Contents"
APP_INFO_PLIST="$APP_CONTENTS_PATH/Info.plist"
APP_EXECUTABLE_PATH="$APP_CONTENTS_PATH/MacOS/EasyZipApp"
APP_PKGINFO_PATH="$APP_CONTENTS_PATH/PkgInfo"
PLUGINS_PATH="$APP_CONTENTS_PATH/PlugIns"
EXTENSION_PATH="$PLUGINS_PATH/EasyZipFinderSyncExtension.appex"
EXTENSION_CONTENTS_PATH="$EXTENSION_PATH/Contents"
EXTENSION_INFO_PLIST="$EXTENSION_CONTENTS_PATH/Info.plist"
EXTENSION_EXECUTABLE_PATH="$EXTENSION_CONTENTS_PATH/MacOS/EasyZipFinderSyncExtension"
EXTENSION_PKGINFO_PATH="$EXTENSION_CONTENTS_PATH/PkgInfo"
APP_ENTITLEMENTS="$(mktemp)"
EXTENSION_ENTITLEMENTS="$(mktemp)"

trap 'rm -f "$APP_ENTITLEMENTS" "$EXTENSION_ENTITLEMENTS"' EXIT

assert_directory_exists "$APP_PATH"
assert_directory_exists "$APP_CONTENTS_PATH"
assert_file_exists "$APP_INFO_PLIST"
assert_file_exists "$APP_PKGINFO_PATH"
assert_executable_exists "$APP_EXECUTABLE_PATH"
assert_directory_exists "$PLUGINS_PATH"
assert_directory_exists "$EXTENSION_PATH"
assert_directory_exists "$EXTENSION_CONTENTS_PATH"
assert_file_exists "$EXTENSION_INFO_PLIST"
assert_file_exists "$EXTENSION_PKGINFO_PATH"
assert_executable_exists "$EXTENSION_EXECUTABLE_PATH"

plutil -lint "$APP_INFO_PLIST" > /dev/null
plutil -lint "$EXTENSION_INFO_PLIST" > /dev/null

assert_plist_value ":CFBundleExecutable" "EasyZipApp" "$APP_INFO_PLIST"
assert_plist_value ":CFBundleIdentifier" "$BUNDLE_IDENTIFIER" "$APP_INFO_PLIST"
assert_plist_value ":CFBundleName" "$APP_NAME" "$APP_INFO_PLIST"
assert_plist_value ":CFBundleDisplayName" "$APP_NAME" "$APP_INFO_PLIST"
assert_plist_value ":CFBundlePackageType" "APPL" "$APP_INFO_PLIST"
assert_plist_value ":CFBundleShortVersionString" "$MARKETING_VERSION" "$APP_INFO_PLIST"
assert_plist_value ":CFBundleVersion" "$BUILD_VERSION" "$APP_INFO_PLIST"
assert_plist_value ":EZAppGroupIdentifier" "$APP_GROUP_IDENTIFIER" "$APP_INFO_PLIST"
assert_plist_bool_true ":LSUIElement" "$APP_INFO_PLIST"
assert_plist_value ":CFBundleURLTypes:0:CFBundleURLName" "$BUNDLE_IDENTIFIER" "$APP_INFO_PLIST"
assert_plist_value ":CFBundleURLTypes:0:CFBundleURLSchemes:0" "easyzip" "$APP_INFO_PLIST"
assert_plist_value ":NSServices:0:NSMessage" "compressSelection" "$APP_INFO_PLIST"
assert_plist_value ":NSServices:0:NSMenuItem:default" "使用易压缩进行压缩" "$APP_INFO_PLIST"
assert_plist_value ":NSServices:1:NSMessage" "extractSelection" "$APP_INFO_PLIST"
assert_plist_value ":NSServices:1:NSMenuItem:default" "使用易压缩进行解压" "$APP_INFO_PLIST"

assert_plist_value ":CFBundleExecutable" "EasyZipFinderSyncExtension" "$EXTENSION_INFO_PLIST"
assert_plist_value ":CFBundleIdentifier" "$EXTENSION_BUNDLE_IDENTIFIER" "$EXTENSION_INFO_PLIST"
assert_plist_value ":CFBundlePackageType" "XPC!" "$EXTENSION_INFO_PLIST"
assert_plist_value ":CFBundleShortVersionString" "$MARKETING_VERSION" "$EXTENSION_INFO_PLIST"
assert_plist_value ":CFBundleVersion" "$BUILD_VERSION" "$EXTENSION_INFO_PLIST"
assert_plist_value ":EZAppGroupIdentifier" "$APP_GROUP_IDENTIFIER" "$EXTENSION_INFO_PLIST"
assert_plist_bool_true ":LSUIElement" "$EXTENSION_INFO_PLIST"
assert_plist_value ":NSExtension:NSExtensionPointIdentifier" "com.apple.FinderSync" "$EXTENSION_INFO_PLIST"
assert_plist_value ":NSExtension:NSExtensionPrincipalClass" "EasyZipFinderSyncExtension.EasyZipFinderSyncExtension" "$EXTENSION_INFO_PLIST"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
extract_entitlements "$APP_PATH" "$APP_ENTITLEMENTS"
extract_entitlements "$EXTENSION_PATH" "$EXTENSION_ENTITLEMENTS"
assert_signature_consistency
assert_expected_code_sign_identity "$APP_PATH"
assert_expected_code_sign_identity "$EXTENSION_PATH"

if [[ "$REQUIRE_DEVELOPER_ID" == "1" ]]; then
    assert_developer_id_signature "$APP_PATH"
    assert_developer_id_signature "$EXTENSION_PATH"
fi

if [[ "$REQUIRE_HARDENED_RUNTIME" == "1" ]]; then
    assert_hardened_runtime "$APP_PATH"
    assert_hardened_runtime "$EXTENSION_PATH"
fi

if [[ "$REQUIRE_STAPLED_TICKET" == "1" ]]; then
    assert_stapled_ticket "$APP_PATH"
fi

assert_entitlement_bool_true ":com.apple.security.app-sandbox" "$APP_ENTITLEMENTS"
assert_entitlement_bool_true ":com.apple.security.app-sandbox" "$EXTENSION_ENTITLEMENTS"
assert_plist_value ":com.apple.security.application-groups:0" "$APP_GROUP_IDENTIFIER" "$APP_ENTITLEMENTS"
assert_plist_value ":com.apple.security.application-groups:0" "$APP_GROUP_IDENTIFIER" "$EXTENSION_ENTITLEMENTS"
assert_entitlement_bool_true ":com.apple.security.files.user-selected.read-write" "$APP_ENTITLEMENTS"
assert_entitlement_bool_true ":com.apple.security.files.user-selected.read-only" "$EXTENSION_ENTITLEMENTS"

echo "产物完整性检查通过: $APP_PATH"
