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
# Check all known Factorio 2.1.24 AppKit globals against the built framework,
# not merely their source declarations. Report the full missing set at once.
compat = app / "Frameworks/FactorioCompat.framework/FactorioCompat"
exports = subprocess.check_output(["xcrun", "nm", "-gU", str(compat)], text=True)
missing = []
for symbol in (
    "_NSApplicationDidChangeScreenParametersNotification",
    "_NSCalibratedRGBColorSpace",
    "_NSWindowDidChangeOcclusionStateNotification",
    "_NSWindowDidEndLiveResizeNotification",
    "_NSWindowWillMiniaturizeNotification",
    "_NSWindowWillMoveNotification",
    "_NSWindowWillStartLiveResizeNotification",
    "_NSPointInRect",
    "_NSZeroPoint",
    "_NSZeroRect",
    "_OBJC_CLASS_$_NSOpenPanel",
    "_OBJC_CLASS_$_NSSavePanel",
    "_OBJC_CLASS_$_NSPasteboardItem",
    "_OBJC_CLASS_$_NSStatusBar",
    "_OBJC_CLASS_$_NSTrackingArea",
):
    if not re.search(r"(?:^|\s)" + re.escape(symbol) + r"$", exports, re.MULTILINE):
        missing.append(symbol)
assert not missing, "FactorioCompat is missing required Factorio 2.1.24 exports: " + ", ".join(missing)
# Link a focused regression probe against the built compatibility framework.
probe = app.parent / "compat-appkit-probe.c"
probe.write_text(
    "extern void *NSApplicationDidChangeScreenParametersNotification;\n"
    "void *screen_notification(void) { return NSApplicationDidChangeScreenParametersNotification; }\n"
    "extern void *NSCalibratedRGBColorSpace;\n"
    "void *calibrated_color_space(void) { return NSCalibratedRGBColorSpace; }\n"
    "extern void *NSWindowDidChangeOcclusionStateNotification;\n"
    "void *occlusion_notification(void) { return NSWindowDidChangeOcclusionStateNotification; }\n"
    "extern void *NSWindowDidEndLiveResizeNotification;\n"
    "void *end_live_resize_notification(void) { return NSWindowDidEndLiveResizeNotification; }\n"
    "extern void *NSWindowWillMiniaturizeNotification;\n"
    "void *will_miniaturize_notification(void) { return NSWindowWillMiniaturizeNotification; }\n"
    "extern void *NSWindowWillMoveNotification;\n"
    "void *will_move_notification(void) { return NSWindowWillMoveNotification; }\n"
)
sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
result = subprocess.run(
    [
        "xcrun", "clang", "-target", "arm64-apple-ios17.0", "-isysroot", sdk,
        "-dynamiclib", "-nostdlib", "-fno-builtin", "-Wl,-undefined,error",
        "-F", str(app / "Frameworks"), "-framework", "FactorioCompat",
        str(probe), "-o", str(probe.with_suffix(".dylib")),
    ], text=True, capture_output=True,
)
assert result.returncode == 0, "Known AppKit imports failed to link:\n" + result.stderr
guest = app / "Frameworks/FactorioGuest.framework/FactorioGuest"
bind = subprocess.check_output(
    ["xcrun", "llvm-objdump", "--macho", "--bind", str(guest)], text=True
)
lazy_bind = subprocess.check_output(
    ["xcrun", "llvm-objdump", "--macho", "--lazy-bind", str(guest)], text=True
)

# Build one link probe per two-level-namespace library ordinal. This checks
# strong imports against the actual linked framework/re-export graph and keeps
# weak imports optional. Collect failures from every library before failing.
imports = {}
patterns = (
    re.compile(r"^\S+\s+\S+\s+0x[0-9a-fA-F]+\s+\S+\s+-?\d+\s+(\S+)\s+(\S+)(?:\s+\((weak_import)\))?\s*$"),
    re.compile(r"^\S+\s+\S+\s+0x[0-9a-fA-F]+\s+(\S+)\s+(\S+)(?:\s+\((weak_import)\))?\s*$"),
)
for output, pattern in ((bind, patterns[0]), (lazy_bind, patterns[1])):
    for line in output.splitlines():
        match = pattern.match(line)
        if not match:
            continue
        library, symbol, weak = match.groups()
        if library in ("self", "flat-namespace", "main-executable"):
            continue
        by_name = imports.setdefault(library, {})
        by_name[symbol] = by_name.get(symbol, True) and weak == "weak_import"

undefined_output = subprocess.check_output(
    ["xcrun", "llvm-nm", "--undefined-only", "--extern-only", str(guest)], text=True
)
undefined_symbols = {
    line.split()[-1]
    for line in undefined_output.splitlines()
    if line.split() and line.split()[-1].startswith("_")
}
bound_symbols = {symbol for symbols in imports.values() for symbol in symbols}
unassigned = sorted(undefined_symbols - bound_symbols)
unexpected = sorted(bound_symbols - undefined_symbols)
assert not (unassigned or unexpected), (
    "LLVM bind records do not cover the complete undefined-symbol table; "
    f"unassigned={unassigned}, unexpected={unexpected}"
)

link_libraries = {
    "FactorioCompat": ["-F", str(app / "Frameworks"), "-framework", "FactorioCompat"],
    "libSystem": ["-lSystem"],
    "libobjc": ["-lobjc"],
    "libresolv": ["-lresolv"],
}
failures = []
for library, symbols in sorted(imports.items()):
    args = link_libraries.get(library, ["-framework", library])
    probe = app.parent / ("compat-imports-" + re.sub(r"[^A-Za-z0-9]+", "-", library) + ".c")
    declarations = []
    references = []
    for index, (symbol, weak) in enumerate(sorted(symbols.items())):
        asm_name = symbol.replace("\\", "\\\\").replace('"', '\\"')
        attr = " __attribute__((weak_import))" if weak else ""
        declarations.append(
            f'extern const unsigned char fp_import_{index}[] __asm__("{asm_name}"){attr};'
        )
        references.append(f"fp_import_{index}")
    probe.write_text(
        "\n".join(declarations)
        + "\n__attribute__((used)) const void *const fp_imports[] = {\n"
        + ",\n".join(references)
        + "\n};\n"
    )
    result = subprocess.run(
        [
            "xcrun", "clang", "-target", "arm64-apple-ios17.0", "-isysroot", sdk,
            "-dynamiclib", "-nostdlib", "-fno-builtin", "-Wl,-undefined,error",
            *args, str(probe), "-o", str(probe.with_suffix(".dylib")),
        ], text=True, capture_output=True,
    )
    if result.returncode:
        failures.append(f"{library} ({len(symbols)} imports):\n{result.stderr.strip()}")
assert not failures, "Unresolved strong imports from FactorioGuest:\n" + "\n\n".join(failures)
print("The app and embedded frameworks target iOS 17 or earlier.")
print(f"FactorioGuest imports resolve through {len(imports)} two-level namespace libraries.")
print("Known Factorio 2.1.24 AppKit symbols and all strong guest imports resolve.")
print("Known Factorio 2.1.24 AppKit imports link against FactorioCompat.")
PY
