#!/usr/bin/env python3
"""The same offline FactorioPad companion on Windows, macOS, and Linux."""

from pathlib import Path
import os
import queue
import subprocess
import sys
import tempfile
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
import webbrowser

from package_ipa import MARKER, package_dmg


def resource_root():
    return Path(__file__).resolve().parent


def result_folder(parent):
    output = parent / "FactorioPad-personal"
    number = 2
    while output.exists():
        output = parent / f"FactorioPad-personal-{number}"
        number += 1
    return output


def prepare_game(dmg, parent, resources, progress):
    template = resources / "FactorioPad-template.ipa"
    extractor = resources / "7zip" / ("7z.exe" if sys.platform == "win32" else "7zz")
    if not template.is_file() or not extractor.is_file():
        raise ValueError("The companion files are missing. Extract the entire release archive, then open the app again.")
    output = result_folder(parent)
    package_dmg(template, dmg, output, extractor, progress=progress)
    return output


def open_folder(path):
    if sys.platform == "win32":
        os.startfile(path)
    else:
        subprocess.Popen(["open" if sys.platform == "darwin" else "xdg-open", str(path)])


class Companion:
    def __init__(self, window):
        self.window = window
        self.busy = False
        self.output = None
        self.events = queue.Queue()
        self.image = tk.StringVar()
        self.destination = tk.StringVar(value=str(Path.home() / "Downloads"))
        self.status = tk.StringVar(value="Select your game download to start.")
        self.instructions = tk.StringVar(value="The app keeps your DMG unchanged. Keep your prepared IPA private because it contains your Factorio executable.")
        window.title("FactorioPad Companion")
        window.minsize(650, 430)
        window.protocol("WM_DELETE_WINDOW", self.close)
        frame = ttk.Frame(window, padding=24)
        frame.grid(sticky="nsew")
        window.columnconfigure(0, weight=1)
        window.rowconfigure(0, weight=1)
        frame.columnconfigure(0, weight=1)
        ttk.Label(frame, text="Prepare FactorioPad", font=("", 20, "bold")).grid(row=0, column=0, columnspan=2, sticky="w")
        ttk.Label(frame, text="Select the Mac Factorio DMG from factorio.com.").grid(
            row=1, column=0, columnspan=2, sticky="w", pady=(8, 20))
        ttk.Label(frame, text="Factorio DMG").grid(row=2, column=0, sticky="w")
        ttk.Entry(frame, textvariable=self.image, state="readonly", width=55).grid(row=3, column=0, sticky="ew", pady=6)
        self.choose_image = ttk.Button(frame, text="Choose DMG", command=self.pick_image)
        self.choose_image.grid(row=3, column=1, padx=(12, 0))
        ttk.Label(frame, text="Save the result in").grid(row=4, column=0, sticky="w", pady=(10, 0))
        ttk.Entry(frame, textvariable=self.destination, state="readonly").grid(row=5, column=0, sticky="ew", pady=6)
        self.choose_folder = ttk.Button(frame, text="Choose folder", command=self.pick_folder)
        self.choose_folder.grid(row=5, column=1, padx=(12, 0))
        buttons = ttk.Frame(frame)
        buttons.grid(row=6, column=0, columnspan=2, sticky="w", pady=(16, 8))
        self.prepare_button = ttk.Button(buttons, text="Prepare app", command=self.prepare)
        self.prepare_button.pack(side="left")
        self.open_button = ttk.Button(buttons, text="Open result", state="disabled", command=self.open_result)
        self.open_button.pack(side="left", padx=12)
        self.progress = ttk.Progressbar(frame, mode="indeterminate")
        self.progress.grid(row=7, column=0, columnspan=2, sticky="ew", pady=8)
        ttk.Label(frame, textvariable=self.status, wraplength=600).grid(row=8, column=0, columnspan=2, sticky="w", pady=8)
        ttk.Label(frame, textvariable=self.instructions, wraplength=600, justify="left").grid(
            row=9, column=0, columnspan=2, sticky="w", pady=8)
        ttk.Button(frame, text="Sideloading help", command=lambda: webbrowser.open(
            "https://github.com/MyNameIsArko/FactorioPad#install-on-your-device")).grid(row=10, column=0, sticky="w", pady=8)
        window.after(100, self.poll)

    def pick_image(self):
        selected = filedialog.askopenfilename(parent=self.window, title="Select your Factorio DMG", filetypes=[("Mac disk images", "*.dmg")])
        if selected:
            self.image.set(selected)

    def pick_folder(self):
        selected = filedialog.askdirectory(parent=self.window, title="Choose where to save the result", initialdir=self.destination.get())
        if selected:
            self.destination.set(selected)

    def prepare(self):
        dmg = Path(self.image.get())
        if not self.image.get() or not dmg.is_file() or dmg.suffix.lower() != ".dmg":
            messagebox.showerror("Select a game download", "Select your Mac Factorio DMG first.", parent=self.window)
            return
        self.busy = True
        self.output = None
        for button in (self.prepare_button, self.choose_image, self.choose_folder, self.open_button):
            button.configure(state="disabled")
        self.progress.start()
        self.status.set("Preparing your app. Keep this window open until preparation finishes.")
        # Tk calls stay on the main thread. The worker only posts queue messages.
        parent = Path(self.destination.get())
        def worker():
            try:
                output = prepare_game(dmg, parent, resource_root(), lambda text: self.events.put(("progress", text)))
                self.events.put(("done", output))
            except Exception as error:
                self.events.put(("error", str(error)))
        threading.Thread(target=worker, daemon=True).start()

    def poll(self):
        while True:
            try:
                kind, value = self.events.get_nowait()
            except queue.Empty:
                break
            if kind == "progress":
                self.status.set(value)
                continue
            self.busy = False
            self.progress.stop()
            for button in (self.prepare_button, self.choose_image, self.choose_folder):
                button.configure(state="normal")
            if kind == "done":
                self.output = value
                self.open_button.configure(state="normal")
                self.status.set("Your app is ready. Click Open result to see the files.")
                self.instructions.set("Install FactorioPad.ipa with your sideloading tool.\nTransfer FactorioData to Files on your iPhone or iPad.\nOpen FactorioPad and choose that folder. Keep the selected folder on your device.")
            else:
                self.status.set("Preparation failed. Select another DMG or destination and try again.")
                messagebox.showerror("Cannot prepare FactorioPad", value, parent=self.window)
        self.window.after(100, self.poll)

    def open_result(self):
        try:
            open_folder(self.output)
        except OSError as error:
            messagebox.showerror("Cannot open the folder", str(error), parent=self.window)

    def close(self):
        if self.busy:
            self.status.set("Wait for preparation to finish before you close this window.")
        else:
            self.window.destroy()


def self_test():
    """Exercise the packaged runtime before publishing a release."""
    window = tk.Tk()
    window.withdraw()
    Companion(window)
    window.update()
    resources = resource_root()
    import zipfile
    with zipfile.ZipFile(resources / "FactorioPad-template.ipa") as archive:
        assert any(name.endswith(MARKER) for name in archive.namelist())
        assert not any("/FactorioData/" in name or "/FactorioGuest.framework/" in name for name in archive.namelist())
    extractor = resources / "7zip" / ("7z.exe" if sys.platform == "win32" else "7zz")
    subprocess.run([str(extractor), "i"], check=True, stdout=subprocess.DEVNULL,
                   creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0)
    # An optional local DMG exercises extraction and patching with the frozen app.
    if len(sys.argv) == 3:
        with tempfile.TemporaryDirectory(prefix="factoriopad-self-test-") as temporary:
            output = prepare_game(Path(sys.argv[2]), Path(temporary), resources, lambda text: None)
            assert (output / "FactorioPad.ipa").is_file()
            assert (output / "FactorioData/base/info.json").is_file()
    window.destroy()


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        try:
            self_test()
        except Exception:
            sys.exit(1)
    else:
        window = tk.Tk()
        Companion(window)
        window.mainloop()
