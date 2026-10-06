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
from package_ipa import MARKER, app_prefix, arm64_slice, make_template, package, package_dmg, remove_signature
from patch_factorio import CPU_TYPE_ARM64, MH_MAGIC_64, MH_DYLIB, LC_ID_DYLIB, TRANSPARENT_TEXTURE, patch_transparent_texture, SPRITE_MASK_FORMATS, patch_sprite_mask_formats


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
    data[1088:1088 + len(TRANSPARENT_TEXTURE)] = TRANSPARENT_TEXTURE
    data[1216:1216 + len(SPRITE_MASK_FORMATS)] = SPRITE_MASK_FORMATS
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
    # Reject unknown code instead of changing an unrelated instruction sequence.
    for invalid in (bytearray(), bytearray(TRANSPARENT_TEXTURE * 2), bytearray(b"x" + TRANSPARENT_TEXTURE)):
        before = bytes(invalid)
        rejected(lambda: patch_transparent_texture(invalid))
        assert invalid == before
    texture = bytearray(TRANSPARENT_TEXTURE)
    patch_transparent_texture(texture)
    instructions = struct.unpack("<22I", texture)
    assert instructions[8] == 0x52800028  # BGRA8
    assert instructions[18] == 0x52800041 and instructions[20] == 0x52800042  # 2x2, 16 bytes
    assert sum(a != b for a, b in zip(struct.unpack("<22I", TRANSPARENT_TEXTURE), instructions)) == 3
    for invalid in (bytearray(), bytearray(SPRITE_MASK_FORMATS * 2), bytearray(b"x" + SPRITE_MASK_FORMATS)):
        before = bytes(invalid)
        rejected(lambda: patch_sprite_mask_formats(invalid))
        assert invalid == before
    masks = bytearray(SPRITE_MASK_FORMATS)
    patch_sprite_mask_formats(masks)
    original = struct.unpack("<12I", SPRITE_MASK_FORMATS)
    instructions = struct.unpack("<12I", masks)
    # MOVZ x13 stores the BitmapFormat in the upper word of BitmapOptions.
    assert instructions[4] == 0xD2C0006D  # R8, Metal format 10
    assert instructions[6] == 0xD2C0008D  # RG8, Metal format 30
    assert all(a == b for i, (a, b) in enumerate(zip(original, instructions)) if i not in (4, 6))
    fixture_version = "9.8.7"
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
            archive.writestr(prefix + "Info.plist", plistlib.dumps({"FactorioPadExternalDataVersion": 1, "UIFileSharingEnabled": False,
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
            assert json.loads(archive.read(prefix + MARKER)) == {"format": 2}
            assert archive.read(prefix + "Assets.car") == b"private content"
            assert archive.read(prefix + "AppIcon60x60@2x.png") == b"private content"
            info = plistlib.loads(archive.read(prefix + "Info.plist"))
            assert info["UIFileSharingEnabled"] and info["LSSupportsOpeningDocumentsInPlace"]
            assert info["CFBundleIcons"]["CFBundlePrimaryIcon"]["CFBundleIconName"] == "AppIcon"
        rejected(lambda: make_template(source, template))
        app = root / "factorio.app"
        contents = app / "Contents"
        for folder in ["MacOS", "data/base/scenarios/freeplay", "data/core"]:
            (contents / folder).mkdir(parents=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": fixture_version}))
        (contents / "MacOS/factorio").write_bytes(thin)
        (contents / "data/base/info.json").write_text(json.dumps({"version": fixture_version}))
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
            info = plistlib.loads(archive.read(prefix + "Info.plist"))
            assert info["UIFileSharingEnabled"] and info["LSSupportsOpeningDocumentsInPlace"]
            binary = archive.read(prefix + "Frameworks/FactorioGuest.framework/FactorioGuest")
            assert struct.unpack_from("<I", binary, 12)[0] == MH_DYLIB
            assert struct.unpack_from("<12I", binary, 1216) == instructions
            assert SPRITE_MASK_FORMATS not in binary
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
        (contents / "data/base/info.json").write_text('{"version":"9.8.8"}')
        rejected(lambda: package(template, app, root / "failed"))
        assert not (root / "failed").exists()
        # Arbitrary fixture versions pass packaging and retain their metadata.
        for version in ("1.2.3", "99.0.0"):
            (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": version}))
            (contents / "data/base/info.json").write_text(json.dumps({"version": version}))
            packaged = root / version
            with contextlib.redirect_stdout(io.StringIO()):
                package(template, app, packaged)
            with zipfile.ZipFile(packaged / "FactorioPad.ipa") as archive:
                guest_info = plistlib.loads(archive.read(prefix + "Frameworks/FactorioGuest.framework/Info.plist"))
                assert guest_info["CFBundleShortVersionString"] == version
            assert json.loads((packaged / "FactorioData/base/info.json").read_text())["version"] == version
            (contents / "data/base/info.json").write_text(json.dumps({"version": fixture_version}))
            rejected(lambda: package(template, app, root / (version + "-mismatch")))
            assert not (root / (version + "-mismatch")).exists()
        (contents / "data/base/info.json").write_text(json.dumps({"version": version}))
        with mock_patch('subprocess.run', side_effect=extract), contextlib.redirect_stdout(io.StringIO()):
            package_dmg(template, dmg, root / "another-version-dmg", Path('7zip'))
        assert (root / "another-version-dmg/FactorioPad.ipa").is_file()
        invalid_template = root / "invalid-template.ipa"
        with zipfile.ZipFile(template) as source, zipfile.ZipFile(invalid_template, "w") as target:
            for entry in source.infolist():
                data = (json.dumps({"format": 999}).encode()
                        if entry.filename == prefix + MARKER else source.read(entry))
                target.writestr(entry, data)
        with contextlib.redirect_stdout(io.StringIO()):
            rejected(lambda: package(invalid_template, app, root / "invalid-template-result"))
        assert not (root / "invalid-template-result").exists()
        (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": ""}))
        (contents / "data/base/info.json").write_text('{"version":""}')
        rejected(lambda: package(template, app, root / "empty-version"))
        assert not (root / "empty-version").exists()
        with zipfile.ZipFile(root / "unsafe.ipa", "w") as archive:
            archive.writestr(prefix + "../escape", b"bad")
        with zipfile.ZipFile(root / "unsafe.ipa") as archive:
            rejected(lambda: app_prefix(archive))
    print("Portable IPA packaging tests passed.")


if __name__ == "__main__":
    main()
