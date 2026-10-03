#!/usr/bin/env python3
"""Exercise preparation failures without touching Vendor or the installed game."""

import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


def main():
    fixture_version = "9.8.7"
    original = Path(__file__).resolve().parent.parent / "Tools/prepare_guest.sh"
    with tempfile.TemporaryDirectory(prefix="factoriopad-prepare-") as temporary:
        root = Path(temporary) / "project with spaces"
        tools = root / "Tools"
        tools.mkdir(parents=True)
        shutil.copy2(original, tools / original.name)
        (tools / "patch_factorio.py").write_text(
            "import os, sys\n"
            "if os.environ.get('FAIL_PATCH'): sys.exit(1)\n"
        )
        source = root / "game.app/Contents/MacOS/factorio"
        source.parent.mkdir(parents=True)
        source.write_bytes(b"replacement guest")
        (root / "game.app/Contents/Info.plist").write_bytes(
            plistlib.dumps({"CFBundleShortVersionString": fixture_version})
        )
        framework = root / "Vendor/FactorioGuest.framework"
        framework.mkdir(parents=True)
        (framework / "FactorioGuest").write_bytes(b"working guest")
        commands = root / "commands"
        commands.mkdir()
        fixtures = {
            "lipo": 'if [ "${FAIL_LIPO:-}" = 1 ]; then exit 1; fi\ncp "$1" "$5"\n',
            "otool": 'printf "__PAGEZERO\\nLC_ID_DYLIB\\n"\n',
            "vtool": 'exit 0\n',
            "codesign": 'exit 0\n',
            "mv": 'if [ "${FAIL_INSTALL:-}" = 1 ] && [ "$1" != "${1%/FactorioGuest.framework}" ] && [ "$2" != "${2%/FactorioGuest.framework}" ]; then exit 1; fi\n'
                  'if [ "${FAIL_RESTORE:-}" = 1 ] && [ "$1" != "${1%/previous.framework}" ]; then exit 1; fi\n/bin/mv "$@"\n',
        }
        for name, body in fixtures.items():
            command = commands / name
            command.write_text("#!/bin/sh\nset -eu\n" + body)
            command.chmod(0o755)
        environment = dict(os.environ, FACTORIO_APP=str(root / "game.app"),
                           PATH=str(commands) + os.pathsep + os.environ["PATH"])
        for failure in ("FAIL_LIPO", "FAIL_PATCH", "FAIL_INSTALL"):
            result = subprocess.run(["bash", str(tools / original.name)],
                                    env=dict(environment, **{failure: "1"}),
                                    capture_output=True, text=True, timeout=20)
            assert result.returncode != 0, (failure, result.stdout, result.stderr)
            assert (framework / "FactorioGuest").read_bytes() == b"working guest", failure
            assert list(framework.iterdir()) == [framework / "FactorioGuest"], failure
            assert not list(framework.parent.glob(".factorio-guest.*")), failure
        result = subprocess.run(["bash", str(tools / original.name)], env=environment,
                                capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, (result.stdout, result.stderr)
        assert (framework / "FactorioGuest").read_bytes() == source.read_bytes()
        assert (framework / "Info.plist").is_file()
        assert plistlib.loads((framework / "Info.plist").read_bytes())[
            "CFBundleShortVersionString"] == fixture_version
        assert not list(framework.parent.glob(".factorio-guest.*"))
        lock = framework.parent / ".factorio-guest.lock"
        lock.mkdir()
        result = subprocess.run(["bash", str(tools / original.name)], env=environment,
                                capture_output=True, text=True, timeout=20)
        assert result.returncode != 0 and lock.is_dir(), "Concurrent preparation must not remove another run's lock"
        assert (framework / "FactorioGuest").read_bytes() == source.read_bytes()
        lock.rmdir()
        result = subprocess.run(["bash", str(tools / original.name)],
                                env=dict(environment, FAIL_INSTALL="1", FAIL_RESTORE="1"),
                                capture_output=True, text=True, timeout=20)
        assert result.returncode != 0 and "Restore failed" in result.stderr, (result.stdout, result.stderr)
        backups = list(framework.parent.glob(".factorio-guest.*/previous.framework/FactorioGuest"))
        assert len(backups) == 1 and backups[0].read_bytes() == source.read_bytes()
        assert lock.is_dir(), "A failed restore must preserve the recovery files and prevent another preparation"
    print("Factorio guest preparation tests passed.")


if __name__ == "__main__":
    main()
