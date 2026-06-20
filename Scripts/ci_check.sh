#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

export XDG_CACHE_HOME="$ROOT_DIR/.build/cache"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache"

mkdir -p "$XDG_CACHE_HOME" "$CLANG_MODULE_CACHE_PATH"

bash -n Scripts/build_app_bundle.sh
bash -n Scripts/check_app_bundle.sh
bash -n Scripts/release_build.sh
swift test
swift build --product EasyZipApp
Scripts/build_app_bundle.sh
Scripts/check_app_bundle.sh "dist/易压缩.app"
git diff --check
git diff --cached --check

scan_files=(
    Package.swift
    README.md
    docs/ARCHITECTURE.md
    Scripts/build_app_bundle.sh
    Scripts/check_app_bundle.sh
    Scripts/ci_check.sh
    Scripts/release_build.sh
)

while IFS= read -r -d '' file; do
    scan_files+=("$file")
done < <(
    find Sources Tests .github -type f \
        \( -name "*.swift" -o -name "*.md" -o -name "*.sh" -o -name "*.yml" -o -name "*.yaml" \) \
        -print0
)

if perl -Mutf8 -CS -ne '
BEGIN { $found = 0 }
if (/[\x{ff0c}\x{3002}\x{ff1b}\x{ff1a}\x{ff01}\x{ff1f}\x{ff08}\x{ff09}\x{3010}\x{3011}]/) {
    print "$ARGV:$.:$_";
    $found = 1;
}
END { exit($found ? 0 : 1) }
' "${scan_files[@]}"; then
    echo "Found unsupported Chinese punctuation."
    exit 1
fi
