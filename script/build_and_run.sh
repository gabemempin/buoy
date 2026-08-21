#!/bin/zsh

set -euo pipefail

# Pinned so every entry point — Codex's Build & Run action, the VS Code task, a
# plain shell — shares one build tree instead of racing Xcode's hashed default.
readonly BUOY_DERIVED_DATA_PATH="$HOME/Library/Developer/Xcode/DerivedData/Buoy-Local"

cd "${0:A:h}/.."

readonly XCODEBUILD_FLAGS=(
    -project Buoy.xcodeproj
    -scheme Buoy
    -configuration Debug
    -derivedDataPath "$BUOY_DERIVED_DATA_PATH"
)

killall Buoy 2>/dev/null || true

xcodebuild "${XCODEBUILD_FLAGS[@]}" build

# Ask xcodebuild where it actually put the product rather than assuming a path.
# Guessing is what let the old VS Code task launch a bundle from a stale tree.
settings=$(xcodebuild "${XCODEBUILD_FLAGS[@]}" -showBuildSettings 2>/dev/null)
build_setting() {
    print -r -- "$settings" | awk -v key="$1" '
        $1 == key && $2 == "=" { sub(/^[^=]*= */, ""); print; exit }
    '
}

products_dir=$(build_setting BUILT_PRODUCTS_DIR)
product_name=$(build_setting FULL_PRODUCT_NAME)

if [[ -z "$products_dir" || -z "$product_name" ]]; then
    print -u2 "Could not resolve the built product path from xcodebuild settings."
    exit 1
fi

app_path="$products_dir/$product_name"
binary_path="$app_path/Contents/MacOS/${product_name:r}"

if [[ ! -d "$app_path" ]]; then
    print -u2 "Build succeeded, but no app bundle exists at: $app_path"
    exit 1
fi

# A successful build that left the binary older than the newest source means
# xcodebuild skipped work it should have done — launching it would run stale code.
if [[ -f "$binary_path" ]]; then
    newest_source=$(find Buoy -name '*.swift' -newer "$binary_path" -print -quit 2>/dev/null || true)
    if [[ -n "$newest_source" ]]; then
        print -u2 "Warning: $newest_source is newer than the built binary; the build may be stale."
    fi
fi

open "$app_path"
