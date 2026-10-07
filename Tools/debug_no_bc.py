#!/usr/bin/env python3
"""Run Mac Factorio with the iOS texture patches and reject BC texture requests.

Use --unpatched to reproduce the original failure. Pass game arguments after --,
for example: -- --load-scenario base/freeplay. Outputs remain in the printed folder.
This tests texture format requests, not iPhone performance or memory limits.
"""
import argparse
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile

from package_ipa import arm64_slice, remove_signature
from patch_factorio import (
    SPRITE_MASK_FORMATS, TERRAIN_EFFECT_FORMAT, TRANSPARENT_TEXTURE,
    patch_sprite_mask_formats, patch_terrain_effect_format, patch_transparent_texture,
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=Path('/Applications/factorio.app'))
    parser.add_argument('--unpatched', action='store_true')
    parser.add_argument('--output', type=Path)
    parser.add_argument('game_arguments', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if sys.platform != 'darwin' or platform.machine() != 'arm64':
        parser.error('This debug runner requires an Apple silicon Mac with Xcode.')
    app = args.app.resolve()
    data = app / 'Contents/data'
    executable = app / 'Contents/MacOS/factorio'
    if not executable.is_file() or not (data / 'base/info.json').is_file():
        parser.error('Select a complete Mac Factorio.app.')
    binary = bytearray(remove_signature(arm64_slice(executable.read_bytes())))
    if not args.unpatched:
        if any(pattern not in binary for pattern in (TRANSPARENT_TEXTURE, SPRITE_MASK_FORMATS, TERRAIN_EFFECT_FORMAT)):
            parser.error('This comparison requires the known Factorio 2.0.77 texture patterns.')
        patch_transparent_texture(binary)
        patch_sprite_mask_formats(binary)
        patch_terrain_effect_format(binary)
    output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='factoriopad-no-bc-')).resolve()
    output.mkdir(parents=True, exist_ok=True)
    game = output / 'factorio'
    if game.exists():
        parser.error('The debug output already contains a game executable. Choose a new folder.')
    game.write_bytes(binary)
    game.chmod(0o755)
    guard = output / 'reject-bc.dylib'
    subprocess.run(['xcrun', 'clang', '-dynamiclib', '-fobjc-arc', '-fblocks', '-framework', 'Foundation',
                    '-framework', 'Metal', str(Path(__file__).with_name('reject_bc_textures.m')), '-o', str(guard)], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(game)], check=True)
    config = output / 'config.ini'
    config.write_text(f'; version=13\n[path]\nread-data={data}\nwrite-data={output}\n'
                      '[graphics]\ntexture-compression-level=none\ngpu-accelerated-compression=false\n'
                      'gpu-accelerated-mipmap-compression=false\ncache-sprite-atlas=false\n')
    (output / 'mods').mkdir(exist_ok=True)
    extra = args.game_arguments
    if extra[:1] == ['--']:
        extra = extra[1:]
    command = [str(game), '--config', str(config), '--mod-directory', str(output / 'mods'), '--force-metal',
               '--fullscreen=false', '--window-size', '844x390', '--single-thread-loading', '--nogamepad',
               '--disable-audio', '--force-graphics-preset', 'mac-with-low-ram', '--max-texture-size', '4096',
               '--no-log-rotation', *extra]
    log = output / 'gpu-debug.log'
    print(f'Debug folder: {output}\nLog: {log}', flush=True)
    print('Close the game when the test is complete. A rejected BC request exits with code 86.', flush=True)
    environment = dict(os.environ, DYLD_INSERT_LIBRARIES=str(guard))
    with log.open('w') as stream:
        result = subprocess.run(command, cwd=data, env=environment, stdout=stream, stderr=subprocess.STDOUT)
    if '[FactorioPad GPU guard] Armed' not in log.read_text(errors='replace'):
        raise RuntimeError(f'The GPU guard did not load. Read {log}.')
    print(f'Game exit code: {result.returncode}. Log: {log}', flush=True)
    return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
