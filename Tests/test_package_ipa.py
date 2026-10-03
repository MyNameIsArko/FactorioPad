#!/usr/bin/env python3
"""Portable packaging checks. No Apple tools or purchased game files required."""

import contextlib
import io
import json
from pathlib import Path
import plistlib
import struct
import sys
import tempfile
from types import SimpleNamespace
from unittest.mock import patch as mock_patch
import shutil
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Tools"))
from package_ipa import app_prefix, arm64_slice, make_template, package, package_dmg, remove_signature
from patch_factorio import CPU_TYPE_ARM64, MH_MAGIC_64, MH_DYLIB, LC_ID_DYLIB


def executable():
    pagezero = struct.pack("<II16sQQQQIIII", 0x19, 72, b"__PAGEZERO", 0, 0x100000000, 0, 0, 0, 0, 0, 0)
    text = struct.pack("<II16sQQQQIIII", 0x19, 152, b"__TEXT", 0x100000000, 4096, 0, 4096, 7, 5, 1, 0)
    section = bytearray(80)
    struct.pack_into("<I", section, 48, 1024)
    build = struct.pack("<IIIIII", 0x32, 24, 1, 17 << 16, 17 << 16, 0)
    signature = struct.pack("<IIII", 0x1D, 16, 2048, 16)
    commands = pagezero + text + section + build + signature
    data = bytearray(4096)
    struct.pack_into("<IIIIIIII", data, 0, MH_MAGIC_64, CPU_TYPE_ARM64, 0, 2, 4, len(commands), 0, 0)
    data[32:32 + len(commands)] = commands
    data[1024:1041] = b"/etc/ssl/cert.pem\0"
    return bytes(data)


def commands(data):
    offset = 32
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        command, length = struct.unpack_from("<II", data, offset)
        yield command
        offset += length


def rejected(action):
    try:
        action()
    except (ValueError, RuntimeError):
        return
    raise AssertionError("Invalid input was accepted")


def main():
    thin = executable()
    for magic, format in [(0xCAFEBABE, ">IIIII"), (0xCAFEBABF, ">IIQQII")]:
        slice_entry = (CPU_TYPE_ARM64, 0, 4096, len(thin), 12)
        if magic == 0xCAFEBABF:
            slice_entry += (0,)
        header = struct.pack(">II", magic, 1) + struct.pack(format, *slice_entry)
        fat = header + bytes(4096 - len(header)) + thin
        assert arm64_slice(fat) == thin
        rejected(lambda: arm64_slice(fat[:-1]))
    assert 0x1D not in commands(remove_signature(thin))
    rejected(lambda: arm64_slice(b"MZ" + bytes(50)))
    rejected(lambda: arm64_slice(thin[:20]))
    malformed = bytearray(thin)
    struct.pack_into("<I", malformed, 36, 0)
    rejected(lambda: remove_signature(malformed))
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        source = root / "private.ipa"
        prefix = "Payload/FactorioPad.app/"
        with zipfile.ZipFile(source, "w") as archive:
            archive.writestr(prefix + "FactorioPad", b"compiled host")
            archive.writestr(prefix + "Info.plist", plistlib.dumps({"FactorioPadExternalDataVersion": 1,
                "CFBundleIcons": {"CFBundlePrimaryIcon": {"CFBundleIconName": "AppIcon"}}}))
            archive.writestr(prefix + "Frameworks/FactorioCompat.framework/FactorioCompat", b"compiled shims")
            archive.writestr("Payload/", b"")
            archive.writestr("__MACOSX/Payload/FactorioPad.app/._Info.plist", b"Mac metadata")
            for name in ["FactorioData/base/info.json", "FactorioData/player-data.json",
                         "Frameworks/FactorioGuest.framework/FactorioGuest", "cacert.pem",
                         "Assets.car", "AppIcon60x60@2x.png", "_CodeSignature/CodeResources", "embedded.mobileprovision"]:
                archive.writestr(prefix + name, b"private content")
        template = root / "template.ipa"
        make_template(source, template)
        with zipfile.ZipFile(template) as archive:
            assert len(archive.namelist()) == 6
            assert archive.read(prefix + "Assets.car") == b"private content"
            assert archive.read(prefix + "AppIcon60x60@2x.png") == b"private content"
            info = plistlib.loads(archive.read(prefix + "Info.plist"))
            assert info["UIFileSharingEnabled"] and info["CFBundleIcons"]["CFBundlePrimaryIcon"]["CFBundleIconName"] == "AppIcon"
        rejected(lambda: make_template(source, template))
        app = root / "factorio.app"
        contents = app / "Contents"
        for folder in ["MacOS", "data/base/scenarios/freeplay", "data/core"]:
            (contents / folder).mkdir(parents=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": "2.0.77"}))
        (contents / "MacOS/factorio").write_bytes(thin)
        (contents / "data/base/info.json").write_text('{"version":"2.0.77"}')
        (contents / "data/core/info.json").write_text('{}')
        (contents / "data/cacert.pem").write_text('certificate')
        (contents / "data/base/scenarios/freeplay/control.lua").write_text('original freeplay')
        (contents / "data/factorio-account.json").write_text('secret')
        result = root / "personal"
        with contextlib.redirect_stdout(io.StringIO()):
            package(template, app, result)
        with zipfile.ZipFile(result / "FactorioPad.ipa") as archive:
            assert archive.read(prefix + "Assets.car") == b"private content"
            assert plistlib.loads(archive.read(prefix + "Info.plist"))["CFBundleIcons"]["CFBundlePrimaryIcon"]["CFBundleIconName"] == "AppIcon"
            binary = archive.read(prefix + "Frameworks/FactorioGuest.framework/FactorioGuest")
            assert struct.unpack_from("<I", binary, 12)[0] == MH_DYLIB
            assert LC_ID_DYLIB in commands(binary) and 0x1D not in commands(binary)
            assert b"cacert.pem\0" in binary and b"/etc/ssl/cert.pem" not in binary
            assert archive.getinfo(prefix + "Frameworks/FactorioGuest.framework/FactorioGuest").external_attr >> 16 & 0o111
            assert not any("FactorioData" in name for name in archive.namelist())
        assert not (result / "FactorioData/factorio-account.json").exists()
        assert "set_skip_intro" in (result / "FactorioData/base/scenarios/freeplay/control.lua").read_text()
        assert (contents / "MacOS/factorio").read_bytes() == thin
        rejected(lambda: package(template, app, result))
        dmg = root / "game image.dmg"
        dmg.write_bytes(b"fixture")
        def extract(command, **kwargs):
            assert command[1:6] == ["x", "-y", "-bd", "-bso0", "-bsp0"]
            assert command[7] == str(dmg.resolve())
            staging = Path(command[6][2:])
            shutil.copytree(app, staging / "Factorio/factorio.app")
            return SimpleNamespace(returncode=0)
        with mock_patch('subprocess.run', side_effect=extract), contextlib.redirect_stdout(io.StringIO()):
            package_dmg(template, dmg, root / "from dmg", Path('7zip'))
        assert (root / "from dmg/FactorioPad.ipa").is_file()
        assert not any(p.name.startswith('tmp') for p in root.iterdir())
        with mock_patch('subprocess.run', return_value=SimpleNamespace(returncode=2)), contextlib.redirect_stdout(io.StringIO()):
            rejected(lambda: package_dmg(template, dmg, root / "bad-dmg", Path('7zip')))
        assert not (root / "bad-dmg").exists()
        with mock_patch('subprocess.run', return_value=SimpleNamespace(returncode=0)), contextlib.redirect_stdout(io.StringIO()):
            rejected(lambda: package_dmg(template, dmg, root / "empty-dmg", Path('7zip')))
        assert not (root / "empty-dmg").exists()
        (contents / "data/base/info.json").write_text('{"version":"2.0.78"}')
        rejected(lambda: package(template, app, root / "failed"))
        assert not (root / "failed").exists()
        with zipfile.ZipFile(root / "unsafe.ipa", "w") as archive:
            archive.writestr(prefix + "../escape", b"bad")
        with zipfile.ZipFile(root / "unsafe.ipa") as archive:
            rejected(lambda: app_prefix(archive))
    print("Portable IPA packaging tests passed.")


if __name__ == "__main__":
    main()
