#!/bin/bash

set -euo pipefail

APP_NAME="${APP_NAME:-易压缩}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.tiv.easyzip}"
EXTENSION_BUNDLE_IDENTIFIER="${EXTENSION_BUNDLE_IDENTIFIER:-$BUNDLE_IDENTIFIER.findersync}"
APP_GROUP_IDENTIFIER="${APP_GROUP_IDENTIFIER:-group.com.tiv.easyzip}"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
BUILD_VERSION="${BUILD_VERSION:-1}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"

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
assert_entitlement_bool_true ":com.apple.security.app-sandbox" "$APP_ENTITLEMENTS"
assert_entitlement_bool_true ":com.apple.security.app-sandbox" "$EXTENSION_ENTITLEMENTS"
assert_plist_value ":com.apple.security.application-groups:0" "$APP_GROUP_IDENTIFIER" "$APP_ENTITLEMENTS"
assert_plist_value ":com.apple.security.application-groups:0" "$APP_GROUP_IDENTIFIER" "$EXTENSION_ENTITLEMENTS"
assert_entitlement_bool_true ":com.apple.security.files.user-selected.read-write" "$APP_ENTITLEMENTS"
assert_entitlement_bool_true ":com.apple.security.files.user-selected.read-only" "$EXTENSION_ENTITLEMENTS"

echo "产物完整性检查通过: $APP_PATH"
