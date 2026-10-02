# FactorioPad

Play Factorio on iPhone and iPad with a gamepad or a physical keyboard and mouse.

> [!IMPORTANT]
> FactorioPad does not include the game. Download the Mac version from [factorio.com](https://factorio.com/download), not Steam.
> Install `factorio.app` in `/Applications` on your Mac before you build the IPA.

## What you need

- A Mac with Xcode 26 or later.
- An iPhone or iPad with iOS 17 or iPadOS 17 or later.
- A gamepad, or a physical keyboard and mouse.
- `factorio.app` in `/Applications` on the Mac.

FactorioPad was tested with Factorio 2.0.77 and a gamepad on an iPad mini (7th generation) and an iPhone 15 Pro. The project targets iOS 17+ and iPadOS 17+. Older versions are untested. Other game versions are untested.

## What changes on iPhone and iPad

- A gamepad acts as a mouse and keyboard. The right stick moves the mouse pointer.
- A physical keyboard uses the game's keyboard controls. A mouse supports movement, clicks, dragging, and scrolling.
- Touch supports menu taps and drags, but not touch-only gameplay.
- Gamepad buttons send Factorio's default keyboard shortcuts. Some keys, including Tab, are not mapped to the gamepad.
- New freeplay games skip the opening cutscene and tutorial prompt, so a gamepad does not need Tab to start playing.
- New installations use a 150% interface scale and one visible quickbar.
- A button opens the on-screen keyboard when a gamepad is connected or no physical keyboard is connected. Hold it to see the gamepad controls.
- Full-screen play locks a connected mouse pointer to keep it inside the game.

## Use a keyboard and mouse

Connect a physical keyboard and mouse to your iPhone or iPad. FactorioPad detects them automatically, and the keyboard uses your existing Factorio key bindings. The mouse moves the pointer and supports clicks, dragging, and scrolling. You can also keep a gamepad connected.

## Build an IPA

An IPA is an app file for your iPhone or iPad. Open Terminal in the FactorioPad project folder.
Run this command:

```sh
bash Tools/build_ipa.sh
```

The same IPA supports a gamepad and a physical keyboard and mouse. FactorioPad keeps Factorio's default key bindings.

The IPA appears at `dist/FactorioPad.ipa`. Move it to your device through Files or iCloud Drive.
Install it with [AltStore Classic](https://faq.altstore.io/altstore-classic/altserver) or [SideStore](https://docs.sidestore.io/docs/installation/prerequisites).
With a free Apple Account, refresh the installed app within seven days. You do not need to rebuild the IPA each week.

> [!NOTE]
> Keep the IPA private because it contains your copy of Factorio. The [MIT license](LICENSE) covers only the FactorioPad source code.

### Sync saves across Apple devices

In the FactorioPad project folder, run this command once:

```sh
bash Tools/link_macos_saves.sh
```

The script copies your Mac saves to `iCloud Drive/FactorioPad Saves`. It links Factorio's save folder to that location. It keeps the original folder as `saves.before-factoriopad`. If the iCloud folder already contains saves, the script stops. Merge those saves before you run it again.

When FactorioPad first opens on an iPhone or iPad, choose `iCloud Drive/FactorioPad Saves` in Files. FactorioPad syncs saves with that folder before the game starts.

## Run from Xcode

1. Open Terminal in the FactorioPad project folder.
2. Run `bash Tools/build_ipa.sh --prepare-only` to prepare your game files.
3. Open `FactorioPad.xcodeproj` in Xcode.
4. Connect your iPhone or iPad to your Mac.
5. Select your device in Xcode.
6. In Signing & Capabilities, select your Apple team.
7. Set a unique Bundle Identifier, such as `com.yourname.FactorioPad`.
8. Press Run.
