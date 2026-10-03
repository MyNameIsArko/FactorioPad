#!/usr/bin/env python3
"""Build the shared companion and a game-free release archive on the current OS."""

import argparse
import hashlib
import importlib.metadata
import os
from pathlib import Path
import platform
import shutil
import ssl
import subprocess
import sys
import sysconfig
import tarfile
import tempfile
import urllib.request
import zipfile

from package_ipa import make_template


SEVEN_ZIP_VERSION = "26.03"
# Each platform maps to an official download filename and its SHA-256 hash.
SEVEN_ZIP = {
    "darwin": ("7z2603-mac.tar.xz", "5ca87677072c59f5602e5c49baa27d4694bacd2259b4e507f0094249d4281480"),
    "linux": ("7z2603-linux-x64.tar.xz", "dc99eff5008f1ab79bd7084c68513701547a808a89502bf4133683535ab3c695"),
    "win32": ("7z2603-x64.exe", "0859c524b8a63551848f0c246abddcb1d0b7b656b0fbfe879f8d85e61a9e6edd"),
}
PROJECT = Path(__file__).resolve().parents[1]
NAME = "FactorioPad Companion"


def download(url):
    context = ssl.create_default_context()
    # Some python.org Mac installations omit their default certificate file.
    if sys.platform == "darwin" and ssl.get_default_verify_paths().cafile is None and Path("/etc/ssl/cert.pem").is_file():
        context.load_verify_locations("/etc/ssl/cert.pem")
    with urllib.request.urlopen(url, context=context, timeout=60) as response:
        return response.read()


def platform_name():
    machine = platform.machine().lower()
    if sys.platform == "darwin" and machine == "arm64":
        return "macOS-arm64"
    if machine in ("x86_64", "amd64") and sys.platform in ("win32", "linux"):
        return ("Windows" if sys.platform == "win32" else "Linux") + "-x64"
    raise ValueError("Build on Windows x64, macOS arm64, or Linux x64.")


def prepare_seven_zip(destination):
    filename, checksum = SEVEN_ZIP[sys.platform]
    url = f"https://github.com/ip7z/7zip/releases/download/{SEVEN_ZIP_VERSION}/{filename}"
    cache = PROJECT / "Vendor" / "CompanionDownloads" / filename
    if not cache.is_file() or hashlib.sha256(cache.read_bytes()).hexdigest() != checksum:
        cache.parent.mkdir(parents=True, exist_ok=True)
        data = download(url)
        if hashlib.sha256(data).hexdigest() != checksum:
            raise ValueError("The 7-Zip download failed its integrity test. Download it again.")
        cache.write_bytes(data)
    destination.mkdir(parents=True)
    if sys.platform == "win32":
        extractor = shutil.which("7z") or str(Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "7-Zip/7z.exe")
        if not Path(extractor).is_file():
            raise ValueError("Install 7-Zip on the Windows computer that builds the companion.")
        subprocess.run([extractor, "x", "-y", "-bd", "-bso0", "-bsp0", "-o" + str(destination),
                        str(cache), "7z.exe", "7z.dll", "License.txt"], check=True)
        required = ("7z.exe", "7z.dll", "License.txt")
    else:
        required = ("7zz", "License.txt")
        with tarfile.open(cache) as archive:
            for name in required:
                member = archive.getmember(name)
                if not member.isfile():
                    raise ValueError("The 7-Zip archive contains an invalid file.")
                with archive.extractfile(member) as source:
                    (destination / name).write_bytes(source.read())
        (destination / "7zz").chmod(0o755)
    if not all((destination / name).is_file() for name in required):
        raise ValueError("The bundled 7-Zip files are incomplete.")
    (destination / "SOURCE.txt").write_text(
        f"7-Zip {SEVEN_ZIP_VERSION}\nDownload: {url}\n"
        f"Source: https://github.com/ip7z/7zip/tree/{SEVEN_ZIP_VERSION}\nLicense: License.txt\n", encoding="utf-8")


def write_archive(folder, output):
    if sys.platform == "linux":
        # Tar preserves executable permissions in Linux file managers.
        with tarfile.open(output, "w:gz") as archive:
            archive.add(folder, arcname=folder.name)
    elif sys.platform == "darwin":
        # ditto preserves the .app bundle's framework links and executable bits.
        subprocess.run(["/usr/bin/ditto", "--norsrc", "--noextattr", "-c", "-k", "--keepParent", str(folder), str(output)], check=True)
    else:
        with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(folder.rglob("*")):
                if path.is_file():
                    archive.write(path, folder.name + "/" + path.relative_to(folder).as_posix())


def copy_runtime_licenses(destination):
    import tkinter
    destination.mkdir()
    candidates = (Path(sysconfig.get_path("stdlib")) / "LICENSE.txt",
                  Path(sys.base_prefix) / "LICENSE.txt", Path(sys.base_prefix) / "LICENSE")
    python_license = next((path for path in candidates if path.is_file()), None)
    if python_license:
        shutil.copyfile(python_license, destination / "Python.txt")
    else:
        url = f"https://raw.githubusercontent.com/python/cpython/v{platform.python_version()}/LICENSE"
        (destination / "Python.txt").write_bytes(download(url))
    distribution = importlib.metadata.distribution("pyinstaller")
    license_path = next(path for path in distribution.files if path.name == "COPYING.txt")
    shutil.copyfile(distribution.locate_file(license_path), destination / "PyInstaller.txt")
    window = tkinter.Tk()
    window.withdraw()
    versions = {"tcl": window.tk.call("info", "patchlevel"), "tk": window.tk.getvar("tk_patchLevel")}
    window.destroy()
    for name, version in versions.items():
        tag = "core-" + str(version).replace(".", "-")
        url = f"https://raw.githubusercontent.com/tcltk/{name}/{tag}/license.terms"
        (destination / (name + ".txt")).write_bytes(download(url))


def make_release(ipa, output):
    target = platform_name()
    suffix = ".tar.gz" if sys.platform == "linux" else ".zip"
    if not str(output).endswith(suffix):
        raise ValueError(f"Use an output filename that ends with {suffix} on this platform.")
    if output.exists():
        raise ValueError("The release archive already exists. Choose a new path.")
    try:
        import tkinter
        import PyInstaller
    except ImportError as error:
        raise ValueError("Run uv sync with Python that includes Tk before building the companion.") from error
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent) as temporary:
        work = Path(temporary).resolve()
        resources = work / "resources"
        resources.mkdir()
        # Always strip game files, even when the input is a personal IPA.
        make_template(ipa, resources / "FactorioPad-template.ipa")
        prepare_seven_zip(resources / "7zip")
        shutil.copyfile(PROJECT / "Tools/freeplay_control.lua", resources / "freeplay_control.lua")
        command = [sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", "--onedir", "--windowed", "--noupx",
                   "--name", NAME, "--distpath", str(work / "dist"), "--workpath", str(work / "build"),
                   "--specpath", str(work), "--add-data", str(resources) + os.pathsep + ".", str(PROJECT / "Tools/companion.py")]
        if sys.platform == "darwin":
            command.extend(["--osx-bundle-identifier", "pl.adrian.FactorioPad.Companion"])
        subprocess.run(command, check=True)
        release = work / ("FactorioPad-Companion-" + target)
        release.mkdir()
        product = work / "dist" / (NAME + ".app" if sys.platform == "darwin" else NAME)
        shutil.move(str(product), release / product.name)
        for name in ("README.txt", "LICENSE"):
            shutil.copyfile(PROJECT / name, release / name)
        copy_runtime_licenses(release / "Licenses")
        executable = (release / product.name / "Contents/MacOS" / NAME if sys.platform == "darwin"
                      else release / product.name / (NAME + ".exe" if sys.platform == "win32" else NAME))
        subprocess.run([str(executable), "--self-test"], check=True, timeout=60)
        staging = work / ("release" + suffix)
        write_archive(release, staging)
        staging.rename(output)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template", required=True, type=Path, help="The common game-free template IPA.")
    parser.add_argument("--output", type=Path, help="The release archive path. It must not exist.")
    args = parser.parse_args()
    try:
        target = platform_name()
        output = args.output or PROJECT / "dist" / ("FactorioPad-Companion-" + target + (".tar.gz" if sys.platform == "linux" else ".zip"))
        print(f"Building the shared companion for {target}...", flush=True)
        make_release(args.template, output)
        print(f"Release archive ready: {output}")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"ERROR: {error}\n")


if __name__ == "__main__":
    main()
