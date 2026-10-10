import SwiftUI

struct FactorioControllerModePicker: View {
    var activeNativeController: Bool? = nil
    @AppStorage("FactorioNativeController") private var nativeController = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Controls").font(.headline)
                Spacer()
                Picker("Controls", selection: $nativeController) {
                    Text("Mouse and keyboard emulation").tag(false)
                    Text("Factorio native controls").tag(true)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .focusable(false)
            }
            if let active = activeNativeController {
                Text("This launch: \(active ? "Factorio native controls" : "Mouse and keyboard emulation")")
                    .foregroundStyle(.secondary)
                if nativeController != active {
                    Text("Save your game, then close and reopen the app to apply this change.")
                        .foregroundStyle(.orange)
                }
            } else {
                Text("Your choice applies when the game starts.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FactorioControlsView: View {
    var onClose: () -> Void
    var onSaves: () -> Void
    var logURL: URL? = nil
    var nativeControllerActive = false

    typealias Activity = (title: String, icon: String, controls: [(action: String, buttons: String)])
    static let activities: [Activity] = [
        ("Movement and driving", "figure.walk", [
            ("Move your character", "Left stick"),
            ("Move the pointer", "Right stick"),
            ("Enter or leave a vehicle", "RB + A"),
            ("Shoot nearby enemies", "Y"),
            ("Shoot the selected target", "LB + Y"),
            ("Select next weapon", "RB + D-pad →"),
            ("Zoom out", "Left stick click"),
            ("Zoom in", "Right stick click")
        ]),
        ("Building and machines", "hammer", [
            ("Build or open a machine", "RT"),
            ("Mine or remove", "LT"),
            ("Select matching item or ghost", "B"),
            ("Rotate clockwise", "X"),
            ("Rotate counterclockwise", "LB + X"),
            ("Toggle Alt-mode details", "RB + Y"),
            ("Copy machine settings", "LB + LT"),
            ("Paste machine settings", "LB + RT"),
            ("Insert a held stack or take items", "RB + RT"),
            ("Insert or take half", "RB + LT")
        ]),
        ("Inventory and items", "shippingbox", [
            ("Open inventory", "A"),
            ("Clear held item", "B"),
            ("Pick up items from the ground", "LB + A"),
            ("Drop one held item", "LB + B"),
            ("Toggle inventory slot filter", "RB + D-pad ↑"),
            ("Transfer selected stack", "LB + RT"),
            ("Transfer half of selected stack", "LB + LT"),
            ("Transfer all of selected item", "RB + RT"),
            ("Transfer half of selected item", "RB + LT")
        ]),
        ("Quickbars", "square.grid.2x2", [
            ("Select slots 1 / 2 / 3 / 4", "D-pad ↑ / → / ↓ / ←"),
            ("Select quickbars 1 / 2 / 3 / 4", "LB + D-pad"),
            ("Clear slot assignment", "RB + D-pad ↑")
        ]),
        ("Blueprints and editing", "doc.on.doc", [
            ("Select deconstruction planner", "RB + D-pad ↓"),
            ("Select upgrade planner", "RB + D-pad ←"),
            ("Copy an area", "RB + B"),
            ("Cut an area", "LB + RB + B"),
            ("Paste copied entities", "RB + X"),
            ("Undo", "LB + RB + X"),
            ("Redo", "LB + RB + Y"),
            ("Open blueprint library", "LB + RB + View"),
            ("Cycle blueprints in a held book", "LB + stick clicks")
        ]),
        ("Maps and menus", "map", [
            ("Open world map", "View"),
            ("Open technology screen", "LB + View"),
            ("Open production statistics", "RB + View"),
            ("Open menu or go back", "Menu"),
            ("Close a window", "A")
        ])
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Controller controls", systemImage: "gamecontroller")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Save sync", action: onSaves)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .focusable(false)
                Button("Back to game", action: onClose)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.large)
                    .focusable(false)
            }
            .padding(20)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    FactorioControllerModePicker(activeNativeController: nativeControllerActive)
                    if let log = logURL {
                        ShareLink("Share log", item: log)
                            .buttonStyle(.bordered)
                            .focusable(false)
                    }
                    if nativeControllerActive {
                        Text("Factorio handles your controller directly, with analog movement and its controller interface.")
                            .foregroundStyle(.secondary)
                        Text("Connect a controller before starting the game. Open Settings → Controls in Factorio to select controller input or change its bindings.")
                            .foregroundStyle(.secondary)
                        Text("Tap the keyboard button to type. Touch, physical keyboard, and mouse input remain available.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Hold LB (Shift) or RB (Ctrl) before the other button. In an inventory, point at the stack you want to transfer.")
                            .foregroundStyle(.secondary)
                        Text("To change a quickbar assignment, point at the slot and press RB + D-pad ↑ to clear it. With an empty hand, press RT on the empty slot and choose a replacement item. Release LT before clearing a slot.")
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), alignment: .top)],
                            alignment: .leading, spacing: 16) {
                            ForEach(Self.activities.indices, id: \.self) { index in
                                activityCard(Self.activities[index])
                            }
                        }
                        Text("Xbox-style positions: A is bottom, B is right, X is left, and Y is top. View is also called Options; Menu is also called Start. These are the default FactorioPad bindings. Custom bindings in Factorio can change them.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color(white: 0.06).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .accessibilityAddTraits(.isModal)
    }

    private func activityCard(_ activity: Activity) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(activity.title, systemImage: activity.icon)
                .font(.headline)
                .foregroundStyle(.orange)
                .accessibilityAddTraits(.isHeader)
            ForEach(activity.controls.indices, id: \.self) { index in
                let control = activity.controls[index]
                HStack(spacing: 12) {
                    Text(control.action).frame(maxWidth: .infinity, alignment: .leading)
                    Text(control.buttons)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }
}
