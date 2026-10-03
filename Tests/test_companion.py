#!/usr/bin/env python3
"""Shared GUI and release checks without Xcode or purchased game files."""

import contextlib
import io
import json
from pathlib import Path
import plistlib
import sys
import tarfile
import tempfile
import tkinter as tk
from types import SimpleNamespace
from unittest.mock import patch
import zipfile

# PyInstaller probes the Linux runtime with subprocess.run during import.
# Load it before the release test replaces subprocess.run with a fake compiler.
import PyInstaller

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Tools'))
import build_companion
import companion
from package_ipa import MARKER


def main():
    for system, machine, target in (("darwin", "arm64", "macOS-arm64"),
                                    ("win32", "AMD64", "Windows-x64"),
                                    ("linux", "x86_64", "Linux-x64")):
        with patch('build_companion.sys.platform', system), patch('build_companion.platform.machine', return_value=machine):
            assert build_companion.platform_name() == target
    with patch('build_companion.sys.platform', 'darwin'), patch('build_companion.platform.machine', return_value='x86_64'):
        try:
            build_companion.platform_name()
        except ValueError:
            pass
        else:
            raise AssertionError('Intel Mac builds must not be accepted')
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        parent = root / 'output with spaces'
        parent.mkdir()
        (parent / 'FactorioPad-personal').mkdir()
        (parent / 'FactorioPad-personal-2').mkdir()
        assert companion.result_folder(parent) == parent / 'FactorioPad-personal-3'
        resources = root / 'resources'
        (resources / '7zip').mkdir(parents=True)
        (resources / 'FactorioPad-template.ipa').write_bytes(b'template')
        extractor = resources / '7zip' / ('7z.exe' if sys.platform == 'win32' else '7zz')
        extractor.write_bytes(b'extractor')
        dmg = root / 'game image.dmg'
        dmg.write_bytes(b'original download')
        progress = []
        def package(template, source, output, tool, progress):
            assert template == resources / 'FactorioPad-template.ipa'
            assert source == dmg and tool == extractor
            assert output == parent / 'FactorioPad-personal-3'
            progress('Extracting game files')
            output.mkdir()
        with patch('companion.package_dmg', side_effect=package):
            output = companion.prepare_game(dmg, parent, resources, progress.append)
        assert progress == ['Extracting game files']
        assert output.is_dir() and dmg.read_bytes() == b'original download'
        extractor.unlink()
        try:
            companion.prepare_game(dmg, parent, resources, progress.append)
        except ValueError:
            pass
        else:
            raise AssertionError('Missing tools were accepted')

        # Exercise success and failure on the real shared window.
        window = tk.Tk()
        window.withdraw()
        view = companion.Companion(window)
        view.busy = True
        view.events.put(('progress', 'Preparing game'))
        view.events.put(('done', output))
        view.poll()
        assert not view.busy and view.output == output
        assert view.open_button.instate(['!disabled'])
        view.busy = True
        view.events.put(('error', 'Test failure'))
        with patch('companion.messagebox.showerror') as error:
            view.poll()
            error.assert_called_once()
        assert not view.busy and view.prepare_button.instate(['!disabled'])
        view.busy = True
        view.close()
        assert window.winfo_exists()
        view.busy = False
        view.close()

        # Fake only the native compiler and tool download, then inspect the release.
        ipa = root / 'private.ipa'
        prefix = 'Payload/FactorioPad.app/'
        with zipfile.ZipFile(ipa, 'w') as archive:
            archive.writestr(prefix + 'FactorioPad', b'host')
            archive.writestr(prefix + 'Info.plist', plistlib.dumps({'FactorioPadExternalDataVersion': 1}))
            archive.writestr(prefix + 'Frameworks/FactorioCompat.framework/FactorioCompat', b'shims')
            archive.writestr(prefix + 'Assets.car', b'icon')
            archive.writestr(prefix + 'FactorioData/base/info.json', b'private game data')
            archive.writestr(prefix + 'Frameworks/FactorioGuest.framework/FactorioGuest', b'private executable')
        def tools(destination):
            destination.mkdir()
            (destination / '7zz').write_bytes(b'tool')
        def compile_app(command, **kwargs):
            if command[-1] == '--self-test':
                return
            assert command[:3] == [sys.executable, '-m', 'PyInstaller']
            bundle_resources = Path(command[command.index('--add-data') + 1].rsplit(__import__('os').pathsep, 1)[0])
            template = (bundle_resources / 'FactorioPad-template.ipa').read_bytes()
            with zipfile.ZipFile(io.BytesIO(template)) as archive:
                assert not any('FactorioData/' in p or 'FactorioGuest.framework/' in p for p in archive.namelist())
                assert archive.read(prefix + 'Assets.car') == b'icon'
                assert json.loads(archive.read(prefix + MARKER)) == {'format': 2}
            product = Path(command[command.index('--distpath') + 1]) / (build_companion.NAME + '.app')
            product.mkdir(parents=True)
            (product / 'FactorioPad-template.ipa').write_bytes(template)
        release = root / 'release.zip'
        native_write = build_companion.write_archive
        def archive_zip(folder, destination):
            # Test the Windows ZIP writer on every test host.
            with patch('build_companion.sys.platform', 'win32'):
                native_write(folder, destination)
        with patch('build_companion.sys', SimpleNamespace(platform='darwin', executable=sys.executable)), patch('build_companion.platform.machine', return_value='arm64'), \
             patch('build_companion.prepare_seven_zip', side_effect=tools), patch('build_companion.subprocess.run', side_effect=compile_app), \
             patch('build_companion.write_archive', side_effect=archive_zip), patch('build_companion.copy_runtime_licenses'):
            build_companion.make_release(ipa, release)
            assert release.exists()
            before = release.read_bytes()
            try:
                build_companion.make_release(ipa, release)
            except ValueError:
                pass
            else:
                raise AssertionError('Existing release was overwritten')
            assert release.read_bytes() == before
            with patch('build_companion.subprocess.run', side_effect=OSError('compiler failed')):
                try:
                    build_companion.make_release(ipa, root / 'failed.zip')
                except OSError:
                    pass
                else:
                    raise AssertionError('Failed builds were published')
            assert not (root / 'failed.zip').exists()
        with zipfile.ZipFile(release) as archive:
            assert archive.testzip() is None
            assert any(p.endswith('README.txt') for p in archive.namelist())
            assert not any('private.ipa' in p for p in archive.namelist())
        linux_app = root / 'Linux app'
        linux_app.mkdir()
        executable = linux_app / 'FactorioPad Companion'
        executable.write_bytes(b'program')
        executable.chmod(0o755)
        linux_release = root / 'linux.tar.gz'
        with patch('build_companion.sys', SimpleNamespace(platform='linux')):
            native_write(linux_app, linux_release)
        with tarfile.open(linux_release) as archive:
            assert archive.extractfile('Linux app/FactorioPad Companion').read() == b'program'
            if sys.platform != 'win32':
                assert archive.getmember('Linux app/FactorioPad Companion').mode == 0o755
    print('Shared companion checks passed.')


if __name__ == '__main__':
    main()
