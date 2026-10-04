# FactorioPad

Play Factorio on your iPhone or iPad. You need iOS 17 or iPadOS 17 or newer, plus a gamepad or a keyboard and mouse. Touch supports menus, but not touch-only gameplay.

You need your own copy of Factorio. You do not need Xcode or a Mac.
Tested on Factorio 2.0.77. The companion rejects executable versions that do not match the required startup patch.
The executable and game data must use the same version.
The companion supports Windows x64, Macs with Apple silicon, and Linux x64.

## Install on your device

1. Download the companion for your computer from [Releases](https://github.com/MyNameIsArko/FactorioPad/releases).
2. Extract the download and open FactorioPad Companion.
3. Download the Mac Factorio DMG from [factorio.com](https://factorio.com/download), even if you use Windows or Linux. Use 2.0.77 for the tested version.
4. In the companion, select the DMG and click `Prepare app`.
5. Click `Open result` when preparation finishes.
6. Install `FactorioPad.ipa` with [Sideloadly](https://sideloadly.io/) on Windows or Mac, or [iloader](https://github.com/nab138/iloader) on Linux.
7. Copy the generated `FactorioData` folder to Files on your iPhone or iPad.
8. Open FactorioPad, tap `Choose game folder`, and select that folder.

Keep the selected folder on your device. FactorioPad uses it without copying it.
Save sharing is optional. Choose `Play without sync` to start without it.

Keep your generated IPA private because it contains your Factorio executable.

## Report a startup problem

If the game stays black or stops during startup, open your selected `FactorioData` folder in Files.
Attach `FactorioPad.log` to your GitHub issue.
The log starts before the app opens its window and contains device details, startup steps, and game output.
The app copies the log to `FactorioData` during use.
If you cannot find the file, tap `Share log` on the setup screen.
During a game, hold the keyboard button and tap `Share log` in the controls panel.
The log keeps recent output across app restarts, so you can share it after a failed launch.
The file stays below 4 MiB. Each launch records up to 1 MiB to preserve space for recent failures.

FactorioPad keeps its own app folder hidden in Files.
Keep `FactorioData` in a folder that you create under `On My iPhone`, `On My iPad`, or iCloud Drive.
Existing game data inside the app stays available through its saved folder selection.

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
