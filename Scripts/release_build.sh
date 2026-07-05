#!/bin/bash

set -euo pipefail

APP_NAME="${APP_NAME:-易压缩}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.tiv.easyzip}"
EXTENSION_BUNDLE_IDENTIFIER="${EXTENSION_BUNDLE_IDENTIFIER:-$BUNDLE_IDENTIFIER.findersync}"
APP_GROUP_IDENTIFIER="${APP_GROUP_IDENTIFIER:-group.com.tiv.easyzip}"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
BUILD_VERSION="${BUILD_VERSION:-1}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
RELEASE_DIR="${RELEASE_DIR:-dist/release}"
ARCHIVE_BASENAME="${ARCHIVE_BASENAME:-EasyZip-$MARKETING_VERSION-$BUILD_VERSION}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
DMG_CODE_SIGN_IDENTITY="${DMG_CODE_SIGN_IDENTITY:-}"
EXPECTED_CODE_SIGN_IDENTITY="${EXPECTED_CODE_SIGN_IDENTITY:-}"
EXPECTED_DMG_CODE_SIGN_IDENTITY="${EXPECTED_DMG_CODE_SIGN_IDENTITY:-}"
APP_CODE_SIGN_ENTITLEMENTS="${APP_CODE_SIGN_ENTITLEMENTS:-}"
EXTENSION_CODE_SIGN_ENTITLEMENTS="${EXTENSION_CODE_SIGN_ENTITLEMENTS:-}"
RELEASE_NOTARIZE="${RELEASE_NOTARIZE:-0}"
RELEASE_REQUIRE_DEVELOPER_ID="${RELEASE_REQUIRE_DEVELOPER_ID:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$REPO_ROOT/$OUTPUT_DIR/$APP_NAME.app"
RELEASE_PATH="$REPO_ROOT/$RELEASE_DIR"
ZIP_PATH="$RELEASE_PATH/$ARCHIVE_BASENAME.zip"
CHECKSUM_PATH="$ZIP_PATH.sha256"
DMG_PATH="$RELEASE_PATH/$ARCHIVE_BASENAME.dmg"
DMG_CHECKSUM_PATH="$DMG_PATH.sha256"
MANIFEST_PATH="$RELEASE_PATH/$ARCHIVE_BASENAME.txt"
NOTARY_ZIP_PATH="$RELEASE_PATH/$ARCHIVE_BASENAME-notary.zip"
ZIP_CHECK_DIR=""
REQUIRE_DEVELOPER_ID="0"
REQUIRE_HARDENED_RUNTIME="0"
REQUIRE_DMG_SIGNATURE="0"
APP_STAPLED_REQUIRED="0"
NOTARIZATION_STATUS="skipped"

fail() {
    echo "发布构建失败: $*" >&2
    exit 1
}

cleanup() {
    if [[ -n "$ZIP_CHECK_DIR" && -d "$ZIP_CHECK_DIR" ]]; then
        rm -rf "$ZIP_CHECK_DIR"
    fi
}

is_enabled() {
    case "$1" in
        1 | true | TRUE | yes | YES)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

ensure_path_inside_repo() {
    local path="$1"
    case "$path" in
        "$REPO_ROOT"/*) ;;
        *) fail "路径不在仓库内: $path" ;;
    esac
}

artifact_size() {
    local path="$1"

    wc -c < "$path" | tr -d '[:space:]'
}

write_checksum() {
    local artifact_path="$1"
    local checksum_path="$2"

    shasum -a 256 "$artifact_path" > "$checksum_path"
    shasum -a 256 -c "$checksum_path" > /dev/null
}

run_app_bundle_check() {
    local target_app_path="$1"
    local require_stapled_ticket="${2:-0}"

    APP_NAME="$APP_NAME" \
    BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
    EXTENSION_BUNDLE_IDENTIFIER="$EXTENSION_BUNDLE_IDENTIFIER" \
    APP_GROUP_IDENTIFIER="$APP_GROUP_IDENTIFIER" \
    MARKETING_VERSION="$MARKETING_VERSION" \
    BUILD_VERSION="$BUILD_VERSION" \
    EXPECTED_CODE_SIGN_IDENTITY="$EXPECTED_CODE_SIGN_IDENTITY" \
    EXPECTED_DMG_CODE_SIGN_IDENTITY="$EXPECTED_DMG_CODE_SIGN_IDENTITY" \
    REQUIRE_DMG_SIGNATURE="$REQUIRE_DMG_SIGNATURE" \
    REQUIRE_DEVELOPER_ID="$REQUIRE_DEVELOPER_ID" \
    REQUIRE_HARDENED_RUNTIME="$REQUIRE_HARDENED_RUNTIME" \
    REQUIRE_STAPLED_TICKET="$require_stapled_ticket" \
    "$SCRIPT_DIR/check_app_bundle.sh" "$target_app_path"
}

run_dmg_check() {
    local require_dmg_stapled_ticket="${1:-0}"
    local require_app_stapled_ticket="${2:-0}"

    APP_NAME="$APP_NAME" \
    BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
    EXTENSION_BUNDLE_IDENTIFIER="$EXTENSION_BUNDLE_IDENTIFIER" \
    APP_GROUP_IDENTIFIER="$APP_GROUP_IDENTIFIER" \
    MARKETING_VERSION="$MARKETING_VERSION" \
    BUILD_VERSION="$BUILD_VERSION" \
    EXPECTED_CODE_SIGN_IDENTITY="$EXPECTED_CODE_SIGN_IDENTITY" \
    REQUIRE_DEVELOPER_ID="$REQUIRE_DEVELOPER_ID" \
    REQUIRE_HARDENED_RUNTIME="$REQUIRE_HARDENED_RUNTIME" \
    REQUIRE_STAPLED_TICKET="$require_dmg_stapled_ticket" \
    REQUIRE_APP_STAPLED_TICKET="$require_app_stapled_ticket" \
    "$SCRIPT_DIR/check_dmg.sh" "$DMG_PATH"
}

check_zip_artifact() {
    local require_stapled_ticket="${1:-0}"
    local extracted_app_path

    ZIP_CHECK_DIR="$(mktemp -d "$RELEASE_PATH/zip-check.XXXXXX")"
    ditto -x -k "$ZIP_PATH" "$ZIP_CHECK_DIR"
    extracted_app_path="$ZIP_CHECK_DIR/$APP_NAME.app"

    if [[ ! -d "$extracted_app_path" ]]; then
        fail "Zip 中未找到应用: $extracted_app_path"
    fi

    run_app_bundle_check "$extracted_app_path" "$require_stapled_ticket"
    rm -rf "$ZIP_CHECK_DIR"
    ZIP_CHECK_DIR=""
}

write_manifest() {
    local zip_checksum
    local dmg_checksum
    local git_commit
    local zip_size
    local dmg_size

    zip_checksum="$(cut -d ' ' -f 1 "$CHECKSUM_PATH")"
    dmg_checksum="$(cut -d ' ' -f 1 "$DMG_CHECKSUM_PATH")"
    git_commit="$(git rev-parse HEAD)"
    zip_size="$(artifact_size "$ZIP_PATH")"
    dmg_size="$(artifact_size "$DMG_PATH")"

    {
        echo "EasyZip release build"
        echo "App name: $APP_NAME"
        echo "Bundle identifier: $BUNDLE_IDENTIFIER"
        echo "Extension bundle identifier: $EXTENSION_BUNDLE_IDENTIFIER"
        echo "App group identifier: $APP_GROUP_IDENTIFIER"
        echo "Marketing version: $MARKETING_VERSION"
        echo "Build version: $BUILD_VERSION"
        echo "Code sign identity: $CODE_SIGN_IDENTITY"
        echo "DMG code sign identity: ${DMG_CODE_SIGN_IDENTITY:-skipped}"
        echo "Require Developer ID: $REQUIRE_DEVELOPER_ID"
        echo "Require Hardened Runtime: $REQUIRE_HARDENED_RUNTIME"
        echo "Require DMG signature: $REQUIRE_DMG_SIGNATURE"
        echo "Notarization status: $NOTARIZATION_STATUS"
        echo "Zip archive: $(basename "$ZIP_PATH")"
        echo "Zip size bytes: $zip_size"
        echo "Zip SHA256: $zip_checksum"
        echo "DMG archive: $(basename "$DMG_PATH")"
        echo "DMG size bytes: $dmg_size"
        echo "DMG SHA256: $dmg_checksum"
        echo "Built at UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "Git commit: $git_commit"
    } > "$MANIFEST_PATH"
}

trap cleanup EXIT

ensure_path_inside_repo "$APP_PATH"
ensure_path_inside_repo "$RELEASE_PATH"
ensure_path_inside_repo "$ZIP_PATH"
ensure_path_inside_repo "$DMG_PATH"
ensure_path_inside_repo "$NOTARY_ZIP_PATH"

if [[ "$APP_PATH" == "$REPO_ROOT" || "$RELEASE_PATH" == "$REPO_ROOT" ]]; then
    fail "输出路径不安全"
fi

if [[ -z "$DMG_CODE_SIGN_IDENTITY" && "$CODE_SIGN_IDENTITY" != "-" ]]; then
    DMG_CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY"
fi

if [[ "$CODE_SIGN_IDENTITY" != "-" ]]; then
    REQUIRE_HARDENED_RUNTIME="1"

    if [[ -z "$EXPECTED_CODE_SIGN_IDENTITY" && "$CODE_SIGN_IDENTITY" == *:* ]]; then
        EXPECTED_CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY"
    fi
fi

if [[ -n "$DMG_CODE_SIGN_IDENTITY" && "$DMG_CODE_SIGN_IDENTITY" != "-" ]]; then
    REQUIRE_DMG_SIGNATURE="1"

    if [[ -z "$EXPECTED_DMG_CODE_SIGN_IDENTITY" && "$DMG_CODE_SIGN_IDENTITY" == *:* ]]; then
        EXPECTED_DMG_CODE_SIGN_IDENTITY="$DMG_CODE_SIGN_IDENTITY"
    fi
fi

if is_enabled "$RELEASE_REQUIRE_DEVELOPER_ID"; then
    REQUIRE_DEVELOPER_ID="1"
fi

if is_enabled "$RELEASE_NOTARIZE"; then
    if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
        fail "公证发布需要设置 CODE_SIGN_IDENTITY"
    fi

    REQUIRE_DEVELOPER_ID="1"
    REQUIRE_HARDENED_RUNTIME="1"
fi

cd "$REPO_ROOT"

rm -rf "$RELEASE_PATH"
mkdir -p "$RELEASE_PATH"

CONFIGURATION=release \
APP_NAME="$APP_NAME" \
BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
EXTENSION_BUNDLE_IDENTIFIER="$EXTENSION_BUNDLE_IDENTIFIER" \
APP_GROUP_IDENTIFIER="$APP_GROUP_IDENTIFIER" \
MARKETING_VERSION="$MARKETING_VERSION" \
BUILD_VERSION="$BUILD_VERSION" \
OUTPUT_DIR="$OUTPUT_DIR" \
CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
APP_CODE_SIGN_ENTITLEMENTS="$APP_CODE_SIGN_ENTITLEMENTS" \
EXTENSION_CODE_SIGN_ENTITLEMENTS="$EXTENSION_CODE_SIGN_ENTITLEMENTS" \
"$SCRIPT_DIR/build_app_bundle.sh"

run_app_bundle_check "$APP_PATH" "0"

if is_enabled "$RELEASE_NOTARIZE"; then
    ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$NOTARY_ZIP_PATH"
    "$SCRIPT_DIR/notarize_release.sh" "$NOTARY_ZIP_PATH" "$APP_PATH"
    rm -f "$NOTARY_ZIP_PATH"
    APP_STAPLED_REQUIRED="1"
    NOTARIZATION_STATUS="app-stapled"
    run_app_bundle_check "$APP_PATH" "$APP_STAPLED_REQUIRED"
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
write_checksum "$ZIP_PATH" "$CHECKSUM_PATH"
check_zip_artifact "$APP_STAPLED_REQUIRED"

APP_NAME="$APP_NAME" \
BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
EXTENSION_BUNDLE_IDENTIFIER="$EXTENSION_BUNDLE_IDENTIFIER" \
APP_GROUP_IDENTIFIER="$APP_GROUP_IDENTIFIER" \
MARKETING_VERSION="$MARKETING_VERSION" \
BUILD_VERSION="$BUILD_VERSION" \
OUTPUT_DIR="$OUTPUT_DIR" \
RELEASE_DIR="$RELEASE_DIR" \
ARCHIVE_BASENAME="$ARCHIVE_BASENAME" \
DMG_CODE_SIGN_IDENTITY="$DMG_CODE_SIGN_IDENTITY" \
EXPECTED_CODE_SIGN_IDENTITY="$EXPECTED_CODE_SIGN_IDENTITY" \
EXPECTED_DMG_CODE_SIGN_IDENTITY="$EXPECTED_DMG_CODE_SIGN_IDENTITY" \
REQUIRE_DMG_SIGNATURE="$REQUIRE_DMG_SIGNATURE" \
REQUIRE_DEVELOPER_ID="$REQUIRE_DEVELOPER_ID" \
REQUIRE_HARDENED_RUNTIME="$REQUIRE_HARDENED_RUNTIME" \
REQUIRE_APP_STAPLED_TICKET="$APP_STAPLED_REQUIRED" \
"$SCRIPT_DIR/package_dmg.sh" "$APP_PATH" "$DMG_PATH"

if is_enabled "$RELEASE_NOTARIZE"; then
    "$SCRIPT_DIR/notarize_release.sh" "$DMG_PATH"
    NOTARIZATION_STATUS="app-and-dmg-stapled"
    run_dmg_check "1" "$APP_STAPLED_REQUIRED"
fi

write_checksum "$DMG_PATH" "$DMG_CHECKSUM_PATH"
write_manifest

echo "Zip 产物: $ZIP_PATH"
echo "Zip 校验文件: $CHECKSUM_PATH"
echo "DMG 产物: $DMG_PATH"
echo "DMG 校验文件: $DMG_CHECKSUM_PATH"
echo "构建摘要: $MANIFEST_PATH"
