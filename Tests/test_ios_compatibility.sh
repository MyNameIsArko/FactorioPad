#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/factoriopad-compatibility.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

xcodebuild -quiet -project "$ROOT/FactorioPad.xcodeproj" -scheme FactorioPad \
    -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath "$WORK" CODE_SIGNING_ALLOWED=NO build

python3 - "$WORK/Build/Products/Release-iphoneos/FactorioPad.app" <<'PY'
from pathlib import Path
import plistlib
import re
import subprocess
import sys

app = Path(sys.argv[1])
for bundle in [app, *sorted((app / "Frameworks").glob("*.framework"))]:
    info = plistlib.loads((bundle / "Info.plist").read_bytes())
    version = tuple(int(part) for part in info["MinimumOSVersion"].split("."))
    assert version[:2] <= (17, 0), (bundle, version)
    binary = bundle / info["CFBundleExecutable"]
    output = subprocess.check_output(["xcrun", "vtool", "-show-build", str(binary)], text=True)
    assert re.search(r"platform\s+IOS\s", output), (binary, output)
    minimums = re.findall(r"minos\s+(\d+)\.(\d+)", output)
    assert minimums and all(tuple(map(int, version)) <= (17, 0) for version in minimums), (binary, output)
assert (app / "Frameworks/FactorioCompat.framework/FactorioCompat").is_file()
assert (app / "Frameworks/FactorioGuest.framework/FactorioGuest").is_file()
assert (app / "FactorioData/base/info.json").is_file()
# Require imports used by Factorio 2.0.7 and 2.1.24 to resolve through FactorioCompat.
probe = app.parent / "compat-imports-probe.c"
probe.write_text(
    "float modff(float, float *);\n"
    "float probe(float x, float *integer) { return modff(x, integer); }\n"
    "extern void *NSApplicationDidChangeScreenParametersNotification;\n"
    "void *screen_notification(void) { return NSApplicationDidChangeScreenParametersNotification; }\n"
    "extern void *NSCalibratedRGBColorSpace;\n"
    "void *calibrated_rgb_color_space(void) { return NSCalibratedRGBColorSpace; }\n"
)
sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
desktop_probe = app.parent / "desktop-imports-probe.s"
desktop_probe.write_text(".section __DATA,__data\n.p2align 3\n" + "".join(".quad " + symbol + "\n" for symbol in [
    "_CGDisplayRegisterReconfigurationCallback", "_CGDisplayRemoveReconfigurationCallback",
    "_NSWindowDidChangeOcclusionStateNotification", "_NSWindowDidEndLiveResizeNotification",
    "_NSWindowWillMiniaturizeNotification", "_NSWindowWillMoveNotification", "_NSWindowWillStartLiveResizeNotification",
    "_OBJC_CLASS_$_NSOpenPanel", "_OBJC_CLASS_$_NSSavePanel", "_OBJC_CLASS_$_NSPasteboardItem",
    "_OBJC_CLASS_$_NSStatusBar", "_OBJC_CLASS_$_NSTrackingArea",
]))
subprocess.run(["xcrun", "clang", "-target", "arm64-apple-ios17.0", "-isysroot", sdk,
    "-dynamiclib", "-nostdlib", "-fno-builtin", "-F", str(app / "Frameworks"),
    "-framework", "FactorioCompat", str(probe), str(desktop_probe), "-o", str(probe.with_suffix(".dylib"))], check=True)
print("The app and embedded frameworks target iOS 17 or earlier.")
print("Older guests can resolve modff through FactorioCompat.")
print("Factorio 2.1.24 can resolve the screen notification and calibrated RGB color space through FactorioCompat.")
PY
