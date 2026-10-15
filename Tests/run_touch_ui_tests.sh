#!/bin/bash
set -euo pipefail

test_device="${1:?Pass the UUID of a booted iOS simulator.}"
shift
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/factoriopad-touch-ui.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
test_app="$test_dir/TouchTests.app"
mkdir -p "$test_app"
python3 - "$test_app/Info.plist" <<'PY'
import plistlib
import sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({
    "CFBundleIdentifier": "dev.factoriopad.touch-ui-tests", "CFBundleExecutable": "TouchTests",
    "CFBundleName": "TouchTests", "CFBundleVersion": "1", "CFBundlePackageType": "APPL",
    "MinimumOSVersion": "17.0", "UIDeviceFamily": [1, 2], "UILaunchScreen": {},
    "UISupportedInterfaceOrientations": ["UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
    "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False, "UISceneConfigurations": {}}
}))
PY
test_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
SDKROOT="$test_sdk" xcrun swiftc -sdk "$test_sdk" -target arm64-apple-ios17.0-simulator \
    "$project_dir/FactorioPad/FactorioOnScreenKeyboard.swift" "$project_dir/FactorioPad/FactorioTouchControls.swift" \
    "$project_dir/Tests/test_touch_ui.swift" -o "$test_app/TouchTests"
codesign --force --sign - "$test_app"
xcrun simctl terminate "$test_device" dev.factoriopad.touch-ui-tests 2>/dev/null || true
xcrun simctl install "$test_device" "$test_app"
test_container="$(xcrun simctl get_app_container "$test_device" dev.factoriopad.touch-ui-tests data)"
rm -f "$test_container/Documents/touch-ui-passed.txt"
xcrun simctl launch "$test_device" dev.factoriopad.touch-ui-tests "$@"
for attempt in {1..20}; do
    if [ -f "$test_container/Documents/touch-ui-passed.txt" ]; then
        cat "$test_container/Documents/touch-ui-passed.txt"
        exit 0
    fi
    sleep 1
done
echo "The native touch interface test did not finish. Read the simulator crash report." >&2
exit 1
