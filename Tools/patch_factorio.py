#!/usr/bin/env python3

import pathlib
import re
import struct
import sys


MH_MAGIC_64 = 0xFEEDFACF
CPU_TYPE_ARM64 = 0x0100000C

MH_EXECUTE = 0x2
MH_DYLIB = 0x6

LC_SEGMENT_64 = 0x19
LC_ID_DYLIB = 0x0D
LC_BUILD_VERSION = 0x32

LC_LOAD_DYLIB = 0x0C
LC_LOAD_WEAK_DYLIB = 0x80000018
LC_REEXPORT_DYLIB = 0x8000001F
LC_LOAD_UPWARD_DYLIB = 0x80000023
LC_LAZY_LOAD_DYLIB = 0x20

PLATFORM_MACOS = 1
PLATFORM_IOS = 2

GUEST_ID = "@rpath/FactorioGuest.framework/FactorioGuest"
COMPAT_PATH = "@rpath/FactorioCompat.framework/FactorioCompat"


SHIM_FRAMEWORKS = {
    "AppKit",
    "Cocoa",
    "Carbon",
    "ForceFeedback",
    "OpenGL",
    "OpenCL",
    "LDAP",
    "ApplicationServices",

    "Foundation",
    "CoreGraphics",
    "CoreVideo",
    "Metal",
    "CoreServices",
    "IOKit",
    "Security",
    "CoreAudio",
    "AudioToolbox",
}


DYLIB_COMMANDS = {
    LC_LOAD_DYLIB,
    LC_LOAD_WEAK_DYLIB,
    LC_REEXPORT_DYLIB,
    LC_LOAD_UPWARD_DYLIB,
    LC_LAZY_LOAD_DYLIB,
}


FRAMEWORK_RE = re.compile(
    r"^/System/Library/Frameworks/"
    r"([^/]+)\.framework/"
    r"(?:Versions/[^/]+/)?"
    r"([^/]+)$"
)

# Factorio 2.0.77 ResourceManager creates a transparent 4x4 BC3 placeholder.
# Keep its zeroed 16-byte buffer, but use a 2x2 BGRA8 texture on iOS.
TRANSPARENT_TEXTURE = struct.pack("<22I",
    0x52800208, 0x4E080D00, 0x910007E8, 0x3C8FF100, 0xA9007C1F,
    0xF90093FF, 0x52800028, 0x390487E8, 0x52800128, 0xB9012BFF,
    0x3904A3FF, 0xB90127E8, 0xF94002A8, 0xF9405509, 0x910383E8,
    0x9103E3E3, 0x910483E5, 0xAA1503E0, 0x52800081, 0x52800004,
    0x52800082, 0xD63F0120)


def patch_transparent_texture(data: bytearray) -> None:
    if data.count(TRANSPARENT_TEXTURE) != 1:
        raise RuntimeError("Cannot patch the startup texture. Use Mac Factorio 2.0.77.")
    offset = data.index(TRANSPARENT_TEXTURE)
    if offset % 4:
        raise RuntimeError("The startup texture instructions are not aligned.")
    struct.pack_into("<I", data, offset + 8 * 4, 0x52800028)   # BitmapFormat 9 (BC3) -> 1 (BGRA8)
    struct.pack_into("<I", data, offset + 18 * 4, 0x52800041)  # width 4 -> 2
    struct.pack_into("<I", data, offset + 20 * 4, 0x52800042)  # height 4 -> 2
    print("[patch] Transparent startup texture: BC3 -> BGRA8")

def patch_ca_bundle_path(data: bytearray) -> None:
    old = b"/etc/ssl/cert.pem"
    new = b"cacert.pem"

    count = data.count(old)

    if count == 0:
        raise RuntimeError(
            "CA bundle path not found: /etc/ssl/cert.pem"
        )

    if len(new) > len(old):
        raise RuntimeError("New CA path is too long")

    replacement = new + b"\x00" * (len(old) - len(new))

    data[:] = data.replace(old, replacement)

    print(
        f"[patch] CA bundle path: "
        f"/etc/ssl/cert.pem -> cacert.pem "
        f"({count} occurrence(s))"
    )

def align8(value):
    return (value + 7) & ~7


def read_cstring(data, start, end):
    p = start

    while p < end and data[p] != 0:
        p += 1

    return bytes(data[start:p]).decode(
        "utf-8",
        errors="replace"
    )


def write_cstring(data, start, capacity, value):
    raw = value.encode("utf-8") + b"\0"

    if len(raw) > capacity:
        raise RuntimeError(
            f"String too long: {value}\n"
            f"need={len(raw)} capacity={capacity}"
        )

    data[start:start + capacity] = (
        raw +
        b"\0" * (capacity - len(raw))
    )


def make_id_dylib_command():
    name = GUEST_ID.encode("utf-8") + b"\0"

    cmdsize = align8(24 + len(name))

    result = bytearray(cmdsize)

    struct.pack_into(
        "<IIIIII",
        result,
        0,
        LC_ID_DYLIB,
        cmdsize,
        24,         # dylib.name.offset
        0,          # timestamp
        0x10000,    # current version 1.0
        0x10000,    # compatibility 1.0
    )

    result[24:24 + len(name)] = name

    return result


def patch(path):
    data = bytearray(path.read_bytes())

    if len(data) < 32:
        raise RuntimeError("File too small")

    magic, = struct.unpack_from("<I", data, 0)

    if magic != MH_MAGIC_64:
        raise RuntimeError(
            "Expected thin Mach-O 64-bit"
        )

    cputype, = struct.unpack_from("<I", data, 4)

    if cputype != CPU_TYPE_ARM64:
        raise RuntimeError(
            f"Expected ARM64, got 0x{cputype:x}"
        )

    filetype, = struct.unpack_from("<I", data, 12)
    ncmds, sizeofcmds = struct.unpack_from(
        "<II",
        data,
        16
    )

    if filetype != MH_EXECUTE:
        raise RuntimeError(
            f"Expected MH_EXECUTE, got {filetype}"
        )

    patch_ca_bundle_path(data)
    patch_transparent_texture(data)

    print(
        f"ARM64 Mach-O: "
        f"ncmds={ncmds} sizeofcmds={sizeofcmds}"
    )

    #
    # MH_EXECUTE -> MH_DYLIB
    #

    struct.pack_into("<I", data, 12, MH_DYLIB)

    print("[+] MH_EXECUTE -> MH_DYLIB")

    off = 32

    found_pagezero = False
    found_build_version = False
    existing_id = False

    first_section_offset = None

    #
    # Walk original load commands.
    #

    for index in range(ncmds):

        if off + 8 > len(data):
            raise RuntimeError(
                f"Command #{index} outside file"
            )

        cmd, cmdsize = struct.unpack_from(
            "<II",
            data,
            off
        )

        if cmdsize < 8:
            raise RuntimeError(
                f"Invalid cmdsize at #{index}"
            )

        if off + cmdsize > len(data):
            raise RuntimeError(
                f"Command #{index} exceeds file"
            )

        #
        # Segments.
        #

        if cmd == LC_SEGMENT_64:

            segname = bytes(
                data[off + 8:off + 24]
            ).split(b"\0", 1)[0]

            vmaddr, vmsize = struct.unpack_from(
                "<QQ",
                data,
                off + 24
            )

            nsects, = struct.unpack_from(
                "<I",
                data,
                off + 64
            )

            #
            # Preserve PAGEZERO but shrink it like
            # LiveContainer does.
            #

            if segname == b"__PAGEZERO":

                print(
                    "[+] __PAGEZERO "
                    f"{hex(vmaddr)}/{hex(vmsize)}"
                )

                struct.pack_into(
                    "<Q",
                    data,
                    off + 24,
                    0xFFFFC000
                )

                struct.pack_into(
                    "<Q",
                    data,
                    off + 32,
                    0x4000
                )

                print(
                    "    -> vmaddr=0xffffc000 "
                    "vmsize=0x4000"
                )

                found_pagezero = True

            #
            # Find first section's file offset.
            # We need this to know how much header padding
            # is available for LC_ID_DYLIB.
            #

            section_base = off + 72

            for section_index in range(nsects):

                s = section_base + section_index * 80

                if s + 80 > off + cmdsize:
                    raise RuntimeError(
                        "Malformed section table"
                    )

                section_file_offset, = struct.unpack_from(
                    "<I",
                    data,
                    s + 48
                )

                if section_file_offset != 0:

                    if (
                        first_section_offset is None
                        or section_file_offset <
                        first_section_offset
                    ):
                        first_section_offset = (
                            section_file_offset
                        )

        #
        # macOS -> iOS
        #

        elif cmd == LC_BUILD_VERSION:

            platform, minos, sdk, ntools = (
                struct.unpack_from(
                    "<IIII",
                    data,
                    off + 8
                )
            )

            print(
                "[+] LC_BUILD_VERSION "
                f"platform={platform} "
                f"minos=0x{minos:x} "
                f"sdk=0x{sdk:x}"
            )

            if platform == PLATFORM_MACOS:

                struct.pack_into(
                    "<I",
                    data,
                    off + 8,
                    PLATFORM_IOS
                )

                print("    macOS -> iOS")

            found_build_version = True

        elif cmd == LC_ID_DYLIB:
            existing_id = True

        #
        # Dependency paths.
        #

        elif cmd in DYLIB_COMMANDS:

            name_offset, = struct.unpack_from(
                "<I",
                data,
                off + 8
            )

            start = off + name_offset
            end = off + cmdsize

            old = read_cstring(
                data,
                start,
                end
            )

            new = old

            match = FRAMEWORK_RE.match(old)

            if match:

                framework = match.group(1)
                binary = match.group(2)

                if framework in SHIM_FRAMEWORKS:

                    new = COMPAT_PATH

                else:

                    new = (
                        "/System/Library/Frameworks/"
                        f"{framework}.framework/"
                        f"{binary}"
                    )

            if new != old:

                write_cstring(
                    data,
                    start,
                    cmdsize - name_offset,
                    new
                )

                print(f"[+] {old}")
                print(f" -> {new}")

        off += cmdsize

    if not found_pagezero:
        raise RuntimeError(
            "__PAGEZERO not found"
        )

    if not found_build_version:
        raise RuntimeError(
            "LC_BUILD_VERSION not found"
        )

    if existing_id:
        raise RuntimeError(
            "Unexpected existing LC_ID_DYLIB"
        )

    original_command_end = 32 + sizeofcmds

    if off != original_command_end:
        raise RuntimeError(
            "Load command size mismatch"
        )

    if first_section_offset is None:
        raise RuntimeError(
            "Could not determine first section offset"
        )

    #
    # Add LC_ID_DYLIB into unused header padding.
    #

    id_command = make_id_dylib_command()

    new_command_end = (
        original_command_end +
        len(id_command)
    )

    print()
    print(
        "[+] header command end:",
        hex(original_command_end)
    )

    print(
        "[+] first section offset:",
        hex(first_section_offset)
    )

    print(
        "[+] LC_ID_DYLIB size:",
        len(id_command)
    )

    if new_command_end > first_section_offset:
        raise RuntimeError(
            "Not enough Mach-O header padding "
            "for LC_ID_DYLIB"
        )

    #
    # Refuse to overwrite anything non-zero.
    #

    padding = data[
        original_command_end:
        new_command_end
    ]

    if any(padding):
        raise RuntimeError(
            "Header padding is not empty; "
            "refusing to overwrite it"
        )

    data[
        original_command_end:
        new_command_end
    ] = id_command

    struct.pack_into(
        "<I",
        data,
        16,
        ncmds + 1
    )

    struct.pack_into(
        "<I",
        data,
        20,
        sizeofcmds + len(id_command)
    )

    print(
        "[+] added LC_ID_DYLIB:",
        GUEST_ID
    )

    path.write_bytes(data)

    print()
    print("[+] Written:", path)


def main():

    if len(sys.argv) != 2:

        print(
            f"Usage: {sys.argv[0]} "
            "<thin-arm64-factorio>",
            file=sys.stderr
        )

        return 1

    patch(
        pathlib.Path(sys.argv[1])
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
