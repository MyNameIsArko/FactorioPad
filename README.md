# FactorioPad

Play Factorio on your iPhone or iPad. You need iOS 17 or iPadOS 17 or newer. Use touch controls, a gamepad, or a keyboard and mouse.

You need your own copy of Factorio. You do not need Xcode or a Mac.
Tested on Factorio 2.0.77. Other versions are allowed but untested.
The companion skips texture fixes when it cannot find their instruction patterns.
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
8. Open FactorioPad, tap `Import game data`, and select that folder.

Wait for the import progress bar to finish. FactorioPad keeps its own copy for later launches.
After import, you can remove the original folder.
Before you press `Play`, choose a mode from the `Controls` and `Graphics` dropdowns.
`Low (less memory)` reduces texture detail and disables high-quality animations and shadows. The app remembers both choices.
Save sharing is optional. Choose `Play without sync` to start without it.

Keep your generated IPA private because it contains your Factorio executable.

## What changes on iPhone and iPad

- A gamepad uses `Mouse and keyboard emulation` by default. Select `Factorio native controls` for analog movement and Factorio's controller interface.
- Physical keyboards and mice support typing, clicks, dragging, and scrolling.
- Touch controls provide movement, aiming, building, mining, and shortcuts on iPhone and iPad.
- New installations use a 150% interface scale and one visible quickbar.
- New freeplay games skip the opening cutscene and tutorial prompt.
- Tap the keyboard button to type. Hold it to see the gamepad controls.
- Full-screen play keeps a connected mouse pointer inside the game.

## Play with touch controls

Choose `Mouse and keyboard emulation` before you press `Play`.
The default touch layout appears when no gamepad, keyboard, or mouse is connected.
Tap the hand button to show or hide it. The app remembers that choice.

Use `Direct taps` for menus and inventory taps or drags.
Tap that button to switch to `Precision aim`. Drag on the game to move the pointer without clicking.
Hold `Build / open` or `Mine` to act at the pointer. Release to stop.
Drag the movement stick to walk. Pinch to zoom in `Precision aim`.

Hold `Shoot` to fire while you move. Use `More` for maps, blueprints, zoom buttons, and other shortcuts.
Tap `Shift` or `Ctrl` to turn the modifier on or off for item transfers and other actions.
The active modifiers remain visible beside the aiming button.
The controls use Factorio's default keyboard bindings. Custom bindings can change their actions.
The layout fits the safe area on both iPhone and iPad. Layout editing is not included.

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

## Report a crash

If the app or game crashes, reopen FactorioPad.
Tap `Share log` on the setup screen.
Attach `FactorioPad.log` to your GitHub issue.
