#!/usr/bin/env bash
set -euo pipefail

PRODUCT_NAME="EasyZipApp"
APP_NAME="${APP_NAME:-易压缩}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.tiv.easyzip}"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
BUILD_VERSION="${BUILD_VERSION:-1}"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFO_PLIST_TEMPLATE="$REPO_ROOT/BuildSupport/EasyZipApp/Info.plist"
APP_PATH="$REPO_ROOT/$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_PATH="$APP_PATH/Contents"
MACOS_PATH="$CONTENTS_PATH/MacOS"
RESOURCES_PATH="$CONTENTS_PATH/Resources"

if [[ -z "$APP_NAME" || -z "$OUTPUT_DIR" ]]; then
    echo "应用名称或输出目录不能为空" >&2
    exit 1
fi

if [[ "$APP_PATH" == "$REPO_ROOT" || "$APP_PATH" == "/" ]]; then
    echo "输出路径不安全: $APP_PATH" >&2
    exit 1
fi

cd "$REPO_ROOT"
swift build -c "$CONFIGURATION" --product "$PRODUCT_NAME"
SWIFT_BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path | tail -n 1)"
EXECUTABLE_PATH="$SWIFT_BIN_PATH/$PRODUCT_NAME"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
    echo "未找到可执行文件: $EXECUTABLE_PATH" >&2
    exit 1
fi

rm -rf "$APP_PATH"
mkdir -p "$MACOS_PATH" "$RESOURCES_PATH"
cp "$EXECUTABLE_PATH" "$MACOS_PATH/$PRODUCT_NAME"
chmod +x "$MACOS_PATH/$PRODUCT_NAME"
cp "$INFO_PLIST_TEMPLATE" "$CONTENTS_PATH/Info.plist"
printf "APPL????" > "$CONTENTS_PATH/PkgInfo"

/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $PRODUCT_NAME" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_IDENTIFIER" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :NSServices:0:NSPortName $APP_NAME" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :NSServices:1:NSPortName $APP_NAME" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_VERSION" "$CONTENTS_PATH/Info.plist"

echo "已生成: $APP_PATH"
