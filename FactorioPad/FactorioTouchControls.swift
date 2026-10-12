import Foundation
import CoreGraphics

enum FactorioTouchAction: String, CaseIterable {
    case build, mine, rotate, pick, inventory, more
    case shift, control, shoot, pickup, map, research, alt, vehicle
    case copy, paste, undo, blueprints, deconstruct, upgrade, zoomIn, zoomOut, back, keyboard

    static let primary: [Self] = [.build, .mine, .rotate, .pick, .inventory, .more]
    static let secondary: [Self] = [.shift, .control, .pickup, .map, .research, .alt, .vehicle,
        .copy, .paste, .undo, .blueprints, .deconstruct, .upgrade, .zoomIn, .zoomOut, .back, .keyboard]

    var title: String {
        switch self {
        case .build: return "Build / open"
        case .mine: return "Mine"
        case .rotate: return "Rotate"
        case .pick: return "Pick / clear"
        case .inventory: return "Inventory"
        case .more: return "More"
        case .shift: return "Shift"
        case .control: return "Ctrl"
        case .shoot: return "Shoot"
        case .pickup: return "Pick up"
        case .map: return "Map"
        case .research: return "Research"
        case .alt: return "Details"
        case .vehicle: return "Vehicle"
        case .copy: return "Copy area"
        case .paste: return "Paste"
        case .undo: return "Undo"
        case .blueprints: return "Blueprints"
        case .deconstruct: return "Deconstruct"
        case .upgrade: return "Upgrade"
        case .zoomIn: return "Zoom +"
        case .zoomOut: return "Zoom −"
        case .back: return "Back / menu"
        case .keyboard: return "Keyboard"
        }
    }

    var held: Bool { [.build, .mine, .shoot, .pickup].contains(self) }

    // shortcut: default Factorio bindings only, add mapping support with the layout editor.
    var key: (code: Int32, symbol: Int32, modifiers: UInt16)? {
        switch self {
        case .rotate: return (21, 114, 0)
        case .pick: return (20, 113, 0)
        case .inventory: return (8, 101, 0)
        case .shoot: return (44, 32, 0)
        case .pickup: return (9, 102, 0)
        case .map: return (16, 109, 0)
        case .research: return (23, 116, 0)
        case .alt: return (226, 0x400000e2, 0)
        case .vehicle: return (40, 13, 0)
        case .copy: return (6, 99, 0x0040)
        case .paste: return (25, 118, 0x0040)
        case .undo: return (29, 122, 0x0040)
        case .blueprints: return (5, 98, 0)
        case .deconstruct: return (7, 100, 0x0100)
        case .upgrade: return (24, 117, 0x0100)
        case .back: return (41, 27, 0)
        default: return nil
        }
    }
}

struct FactorioTouchLayout {
    let stick: CGRect
    let actions: [CGRect]
    let shoot: CGRect
    let mode: CGRect
    let panel: CGRect

    init(safeBounds: CGRect) {
        let area = safeBounds.insetBy(dx: 12, dy: 12)
        let height: CGFloat = area.height < 480 ? 48 : 56
        let width = height + 24
        let gap: CGFloat = 8
        let actionWidth = width * 2 + gap
        let actionHeight = height * 3 + gap * 2
        actions = FactorioTouchAction.primary.indices.map { index in
            CGRect(x: area.maxX - actionWidth + CGFloat(index % 2) * (width + gap),
                y: area.maxY - actionHeight + CGFloat(index / 2) * (height + gap), width: width, height: height)
        }
        shoot = CGRect(x: area.maxX - width, y: area.maxY - actionHeight - 52, width: width, height: 44)
        let diameter: CGFloat = area.height < 480 ? 112 : 144
        stick = CGRect(x: area.minX, y: area.maxY - diameter, width: diameter, height: diameter)
        mode = CGRect(x: area.minX + 52, y: area.minY, width: 108, height: 44)
        let panelWidth = min(340, area.width - actionWidth - gap)
        let columns = panelWidth >= 300 ? 3 : 2
        let rows = (FactorioTouchAction.secondary.count + columns - 1) / columns
        panel = CGRect(x: area.minX, y: area.minY + 52,
            width: panelWidth, height: min(CGFloat(rows) * 56 + 8, max(0, area.height - 52)))
    }

    static func movement(at point: CGPoint, radius: CGFloat) -> Set<Int32> {
        guard radius > 0, hypot(point.x, point.y) > radius * 0.18 else { return [] }
        let threshold = hypot(point.x, point.y) * 0.38
        var keys = Set<Int32>()
        if point.x < -threshold { keys.insert(4) }
        if point.x > threshold { keys.insert(7) }
        if point.y < -threshold { keys.insert(26) }
        if point.y > threshold { keys.insert(22) }
        return keys
    }
}

#if canImport(UIKit)
import UIKit

final class FactorioTouchControlsView: UIView {
    var onAction: ((FactorioTouchAction, Bool) -> Void)?
    var onMovement: ((Set<Int32>) -> Void)?
    var onModeChange: (() -> Void)?
    private(set) var precision = false
    private let stick = FactorioTouchStickView()
    private let modeButton = FactorioTouchOnlyButton(type: .system)
    private let panel = UIScrollView()
    private let modifierLabel = UILabel()
    private var buttons: [FactorioTouchAction: UIButton] = [:]
    private var heldActions = Set<FactorioTouchAction>()

    override init(frame: CGRect) {
        super.init(frame: frame)
        overrideUserInterfaceStyle = .dark
        isMultipleTouchEnabled = true
        stick.onMovement = { [weak self] in self?.onMovement?($0) }
        addSubview(stick)
        configure(modeButton, title: "Direct taps")
        modeButton.accessibilityHint = "Tap and drag directly in menus or the game. Tap to switch to precision aiming."
        modeButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.releaseHeldActions()
            self.precision.toggle()
            self.modeButton.setTitle(self.precision ? "Precision aim" : "Direct taps", for: .normal)
            self.modeButton.accessibilityHint = self.precision
                ? "Drag to aim without clicking. Tap to switch to direct taps."
                : "Tap and drag directly in menus or the game. Tap to switch to precision aiming."
            self.onModeChange?()
        }, for: .touchUpInside)
        addSubview(modeButton)
        modifierLabel.textColor = .systemOrange
        modifierLabel.font = .systemFont(ofSize: 13, weight: .medium)
        modifierLabel.isHidden = true
        addSubview(modifierLabel)
        panel.isHidden = true
        panel.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.95)
        panel.layer.cornerRadius = 16
        panel.alwaysBounceVertical = false
        addSubview(panel)
        for action in FactorioTouchAction.allCases {
            let button = FactorioTouchOnlyButton(type: .custom)
            configure(button, title: action.title)
            button.accessibilityHint = action.held ? "Touch and hold. Release to stop." : "Uses the default Factorio binding."
            if action == .shift || action == .control {
                button.accessibilityHint = "Tap to turn this modifier on or off."
            }
            if action.held {
                button.addAction(UIAction { [weak self] _ in self?.press(action) }, for: [.touchDown, .touchDragEnter])
                button.addAction(UIAction { [weak self] _ in
                    self?.release(action)
                }, for: .touchUpInside)
                button.onAccessibilityActivate = { [weak self] in
                    self?.press(action)
                    self?.release(action)
                }
                button.addAction(UIAction { [weak self] _ in self?.release(action) },
                    for: [.touchUpOutside, .touchCancel, .touchDragExit])
                button.accessibilityCustomActions = [
                    UIAccessibilityCustomAction(name: "Hold \(action.title)") { [weak self] _ in self?.press(action); return true },
                    UIAccessibilityCustomAction(name: "Stop \(action.title)") { [weak self] _ in self?.release(action); return true }
                ]
            } else {
                button.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    if action == .more {
                        self.releaseHeldActions()
                        self.panel.isHidden.toggle()
                        self.setSelected(action, !self.panel.isHidden)
                        self.onAction?(action, true)
                    } else {
                        self.onAction?(action, true)
                    }
                }, for: .touchUpInside)
            }
            buttons[action] = button
            (FactorioTouchAction.primary.contains(action) || action == .shoot ? self : panel).addSubview(button)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let layout = FactorioTouchLayout(safeBounds: bounds.inset(by: safeAreaInsets))
        if stick.frame != layout.stick { releaseHeldActions() }
        stick.frame = layout.stick
        modeButton.frame = layout.mode
        modifierLabel.frame = CGRect(x: layout.mode.maxX + 8, y: layout.mode.minY,
            width: max(0, bounds.inset(by: safeAreaInsets).maxX - layout.mode.maxX - 76), height: 44)
        for (action, frame) in zip(FactorioTouchAction.primary, layout.actions) { buttons[action]?.frame = frame }
        buttons[.shoot]?.frame = layout.shoot
        panel.frame = layout.panel
        let gap: CGFloat = 8
        let columns = panel.bounds.width >= 300 ? 3 : 2
        let width = (panel.bounds.width - gap * CGFloat(columns + 1)) / CGFloat(columns)
        for (index, action) in FactorioTouchAction.secondary.enumerated() {
            buttons[action]?.frame = CGRect(x: gap + CGFloat(index % columns) * (width + gap),
                y: gap + CGFloat(index / columns) * 56, width: width, height: 48)
        }
        panel.contentSize = CGSize(width: panel.bounds.width,
            height: gap + CGFloat((FactorioTouchAction.secondary.count + columns - 1) / columns) * 56)
    }

    func setSelected(_ action: FactorioTouchAction, _ selected: Bool) {
        buttons[action]?.isSelected = selected
        buttons[action]?.backgroundColor = selected ? UIColor.systemOrange.withAlphaComponent(0.85) : UIColor.black.withAlphaComponent(0.6)
        buttons[action]?.accessibilityTraits = selected ? [.button, .selected] : [.button]
        if action == .shift || action == .control {
            modifierLabel.text = [FactorioTouchAction.shift, .control].filter { buttons[$0]?.isSelected == true }
                .map(\.title).joined(separator: " + ")
            modifierLabel.isHidden = modifierLabel.text?.isEmpty != false
        }
    }

    func releaseHeldActions() {
        for action in Array(heldActions) { release(action) }
        stick.reset()
    }

    func reset() {
        releaseHeldActions()
        panel.isHidden = true
        for action in [FactorioTouchAction.shift, .control, .more] { setSelected(action, false) }
    }

    private func press(_ action: FactorioTouchAction) {
        guard heldActions.insert(action).inserted else { return }
        setSelected(action, true)
        onAction?(action, true)
    }

    private func release(_ action: FactorioTouchAction) {
        guard heldActions.remove(action) != nil else { return }
        setSelected(action, false)
        onAction?(action, false)
    }

    private func configure(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.setTitleColor(.systemOrange, for: .highlighted)
        button.setTitleColor(.white, for: [.selected, .highlighted])
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 12
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
    }
}

private final class FactorioTouchStickView: UIView {
    var onMovement: ((Set<Int32>) -> Void)?
    private let knob = UIView()
    private let label = UILabel()
    private var activeTouch: UITouch?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.45)
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        knob.backgroundColor = UIColor.white.withAlphaComponent(0.45)
        knob.isUserInteractionEnabled = false
        addSubview(knob)
        label.text = "Move"
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textAlignment = .center
        addSubview(label)
        isAccessibilityElement = true
        accessibilityLabel = "Movement stick"
        accessibilityHint = "Drag in the direction you want to move. Release to stop."
        accessibilityCustomActions = [
            ("Move up", Set<Int32>([26])), ("Move down", [22]),
            ("Move left", [4]), ("Move right", [7]), ("Stop moving", [])
        ].map { name, keys in
            UIAccessibilityCustomAction(name: name) { [weak self] _ in self?.onMovement?(keys); return true }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        knob.bounds.size = CGSize(width: bounds.width * 0.38, height: bounds.height * 0.38)
        knob.layer.cornerRadius = knob.bounds.width / 2
        label.frame = CGRect(x: 0, y: bounds.maxY - 24, width: bounds.width, height: 20)
        if activeTouch == nil { knob.center = CGPoint(x: bounds.midX, y: bounds.midY) }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        update(touch)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let activeTouch, touches.contains(activeTouch) { update(activeTouch) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let activeTouch, touches.contains(activeTouch) { reset() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { reset() }

    func reset() {
        activeTouch = nil
        knob.center = CGPoint(x: bounds.midX, y: bounds.midY)
        onMovement?([])
    }

    private func update(_ touch: UITouch) {
        let point = touch.location(in: self)
        let delta = CGPoint(x: point.x - bounds.midX, y: point.y - bounds.midY)
        let radius = bounds.width / 2
        let distance = max(1, hypot(delta.x, delta.y))
        let scale = min(1, (radius - knob.bounds.width / 2) / distance)
        knob.center = CGPoint(x: bounds.midX + delta.x * scale, y: bounds.midY + delta.y * scale)
        onMovement?(FactorioTouchLayout.movement(at: delta, radius: radius))
    }
}
#endif
