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
print("The app and embedded frameworks target iOS 17 or earlier.")
PY
