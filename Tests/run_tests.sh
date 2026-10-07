#!/bin/sh
set -eu

project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/factoriopad-tests.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
cd "$project_dir"

xcrun clang++ -fobjc-arc -fblocks -IFactorioCompat -framework Foundation -framework CoreGraphics \
    Tests/test_config.mm -o "$test_dir/config"
"$test_dir/config"
xcrun clang++ -fobjc-arc -fblocks -IFactorioCompat -framework Foundation -framework CoreGraphics \
    Tests/test_import.mm -o "$test_dir/import"
"$test_dir/import"
xcrun clang++ -fobjc-arc -fblocks -IFactorioCompat -framework Foundation -framework CoreGraphics \
    Tests/test_logging.mm -o "$test_dir/logging"
"$test_dir/logging"
xcrun clang -fobjc-arc -fblocks -framework Foundation Tests/test_workspace.m -o "$test_dir/workspace"
"$test_dir/workspace"
xcrun swiftc FactorioPad/FactorioOnScreenKeyboard.swift Tests/test_keyboard.swift -o "$test_dir/keyboard"
"$test_dir/keyboard"
xcrun swiftc FactorioPad/FactorioMouseButtonSources.swift Tests/test_mouse_buttons.swift -o "$test_dir/mouse-buttons"
"$test_dir/mouse-buttons"
xcrun clang -fobjc-arc -fblocks -framework Foundation Tests/test_keyboard_bridge.m -o "$test_dir/keyboard-bridge"
"$test_dir/keyboard-bridge"
xcrun clang -fobjc-arc -fblocks -framework Foundation -framework GameController -framework QuartzCore -framework CoreGraphics \
    Tests/test_controller.m -o "$test_dir/controller"
"$test_dir/controller"
xcrun clang -fobjc-arc -fblocks -Wl,-export_dynamic -framework Foundation -framework GameController -framework QuartzCore -framework CoreGraphics \
    Tests/test_input.m -o "$test_dir/input"
"$test_dir/input"
xcrun swiftc FactorioPad/FactorioControlsView.swift Tests/test_controls.swift -o "$test_dir/controls"
"$test_dir/controls"
xcrun swiftc FactorioPad/FactorioSaveSync.swift Tests/test_save_sync.swift -o "$test_dir/save-sync"
"$test_dir/save-sync"
python3 Tests/test_prepare_guest.py
python3 Tests/test_package_ipa.py

python3 Tests/test_companion.py
