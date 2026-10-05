#!/usr/bin/env python3
"""Make a game-free template, or package a personal IPA without Apple tools."""

import argparse
import json
import pathlib
import plistlib
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import zipfile

from patch_factorio import CPU_TYPE_ARM64, MH_MAGIC_64, patch


PRIVATE_FILES = {"player-data.json", "factorio-account.json", ".DS_Store"}
MARKER = "FactorioPadTemplate.json"


def arm64_slice(data):
    if len(data) < 32:
        raise ValueError("The Mac executable is too small.")
    if struct.unpack_from("<I", data)[0] == MH_MAGIC_64:
        if (struct.unpack_from("<I", data, 4)[0] != CPU_TYPE_ARM64
                or struct.unpack_from("<I", data, 8)[0] & 0xFFFFFF != 0):
            raise ValueError("The Mac executable needs an ARM64 slice.")
        return data
    magic, count = struct.unpack_from(">II", data)
    if magic not in (0xCAFEBABE, 0xCAFEBABF):
        raise ValueError("Use the Mac Factorio executable, not factorio.exe.")
    size = 20 if magic == 0xCAFEBABE else 32
    if count > (len(data) - 8) // size:
        raise ValueError("The universal executable has an invalid slice table.")
    for index in range(count):
        offset = 8 + index * size
        cpu, subtype = struct.unpack_from(">II", data, offset)
        start, length = struct.unpack_from(">II" if size == 20 else ">QQ", data, offset + 8)
        if cpu == CPU_TYPE_ARM64 and subtype & 0xFFFFFF == 0:
            if start < 8 + count * size or length < 32 or start + length > len(data):
                raise ValueError("The ARM64 slice is outside the executable.")
            return arm64_slice(data[start:start + length])
    raise ValueError("The Mac executable needs an ARM64 slice.")


def remove_signature(data):
    data = bytearray(data)
    count, size = struct.unpack_from("<II", data, 16)
    end = 32 + size
    if end > len(data):
        raise ValueError("The executable has invalid load commands.")
    offset = 32
    commands = []
    for _ in range(count):
        if offset + 8 > end:
            raise ValueError("The executable has a truncated load command.")
        command, length = struct.unpack_from("<II", data, offset)
        if length < 8 or length % 8 or offset + length > end:
            raise ValueError("The executable has an invalid load command size.")
        if command != 0x1D:  # LC_CODE_SIGNATURE becomes invalid after patching.
            commands.append(data[offset:offset + length])
        offset += length
    if offset != end:
        raise ValueError("The executable load command sizes do not match.")
    remaining = b"".join(commands)
    data[32:end] = remaining + bytes(size - len(remaining))
    struct.pack_into("<II", data, 16, len(commands), len(remaining))
    return data


def app_prefix(archive):
    names = archive.namelist()
    if len(names) != len(set(names)):
        raise ValueError("The IPA contains duplicate entries.")
    for name in names:
        path = pathlib.PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts or "\\" in name or ":" in name:
            raise ValueError("The IPA contains an unsafe path.")
    apps = {name.split("/")[1] for name in names
            if name.startswith("Payload/") and len(name.split("/")) > 2
            and name.split("/")[1].endswith(".app")}
    if len(apps) != 1:
        raise ValueError("The IPA must contain exactly one app.")
    prefix = "Payload/" + apps.pop() + "/"
    if any(not (name.startswith(prefix) or name in ("Payload/", prefix)
                or name.startswith("__MACOSX/")) for name in names):
        raise ValueError("The IPA contains files outside its app.")
    for entry in archive.infolist():
        if stat.S_ISLNK(entry.external_attr >> 16):
            raise ValueError("The IPA must not contain symbolic links.")
    return prefix


def omit(name):
    path = pathlib.PurePosixPath(name)
    return (path.name in PRIVATE_FILES | {"embedded.mobileprovision", "CodeResources", MARKER}
            or "_CodeSignature" in path.parts
            or "FactorioGuest.framework" in path.parts
            or "FactorioData" in path.parts or path.name == "cacert.pem")


def copy_app(source, target, prefix):
    for entry in source.infolist():
        if not entry.filename.startswith(prefix):
            continue
        relative = entry.filename.removeprefix(prefix)
        if omit(relative):
            continue
        if relative == "Info.plist":
            info = plistlib.loads(source.read(entry))
            info.update(UIFileSharingEnabled=True, LSSupportsOpeningDocumentsInPlace=True)
            target.writestr(entry, plistlib.dumps(info))
        else:
            with source.open(entry) as reader, target.open(entry, "w") as writer:
                shutil.copyfileobj(reader, writer)


def make_template(ipa, output):
    if output.exists():
        raise ValueError("The output IPA already exists. Choose a new path.")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent) as temporary:
        staging = pathlib.Path(temporary) / "template.ipa"
        with zipfile.ZipFile(ipa) as source, zipfile.ZipFile(staging, "w", zipfile.ZIP_DEFLATED) as target:
            prefix = app_prefix(source)
            info = plistlib.loads(source.read(prefix + "Info.plist"))
            if (prefix + "FactorioPad" not in source.namelist()
                    or info.get("FactorioPadExternalDataVersion") != 1):
                raise ValueError("Use an IPA built from the updated FactorioPad source.")
            copy_app(source, target, prefix)
            target.writestr(prefix + MARKER, json.dumps({"format": 2}))
        staging.rename(output)


def package(template, app, output):
    if output.exists():
        raise ValueError("The output folder already exists. Choose a new path.")
    contents = app / "Contents"
    game_info = plistlib.loads((contents / "Info.plist").read_bytes())
    version = game_info["CFBundleShortVersionString"]
    data_root = contents / "data"
    data_info = json.loads((data_root / "base/info.json").read_text(encoding="utf-8"))
    if not isinstance(version, str) or not version or data_info.get("version") != version:
        raise ValueError("The Mac executable and game data must use the same Factorio version.")
    for required in ("core/info.json", "cacert.pem", "base/scenarios/freeplay/control.lua"):
        if not (data_root / required).is_file():
            raise ValueError(f"The Mac game data is incomplete: {required}")
    # Refuse links so that copying cannot include files outside the installation.
    if any(path.is_symlink() for path in data_root.rglob("*")):
        raise ValueError("The game data must not contain symbolic links.")
    executable = remove_signature(arm64_slice((contents / "MacOS/factorio").read_bytes()))
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent) as temporary:
        work = pathlib.Path(temporary)
        result = work / "result"
        result.mkdir()
        binary = work / "FactorioGuest"
        binary.write_bytes(executable)
        patch(binary)
        shutil.copytree(data_root, result / "FactorioData", ignore=shutil.ignore_patterns(*PRIVATE_FILES))
        shutil.copyfile(pathlib.Path(__file__).with_name("freeplay_control.lua"),
                        result / "FactorioData/base/scenarios/freeplay/control.lua")
        with zipfile.ZipFile(template) as source, zipfile.ZipFile(result / "FactorioPad.ipa", "w", zipfile.ZIP_DEFLATED) as target:
            prefix = app_prefix(source)
            marker = json.loads(source.read(prefix + MARKER))
            if marker != {"format": 2}:
                raise ValueError("The app template format does not match this packaging tool. Download the current companion release.")
            if prefix + "Frameworks/FactorioCompat.framework/FactorioCompat" not in source.namelist():
                raise ValueError("The app template is missing the compatibility framework.")
            copy_app(source, target, prefix)
            guest = prefix + "Frameworks/FactorioGuest.framework/"
            info = {
                "CFBundleDevelopmentRegion": "en", "CFBundleExecutable": "FactorioGuest",
                "CFBundleIdentifier": "pl.adrian.FactorioPad.FactorioGuest",
                "CFBundleInfoDictionaryVersion": "6.0", "CFBundleName": "FactorioGuest",
                "CFBundlePackageType": "FMWK", "CFBundleShortVersionString": version,
                "CFBundleVersion": "1", "MinimumOSVersion": "17.0",
            }
            target.writestr(guest + "Info.plist", plistlib.dumps(info))
            entry = zipfile.ZipInfo(guest + "FactorioGuest")
            entry.create_system = 3
            entry.external_attr = (stat.S_IFREG | 0o755) << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            target.writestr(entry, binary.read_bytes())
        result.rename(output)


def package_dmg(template, dmg, output, seven_zip, progress=print):
    if output.exists():
        raise ValueError("The output folder already exists. Choose a new folder.")
    if not dmg.is_file() or dmg.suffix.lower() != ".dmg":
        raise ValueError("Select the Mac Factorio DMG download.")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent) as temporary:
        progress("Extracting the Factorio game files...")
        process = subprocess.run([str(seven_zip), "x", "-y", "-bd", "-bso0", "-bsp0", "-o" + temporary,
                                  str(dmg.resolve()), "Factorio/factorio.app/Contents/Info.plist",
                                  "Factorio/factorio.app/Contents/MacOS/factorio",
                                  "Factorio/factorio.app/Contents/data/*"],
                                 capture_output=True, text=True, errors="replace",
                                 creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0)
        if process.returncode:
            raise ValueError("Cannot extract the DMG. Download the Mac Factorio image again.")
        app = pathlib.Path(temporary) / "Factorio/factorio.app"
        if not (app / "Contents/Info.plist").is_file():
            raise ValueError("This DMG does not contain the Mac Factorio app.")
        progress("Preparing your IPA and game data...")
        package(template, app, output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    template = commands.add_parser("template", help="Remove game files and signatures from a maintainer IPA.")
    template.add_argument("ipa", type=pathlib.Path)
    template.add_argument("output", type=pathlib.Path)
    personal = commands.add_parser("package", help="Create a private IPA and a separate FactorioData folder.")
    personal.add_argument("template", type=pathlib.Path)
    personal.add_argument("factorio_app", type=pathlib.Path)
    personal.add_argument("output", type=pathlib.Path)
    dmg = commands.add_parser("dmg", help="Extract a Factorio DMG and prepare a personal IPA.")
    dmg.add_argument("template", type=pathlib.Path)
    dmg.add_argument("image", type=pathlib.Path)
    dmg.add_argument("output", type=pathlib.Path)
    dmg.add_argument("seven_zip", type=pathlib.Path)
    args = parser.parse_args()
    try:
        if args.command == "template":
            make_template(args.ipa, args.output)
            print(f"Game-free template ready: {args.output}")
        elif args.command == "dmg":
            package_dmg(args.template, args.image, args.output, args.seven_zip)
            print("Your app is ready.", flush=True)
        else:
            package(args.template, args.factorio_app, args.output)
            print(f"Private unsigned IPA: {args.output / 'FactorioPad.ipa'}")
            print(f"Sideload the IPA with a tool that signs embedded frameworks. Transfer {args.output / 'FactorioData'} to your device, then select it in FactorioPad.")
    except (OSError, ValueError, RuntimeError, KeyError, TypeError,
            plistlib.InvalidFileException, struct.error, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        parser.exit(1, f"ERROR: {error}\n")


if __name__ == "__main__":
    main()
