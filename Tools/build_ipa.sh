#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${FACTORIO_APP:-/Applications/factorio.app}"
GAME_DATA="$APP/Contents/data"
DESTINATION="$ROOT/Vendor/FactorioData"
OUTPUT="$ROOT/dist/FactorioPad-template.ipa"

if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != '--prepare-only' ] && [ "$1" != '--template' ]; }; then
    echo "Usage: bash Tools/build_ipa.sh [--prepare-only|--template]" >&2
    exit 2
fi

if [ ! -f "$APP/Contents/MacOS/factorio" ] || [ ! -d "$GAME_DATA/base" ]; then
    echo "ERROR: Set FACTORIO_APP to your installed Mac Factorio.app." >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"

mkdir -p "$ROOT/Vendor"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/factoriopad-ipa.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

if [ ! -d "$DESTINATION" ]; then
    echo "Copying game data from your local installation..."
    /usr/bin/ditto "$GAME_DATA" "$WORK/FactorioData"
    mv "$WORK/FactorioData" "$DESTINATION"
fi

DATA_VERSION="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$DESTINATION/base/info.json")"
if [ "$DATA_VERSION" != "$VERSION" ]; then
    echo "ERROR: Local game data is $DATA_VERSION, but the installed game is $VERSION." >&2
    echo "Move Vendor/FactorioData aside, then run this script again." >&2
    exit 1
fi

ICON="$ROOT/FactorioPad/Assets.xcassets/AppIcon.appiconset/icon.png"
if [ ! -f "$ICON" ]; then
    /usr/bin/sips -s format png -z 1024 1024 \
        "$APP/Contents/Resources/factorio.icns" --out "$ICON" >/dev/null
fi

FACTORIO_APP="$APP" "$ROOT/Tools/prepare_guest.sh"

if [ "${1:-}" = '--prepare-only' ]; then
    echo "Game files ready. Open FactorioPad.xcodeproj in Xcode."
    exit 0
fi

mkdir -p "$ROOT/dist"

echo "Game files ready. Building the iOS app now; Xcode may stay quiet for several minutes..."
xcodebuild -quiet \
    -project "$ROOT/FactorioPad.xcodeproj" \
    -scheme FactorioPad \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$WORK/DerivedData" \
    CODE_SIGNING_ALLOWED=NO build

PRODUCT="$WORK/DerivedData/Build/Products/Release-iphoneos/FactorioPad.app"
test -f "$PRODUCT/FactorioPad"
test -f "$PRODUCT/Frameworks/FactorioGuest.framework/FactorioGuest"
test -d "$PRODUCT/FactorioData/base"
echo "iOS build complete. Packaging the IPA..."
mkdir -p "$WORK/Payload"
mv "$PRODUCT" "$WORK/Payload/FactorioPad.app"
# Personal IPAs and separate game data are now prepared by the companion.
rm -rf "$WORK/Payload/FactorioPad.app/FactorioData" \
    "$WORK/Payload/FactorioPad.app/Frameworks/FactorioGuest.framework"
/usr/bin/ditto --norsrc --noextattr -c -k --keepParent "$WORK/Payload" "$WORK/FactorioPad.ipa"
/usr/bin/unzip -tq "$WORK/FactorioPad.ipa" >/dev/null
python3 "$ROOT/Tools/package_ipa.py" template "$WORK/FactorioPad.ipa" "$WORK/FactorioPad-template.ipa"
mv -f "$WORK/FactorioPad-template.ipa" "$OUTPUT"
echo "App template ready: $OUTPUT"
echo "The companion uses this same template on Windows, macOS, and Linux."
python3 "$ROOT/Tools/build_companion.py" --template "$OUTPUT" --output "$WORK/FactorioPad-Companion-macOS-arm64.zip"
mv -f "$WORK/FactorioPad-Companion-macOS-arm64.zip" "$ROOT/dist/FactorioPad-Companion-macOS-arm64.zip"
echo "Upload this ZIP to GitHub Releases: $ROOT/dist/FactorioPad-Companion-macOS-arm64.zip"
echo "Upload the template IPA, then run the companion workflow for the other platforms."
