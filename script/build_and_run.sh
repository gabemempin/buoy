#!/bin/zsh

set -euo pipefail

readonly BUOY_DERIVED_DATA_PATH="$HOME/Library/Developer/Xcode/DerivedData/Buoy-Codex"
readonly BUOY_DEBUG_APP_PATH="$BUOY_DERIVED_DATA_PATH/Build/Products/Debug/Buoy.app"

killall Buoy 2>/dev/null || true

xcodebuild \
    -project Buoy.xcodeproj \
    -scheme Buoy \
    -configuration Debug \
    -derivedDataPath "$BUOY_DERIVED_DATA_PATH" \
    build

if [[ ! -d "$BUOY_DEBUG_APP_PATH" ]]; then
    print -u2 "Build succeeded, but the Debug app was not found at: $BUOY_DEBUG_APP_PATH"
    exit 1
fi

open "$BUOY_DEBUG_APP_PATH"
