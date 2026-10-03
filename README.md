# FactorioPad

Play Factorio on your iPhone or iPad. You need iOS 17 or iPadOS 17 or newer, plus a gamepad or a keyboard and mouse. Touch supports menus, but not touch-only gameplay.

You need your own copy of Factorio 2.0.77. You do not need Xcode or a Mac.
The companion supports Windows x64, Macs with Apple silicon, and Linux x64.

## Install on your device

1. Download the companion for your computer from [Releases](https://github.com/MyNameIsArko/FactorioPad/releases).
2. Extract the download and open FactorioPad Companion.
3. Download the Mac Factorio 2.0.77 DMG from [factorio.com](https://factorio.com/download), even if you use Windows or Linux.
4. In the companion, select the DMG and click `Prepare app`.
5. Click `Open result` when preparation finishes.
6. Install `FactorioPad.ipa` with [Sideloadly](https://sideloadly.io/) on Windows or Mac, or [iloader](https://github.com/nab138/iloader) on Linux.
7. Copy the generated `FactorioData` folder to Files on your iPhone or iPad.
8. Open FactorioPad, tap `Choose game folder`, and select that folder.

Keep the selected folder on your device. FactorioPad uses it without copying it.
Save sharing is optional. Choose `Play without sync` to start without it.

Keep your generated IPA private because it contains your Factorio executable.

## What changes on iPhone and iPad

- A gamepad uses mouse and keyboard controls. The right stick moves the pointer.
- Physical keyboards and mice support typing, clicks, dragging, and scrolling.
- Touch supports menu taps and drags.
- New installations use a 150% interface scale and one visible quickbar.
- New freeplay games skip the opening cutscene and tutorial prompt.
- Tap the keyboard button to type. Hold it to see the gamepad controls.
- Full-screen play keeps a connected mouse pointer inside the game.

## Share saves through iCloud

Use the same iCloud Drive folder to share saves between your iPhone and iPad:

1. Create a folder in iCloud Drive, such as `FactorioPad Saves`.
2. In FactorioPad, tap `Choose save folder`.
3. Select that iCloud Drive folder on each device.

FactorioPad syncs saves before the game starts and after you exit the game.
Let iCloud finish transferring saves before you continue on another device.
For Mac saves, use the [Mac setup script](Tools/link_macos_saves.sh).

```sh
bash Tools/link_macos_saves.sh
```

For development, see [CONTRIBUTING.md](CONTRIBUTING.md).
