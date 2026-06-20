#!/usr/bin/env bash
set -euo pipefail

PRODUCT_NAME="EasyZipApp"
EXTENSION_PRODUCT_NAME="EasyZipFinderSyncExtension"
APP_NAME="${APP_NAME:-易压缩}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.tiv.easyzip}"
EXTENSION_BUNDLE_IDENTIFIER="${EXTENSION_BUNDLE_IDENTIFIER:-$BUNDLE_IDENTIFIER.findersync}"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
BUILD_VERSION="${BUILD_VERSION:-1}"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFO_PLIST_TEMPLATE="$REPO_ROOT/BuildSupport/EasyZipApp/Info.plist"
EXTENSION_INFO_PLIST_TEMPLATE="$REPO_ROOT/BuildSupport/EasyZipFinderSyncExtension/Info.plist"
EXTENSION_SOURCE="$REPO_ROOT/Sources/EasyZipFinderSyncExtension/FinderSyncExtension.swift"
SHARED_HANDOFF_SOURCE="$REPO_ROOT/Sources/EasyZipShared/FinderActionHandoffStore.swift"
SHARED_NORMALIZER_SOURCE="$REPO_ROOT/Sources/EasyZipShared/FileURLListNormalizer.swift"
APP_PATH="$REPO_ROOT/$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_PATH="$APP_PATH/Contents"
MACOS_PATH="$CONTENTS_PATH/MacOS"
PLUGINS_PATH="$CONTENTS_PATH/PlugIns"
RESOURCES_PATH="$CONTENTS_PATH/Resources"
EXTENSION_PATH="$PLUGINS_PATH/$EXTENSION_PRODUCT_NAME.appex"
EXTENSION_CONTENTS_PATH="$EXTENSION_PATH/Contents"
EXTENSION_MACOS_PATH="$EXTENSION_CONTENTS_PATH/MacOS"
EXTENSION_RESOURCES_PATH="$EXTENSION_CONTENTS_PATH/Resources"
EXTENSION_EXECUTABLE_PATH="$EXTENSION_MACOS_PATH/$EXTENSION_PRODUCT_NAME"
MODULE_CACHE_PATH="$REPO_ROOT/.build/easyzip-findersync-module-cache"

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
mkdir -p "$MACOS_PATH" "$RESOURCES_PATH" "$EXTENSION_MACOS_PATH" "$EXTENSION_RESOURCES_PATH" "$MODULE_CACHE_PATH"
cp "$EXECUTABLE_PATH" "$MACOS_PATH/$PRODUCT_NAME"
chmod +x "$MACOS_PATH/$PRODUCT_NAME"
cp "$INFO_PLIST_TEMPLATE" "$CONTENTS_PATH/Info.plist"
cp "$EXTENSION_INFO_PLIST_TEMPLATE" "$EXTENSION_CONTENTS_PATH/Info.plist"
printf "APPL????" > "$CONTENTS_PATH/PkgInfo"
printf "XPC!????" > "$EXTENSION_CONTENTS_PATH/PkgInfo"

xcrun swiftc "$EXTENSION_SOURCE" "$SHARED_HANDOFF_SOURCE" "$SHARED_NORMALIZER_SOURCE" \
    -o "$EXTENSION_EXECUTABLE_PATH" \
    -module-name "$EXTENSION_PRODUCT_NAME" \
    -module-cache-path "$MODULE_CACHE_PATH" \
    -application-extension \
    -framework Cocoa \
    -framework FinderSync \
    -Xlinker -e \
    -Xlinker _NSExtensionMain
chmod +x "$EXTENSION_EXECUTABLE_PATH"

/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $PRODUCT_NAME" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_IDENTIFIER" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLName $BUNDLE_IDENTIFIER" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :NSServices:0:NSPortName $APP_NAME" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :NSServices:1:NSPortName $APP_NAME" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_VERSION" "$CONTENTS_PATH/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $EXTENSION_PRODUCT_NAME" "$EXTENSION_CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $EXTENSION_BUNDLE_IDENTIFIER" "$EXTENSION_CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$EXTENSION_CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_VERSION" "$EXTENSION_CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :NSExtension:NSExtensionPrincipalClass $EXTENSION_PRODUCT_NAME.$EXTENSION_PRODUCT_NAME" "$EXTENSION_CONTENTS_PATH/Info.plist"

codesign --force --sign - "$EXTENSION_PATH"
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo "已生成: $APP_PATH"
