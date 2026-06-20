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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$REPO_ROOT/$OUTPUT_DIR/$APP_NAME.app"
RELEASE_PATH="$REPO_ROOT/$RELEASE_DIR"
ZIP_PATH="$RELEASE_PATH/$ARCHIVE_BASENAME.zip"
CHECKSUM_PATH="$ZIP_PATH.sha256"
MANIFEST_PATH="$RELEASE_PATH/$ARCHIVE_BASENAME.txt"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

fail() {
    echo "发布构建失败: $*" >&2
    exit 1
}

ensure_path_inside_repo() {
    local path="$1"
    case "$path" in
        "$REPO_ROOT"/*) ;;
        *) fail "路径不在仓库内: $path" ;;
    esac
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

write_manifest() {
    {
        echo "EasyZip release build"
        echo "App name: $APP_NAME"
        echo "Bundle identifier: $BUNDLE_IDENTIFIER"
        echo "Extension bundle identifier: $EXTENSION_BUNDLE_IDENTIFIER"
        echo "Marketing version: $MARKETING_VERSION"
        echo "Build version: $BUILD_VERSION"
        echo "Archive: $(basename "$ZIP_PATH")"
        echo "Checksum: $(cut -d ' ' -f 1 "$CHECKSUM_PATH")"
        echo "Built at UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "Git commit: $(git rev-parse --short HEAD)"
    } > "$MANIFEST_PATH"
}

ensure_path_inside_repo "$APP_PATH"
ensure_path_inside_repo "$RELEASE_PATH"

if [[ "$APP_PATH" == "$REPO_ROOT" || "$RELEASE_PATH" == "$REPO_ROOT" ]]; then
    fail "输出路径不安全"
fi

cd "$REPO_ROOT"

rm -rf "$RELEASE_PATH"
mkdir -p "$RELEASE_PATH"

CONFIGURATION=release \
APP_NAME="$APP_NAME" \
BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
EXTENSION_BUNDLE_IDENTIFIER="$EXTENSION_BUNDLE_IDENTIFIER" \
MARKETING_VERSION="$MARKETING_VERSION" \
BUILD_VERSION="$BUILD_VERSION" \
OUTPUT_DIR="$OUTPUT_DIR" \
"$SCRIPT_DIR/build_app_bundle.sh"

APP_CONTENTS_PATH="$APP_PATH/Contents"
APP_INFO_PLIST="$APP_CONTENTS_PATH/Info.plist"
APP_EXECUTABLE_PATH="$APP_CONTENTS_PATH/MacOS/EasyZipApp"
PLUGINS_PATH="$APP_CONTENTS_PATH/PlugIns"
EXTENSION_PATH="$PLUGINS_PATH/EasyZipFinderSyncExtension.appex"
EXTENSION_CONTENTS_PATH="$EXTENSION_PATH/Contents"
EXTENSION_INFO_PLIST="$EXTENSION_CONTENTS_PATH/Info.plist"
EXTENSION_EXECUTABLE_PATH="$EXTENSION_CONTENTS_PATH/MacOS/EasyZipFinderSyncExtension"

assert_directory_exists "$APP_PATH"
assert_file_exists "$APP_INFO_PLIST"
assert_executable_exists "$APP_EXECUTABLE_PATH"
assert_directory_exists "$PLUGINS_PATH"
assert_directory_exists "$EXTENSION_PATH"
assert_file_exists "$EXTENSION_INFO_PLIST"
assert_executable_exists "$EXTENSION_EXECUTABLE_PATH"

assert_plist_value ":CFBundleExecutable" "EasyZipApp" "$APP_INFO_PLIST"
assert_plist_value ":CFBundleIdentifier" "$BUNDLE_IDENTIFIER" "$APP_INFO_PLIST"
assert_plist_value ":CFBundleShortVersionString" "$MARKETING_VERSION" "$APP_INFO_PLIST"
assert_plist_value ":CFBundleVersion" "$BUILD_VERSION" "$APP_INFO_PLIST"
assert_plist_bool_true ":LSUIElement" "$APP_INFO_PLIST"
assert_plist_value ":CFBundleURLTypes:0:CFBundleURLSchemes:0" "easyzip" "$APP_INFO_PLIST"
assert_plist_value ":NSServices:0:NSMessage" "compressSelection" "$APP_INFO_PLIST"
assert_plist_value ":NSServices:1:NSMessage" "extractSelection" "$APP_INFO_PLIST"

assert_plist_value ":CFBundleExecutable" "EasyZipFinderSyncExtension" "$EXTENSION_INFO_PLIST"
assert_plist_value ":CFBundleIdentifier" "$EXTENSION_BUNDLE_IDENTIFIER" "$EXTENSION_INFO_PLIST"
assert_plist_value ":CFBundleShortVersionString" "$MARKETING_VERSION" "$EXTENSION_INFO_PLIST"
assert_plist_value ":CFBundleVersion" "$BUILD_VERSION" "$EXTENSION_INFO_PLIST"
assert_plist_value ":NSExtension:NSExtensionPointIdentifier" "com.apple.FinderSync" "$EXTENSION_INFO_PLIST"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$CHECKSUM_PATH"
write_manifest

echo "发布产物: $ZIP_PATH"
echo "校验文件: $CHECKSUM_PATH"
echo "构建摘要: $MANIFEST_PATH"
