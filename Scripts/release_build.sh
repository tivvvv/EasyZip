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
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
APP_CODE_SIGN_ENTITLEMENTS="${APP_CODE_SIGN_ENTITLEMENTS:-}"
EXTENSION_CODE_SIGN_ENTITLEMENTS="${EXTENSION_CODE_SIGN_ENTITLEMENTS:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$REPO_ROOT/$OUTPUT_DIR/$APP_NAME.app"
RELEASE_PATH="$REPO_ROOT/$RELEASE_DIR"
ZIP_PATH="$RELEASE_PATH/$ARCHIVE_BASENAME.zip"
CHECKSUM_PATH="$ZIP_PATH.sha256"
DMG_PATH="$RELEASE_PATH/$ARCHIVE_BASENAME.dmg"
DMG_CHECKSUM_PATH="$DMG_PATH.sha256"
MANIFEST_PATH="$RELEASE_PATH/$ARCHIVE_BASENAME.txt"

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

write_manifest() {
    local zip_checksum
    local dmg_checksum
    local git_commit

    zip_checksum="$(cut -d ' ' -f 1 "$CHECKSUM_PATH")"
    dmg_checksum="$(cut -d ' ' -f 1 "$DMG_CHECKSUM_PATH")"
    git_commit="$(git rev-parse HEAD)"

    {
        echo "EasyZip release build"
        echo "App name: $APP_NAME"
        echo "Bundle identifier: $BUNDLE_IDENTIFIER"
        echo "Extension bundle identifier: $EXTENSION_BUNDLE_IDENTIFIER"
        echo "Marketing version: $MARKETING_VERSION"
        echo "Build version: $BUILD_VERSION"
        echo "Code sign identity: $CODE_SIGN_IDENTITY"
        echo "Zip archive: $(basename "$ZIP_PATH")"
        echo "Zip SHA256: $zip_checksum"
        echo "DMG archive: $(basename "$DMG_PATH")"
        echo "DMG SHA256: $dmg_checksum"
        echo "Built at UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "Git commit: $git_commit"
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
CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
APP_CODE_SIGN_ENTITLEMENTS="$APP_CODE_SIGN_ENTITLEMENTS" \
EXTENSION_CODE_SIGN_ENTITLEMENTS="$EXTENSION_CODE_SIGN_ENTITLEMENTS" \
"$SCRIPT_DIR/build_app_bundle.sh"

APP_NAME="$APP_NAME" \
BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
EXTENSION_BUNDLE_IDENTIFIER="$EXTENSION_BUNDLE_IDENTIFIER" \
MARKETING_VERSION="$MARKETING_VERSION" \
BUILD_VERSION="$BUILD_VERSION" \
"$SCRIPT_DIR/check_app_bundle.sh" "$APP_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$CHECKSUM_PATH"

APP_NAME="$APP_NAME" \
BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
EXTENSION_BUNDLE_IDENTIFIER="$EXTENSION_BUNDLE_IDENTIFIER" \
MARKETING_VERSION="$MARKETING_VERSION" \
BUILD_VERSION="$BUILD_VERSION" \
OUTPUT_DIR="$OUTPUT_DIR" \
RELEASE_DIR="$RELEASE_DIR" \
ARCHIVE_BASENAME="$ARCHIVE_BASENAME" \
"$SCRIPT_DIR/package_dmg.sh" "$APP_PATH" "$DMG_PATH"

shasum -a 256 "$DMG_PATH" > "$DMG_CHECKSUM_PATH"
write_manifest

echo "Zip 产物: $ZIP_PATH"
echo "Zip 校验文件: $CHECKSUM_PATH"
echo "DMG 产物: $DMG_PATH"
echo "DMG 校验文件: $DMG_CHECKSUM_PATH"
echo "构建摘要: $MANIFEST_PATH"
