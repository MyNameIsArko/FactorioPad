#!/bin/bash
set -euo pipefail

# Usage: bash Tests/test_metal_view.sh <booted-simulator-UUID>
SIMULATOR="${1:?Pass the UUID of a booted iOS simulator}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d /tmp/factoriopad-metal-view.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

xcodebuild -quiet -project "$ROOT/FactorioPad.xcodeproj" -target FactorioCompat \
    -configuration Release -sdk iphonesimulator \
    CONFIGURATION_BUILD_DIR="$WORK/frameworks" OBJROOT="$WORK/intermediates" \
    CODE_SIGNING_ALLOWED=NO build
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator \
    -fobjc-arc -fblocks -I "$ROOT/FactorioCompat" -F "$WORK/frameworks" \
    -framework UIKit -framework Foundation -framework QuartzCore -framework FactorioCompat \
    -Wl,-rpath,"$WORK/frameworks" "$ROOT/Tests/test_metal_view.m" -o "$WORK/test-metal-view"
xcrun simctl spawn "$SIMULATOR" "$WORK/test-metal-view"
