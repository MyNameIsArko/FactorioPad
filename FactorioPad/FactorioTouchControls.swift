import Foundation
import CoreGraphics

enum FactorioTouchAction: String, CaseIterable {
    case build, mine, rotate, pick, inventory, more
    case shift, control, shoot, pickup, map, research, alt, vehicle
    case copy, paste, undo, blueprints, deconstruct, upgrade, zoomIn, zoomOut, back, keyboard

    static let primary: [Self] = [.build, .mine, .rotate, .pick, .inventory, .shoot, .more]
    static let groups: [[Self]] = [
        [.copy, .paste, .undo, .blueprints, .deconstruct, .upgrade],
        [.shift, .control, .pickup, .inventory, .back, .keyboard],
        [.map, .research, .alt, .vehicle, .zoomIn, .zoomOut]
    ]

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
    let toolbar: CGRect
    let panel: CGRect
    let menuActions: [CGRect]
    let edgeInset: CGFloat

    init(safeBounds: CGRect) {
        let compact = safeBounds.height < 500 || safeBounds.width < 700
        let edgeInset: CGFloat = compact ? 32 : 48
        self.edgeInset = edgeInset
        let bottom: CGFloat = compact ? 28 : 48
        let diameter: CGFloat = compact ? 128 : 152
        stick = CGRect(x: safeBounds.minX + edgeInset,
            y: safeBounds.maxY - bottom - diameter, width: diameter, height: diameter)
        let short = safeBounds.height < 330
        let center = CGPoint(x: safeBounds.maxX - edgeInset - (short ? 84 : 100),
            y: safeBounds.maxY - bottom - (short ? 84 : 102))
        let size: CGFloat = compact ? 52 : 56
        let positions: [(CGFloat, CGFloat, CGFloat)] = short ? [
            (0, 0, 60), (0, 62, 44), (-62, 0, 44),
            (-32, -56, 44), (32, -56, 44), (62, 0, 44), (56, 54, 44)
        ] : [
            (0, 0, compact ? 68 : 76), (0, 74, size), (-72, 0, size),
            (-42, -66, size), (38, -66, size), (72, 0, size), (58, 66, size)
        ]
        actions = positions.map { x, y, size in
            CGRect(x: center.x + x - size / 2, y: center.y + y - size / 2, width: size, height: size)
        }
        let toolbarWidth = min(320, safeBounds.width - edgeInset * 2)
        toolbar = CGRect(x: safeBounds.midX - toolbarWidth / 2,
            y: safeBounds.minY + (compact ? 20 : 28), width: toolbarWidth, height: 52)
        let panelWidth = min(352, safeBounds.width - 32)
        let panelHeight = min(276, safeBounds.height - 24)
        panel = CGRect(x: safeBounds.midX - panelWidth / 2, y: safeBounds.midY - panelHeight / 2,
            width: panelWidth, height: panelHeight)
        menuActions = (0..<3).map { index in
            CGRect(x: safeBounds.maxX - edgeInset - 52 - CGFloat(2 - index) * 60,
                y: safeBounds.maxY - bottom - 52, width: 52, height: 52)
        }
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

private let touchAmber = UIColor(red: 0.96, green: 0.70, blue: 0.30, alpha: 1)
private let touchSurface = UIColor(red: 0.10, green: 0.12, blue: 0.13, alpha: 0.88)

private final class FactorioTouchSegments: UISegmentedControl {
    override var canBecomeFocused: Bool { false }
}

private extension FactorioTouchAction {
    var symbol: String {
        switch self {
        case .build: return "hammer.fill"
        case .mine: return "wrench.adjustable.fill"
        case .rotate: return "rotate.right"
        case .pick: return "eyedropper"
        case .inventory: return "shippingbox.fill"
        case .more: return "square.grid.2x2.fill"
        case .shift: return "shift"
        case .control: return "control"
        case .shoot: return "scope"
        case .pickup: return "hand.raised.fingers.spread.fill"
        case .map: return "map.fill"
        case .research: return "flask.fill"
        case .alt: return "info.circle"
        case .vehicle: return "car.fill"
        case .copy: return "doc.on.doc"
        case .paste: return "doc.on.clipboard"
        case .undo: return "arrow.uturn.backward"
        case .blueprints: return "book.closed.fill"
        case .deconstruct: return "trash"
        case .upgrade: return "arrow.up.square"
        case .zoomIn: return "plus.magnifyingglass"
        case .zoomOut: return "minus.magnifyingglass"
        case .back: return "arrow.backward"
        case .keyboard: return "keyboard"
        }
    }

    var caption: String {
        switch self {
        case .build: return "Build"
        case .pick: return "Pick"
        case .inventory: return "Items"
        case .more: return "Tools"
        case .shoot: return "Fire"
        case .blueprints: return "Plans"
        case .deconstruct: return "Remove"
        case .pickup: return "Collect"
        case .back: return "Back"
        case .copy: return "Copy"
        default: return title
        }
    }
}

final class FactorioTouchControlsView: UIView {
    var onAction: ((FactorioTouchAction, Bool) -> Void)?
    var onMovement: ((Set<Int32>) -> Void)?
    var onAim: ((CGPoint) -> Void)?
    var onModeChange: (() -> Void)?
    var onHide: (() -> Void)?
    var onHelp: (() -> Void)?
    private(set) var precision = false
    private let stick = FactorioTouchStickView()
    private let toolbar = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let mode = FactorioTouchSegments(items: ["Menus", "Play"])
    private let modifierLabel = UILabel()
    private let palette = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    private let groups = FactorioTouchSegments(items: ["Build", "Items", "World"])
    private let closeButton = FactorioTouchOnlyButton(type: .custom)
    private let backdrop = UIControl()
    private var buttons: [FactorioTouchAction: FactorioTouchActionButton] = [:]
    private var paletteButtons: [FactorioTouchAction: FactorioTouchActionButton] = [:]
    private var utilityButtons: [UIButton] = []
    private var menuButtons: [FactorioTouchActionButton] = []
    private var heldActions = Set<FactorioTouchAction>()
    private let feedback = UISelectionFeedbackGenerator()

    override init(frame: CGRect) {
        super.init(frame: frame)
        overrideUserInterfaceStyle = .dark
        isMultipleTouchEnabled = true
        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        backdrop.isHidden = true
        backdrop.addAction(UIAction { [weak self] _ in self?.showPalette(false) }, for: .touchUpInside)
        addSubview(backdrop)
        stick.onMovement = { [weak self] in self?.onMovement?($0) }
        addSubview(stick)
        styleSurface(toolbar, radius: 26)
        addSubview(toolbar)
        mode.selectedSegmentIndex = 0
        mode.selectedSegmentTintColor = UIColor.white.withAlphaComponent(0.18)
        mode.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 13, weight: .semibold)], for: .normal)
        mode.accessibilityLabel = "Touch mode"
        mode.accessibilityHint = "Menus uses direct touch. Play uses a movement pad and drag-to-aim controls."
        mode.addAction(UIAction { [weak self] _ in self?.setPrecision(self?.mode.selectedSegmentIndex == 1) }, for: .valueChanged)
        toolbar.contentView.addSubview(mode)
        utilityButtons = [
            utility("hand.tap", label: "Hide touch controls") { [weak self] in self?.onHide?() },
            utility("keyboard", label: "Show keyboard") { [weak self] in self?.onAction?(.keyboard, true) },
            utility("questionmark.circle", label: "Control guide") { [weak self] in self?.onHelp?() }
        ]
        utilityButtons.forEach { toolbar.contentView.addSubview($0) }
        modifierLabel.textColor = touchAmber
        modifierLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        modifierLabel.textAlignment = .center
        modifierLabel.isHidden = true
        addSubview(modifierLabel)
        for action in FactorioTouchAction.primary {
            let button = actionButton(action)
            buttons[action] = button
            addSubview(button)
        }
        for action in [FactorioTouchAction.inventory, .more, .back] {
            let button = actionButton(action)
            menuButtons.append(button)
            addSubview(button)
        }
        styleSurface(palette, radius: 24)
        palette.isHidden = true
        addSubview(palette)
        groups.selectedSegmentIndex = 0
        groups.selectedSegmentTintColor = UIColor.white.withAlphaComponent(0.16)
        groups.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 13, weight: .semibold)], for: .normal)
        groups.accessibilityLabel = "Tool group"
        groups.addAction(UIAction { [weak self] _ in self?.updatePalette() }, for: .valueChanged)
        palette.contentView.addSubview(groups)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.accessibilityLabel = "Close tools"
        closeButton.addAction(UIAction { [weak self] _ in self?.showPalette(false) }, for: .touchUpInside)
        palette.contentView.addSubview(closeButton)
        for action in Set(FactorioTouchAction.groups.flatMap { $0 }) {
            let button = actionButton(action)
            paletteButtons[action] = button
            palette.contentView.addSubview(button)
        }
        updatePalette()
        updateMode()
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
        backdrop.frame = bounds
        stick.frame = layout.stick
        toolbar.frame = layout.toolbar
        utilityButtons[0].frame = CGRect(x: 4, y: 4, width: 44, height: 44)
        mode.frame = CGRect(x: 52, y: 4, width: toolbar.bounds.width - 152, height: 44)
        utilityButtons[1].frame = CGRect(x: toolbar.bounds.width - 96, y: 4, width: 44, height: 44)
        utilityButtons[2].frame = CGRect(x: toolbar.bounds.width - 48, y: 4, width: 44, height: 44)
        modifierLabel.frame = CGRect(x: layout.toolbar.minX, y: layout.toolbar.maxY + 4,
            width: layout.toolbar.width, height: 20)
        for (action, frame) in zip(FactorioTouchAction.primary, layout.actions) { buttons[action]?.frame = frame }
        for (button, frame) in zip(menuButtons, layout.menuActions) { button.frame = frame }
        palette.frame = layout.panel
        groups.frame = CGRect(x: 12, y: 12, width: palette.bounds.width - 72, height: 36)
        closeButton.frame = CGRect(x: palette.bounds.width - 52, y: 8, width: 44, height: 44)
        let radius = min(70, (palette.bounds.height - 112) / 2)
        let center = CGPoint(x: palette.bounds.midX, y: palette.bounds.height / 2 + 20)
        for (index, action) in FactorioTouchAction.groups[groups.selectedSegmentIndex].enumerated() {
            let angle = CGFloat(index) * .pi / 3 - .pi / 2
            paletteButtons[action]?.frame = CGRect(x: center.x + cos(angle) * radius - 28,
                y: center.y + sin(angle) * radius - 28, width: 56, height: 56)
        }
    }

    func setSelected(_ action: FactorioTouchAction, _ selected: Bool) {
        buttons[action]?.active = selected
        paletteButtons[action]?.active = selected
        for button in menuButtons where button.action == action { button.active = selected }
        if action == .shift || action == .control {
            modifierLabel.text = [FactorioTouchAction.shift, .control].filter { paletteButtons[$0]?.active == true }
                .map(\.title).joined(separator: " + ")
            modifierLabel.isHidden = modifierLabel.text?.isEmpty != false || !palette.isHidden
        }
    }

    func releaseHeldActions() {
        for action in Array(heldActions) { release(action) }
        stick.reset()
    }

    func reset() {
        releaseHeldActions()
        showPalette(false)
        for action in [FactorioTouchAction.shift, .control, .more] { setSelected(action, false) }
    }

    private func setPrecision(_ enabled: Bool) {
        releaseHeldActions()
        precision = enabled
        mode.selectedSegmentIndex = enabled ? 1 : 0
        showPalette(false)
        updateMode()
        onModeChange?()
        feedback.selectionChanged()
    }

    private func updateMode() {
        let toolsOpen = !palette.isHidden
        stick.isHidden = !precision || toolsOpen
        buttons.values.forEach { $0.isHidden = !precision || toolsOpen }
        menuButtons.forEach { $0.isHidden = precision || toolsOpen }
        toolbar.isHidden = toolsOpen
        modifierLabel.isHidden = modifierLabel.text?.isEmpty != false || toolsOpen
    }

    private func showPalette(_ visible: Bool) {
        if visible { releaseHeldActions(); onAction?(.more, true) }
        else {
            for action in Array(heldActions) where FactorioTouchAction.groups.flatMap({ $0 }).contains(action) { release(action) }
        }
        palette.isHidden = !visible
        backdrop.isHidden = !visible
        setSelected(.more, visible)
        palette.accessibilityViewIsModal = visible
        updateMode()
        if visible { UIAccessibility.post(notification: .layoutChanged, argument: groups) }
    }

    private func updatePalette() {
        let visible = Set(FactorioTouchAction.groups[groups.selectedSegmentIndex])
        for action in Array(heldActions) { release(action) }
        for (action, button) in paletteButtons { button.isHidden = !visible.contains(action) }
        setNeedsLayout()
    }

    private func actionButton(_ action: FactorioTouchAction) -> FactorioTouchActionButton {
        let button = FactorioTouchActionButton(action: action)
        button.accessibilityHint = action.held ? "Hold to act. Release to stop." : "Uses the default Factorio binding."
        if [.build, .mine, .shoot].contains(action) {
            button.onDrag = { [weak self] delta in
                guard let self, self.heldActions.contains(action) else { return }
                self.onAim?(delta)
            }
            button.accessibilityHint = "Hold to act. Drag to aim while holding. Release to stop."
        }
        if action.held {
            button.addAction(UIAction { [weak self] _ in self?.press(action) }, for: .touchDown)
            button.addAction(UIAction { [weak self] _ in self?.release(action) }, for: [.touchUpInside, .touchUpOutside, .touchCancel])
            button.onAccessibilityActivate = { [weak self] in self?.press(action); self?.release(action) }
            button.accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: "Hold \(action.title)") { [weak self] _ in self?.press(action); return true },
                UIAccessibilityCustomAction(name: "Stop \(action.title)") { [weak self] _ in self?.release(action); return true }
            ]
        } else {
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.feedback.selectionChanged()
                if action == .more { self.showPalette(self.palette.isHidden) }
                else {
                    self.onAction?(action, true)
                    if [.inventory, .map, .research, .blueprints, .back].contains(action) { self.setPrecision(false) }
                    else if ![.shift, .control, .zoomIn, .zoomOut].contains(action) { self.showPalette(false) }
                }
            }, for: .touchUpInside)
        }
        return button
    }

    private func press(_ action: FactorioTouchAction) {
        guard heldActions.insert(action).inserted else { return }
        setSelected(action, true)
        feedback.selectionChanged()
        onAction?(action, true)
    }

    private func release(_ action: FactorioTouchAction) {
        guard heldActions.remove(action) != nil else { return }
        setSelected(action, false)
        onAction?(action, false)
    }

    private func utility(_ symbol: String, label: String, action: @escaping () -> Void) -> UIButton {
        let button = FactorioTouchOnlyButton(type: .system)
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)), for: .normal)
        button.tintColor = .white
        button.accessibilityLabel = label
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func styleSurface(_ view: UIView, radius: CGFloat) {
        view.layer.cornerRadius = radius
        view.clipsToBounds = true
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.white.withAlphaComponent(0.13).cgColor
    }
}

private final class FactorioTouchActionButton: UIButton {
    override var canBecomeFocused: Bool { false }
    var onAccessibilityActivate: (() -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var active = false { didSet { updateAppearance() } }
    override var isHighlighted: Bool { didSet { updateAppearance() } }
    private let glyph = UIImageView()
    private let caption = UILabel()
    let action: FactorioTouchAction
    private var lastPoint: CGPoint?

    init(action: FactorioTouchAction) {
        self.action = action
        super.init(frame: .zero)
        isExclusiveTouch = false
        accessibilityLabel = action.title
        accessibilityIdentifier = "touch-" + action.rawValue
        glyph.image = UIImage(systemName: action.symbol)
        glyph.contentMode = .scaleAspectFit
        glyph.isUserInteractionEnabled = false
        addSubview(glyph)
        caption.text = action.caption
        caption.textAlignment = .center
        caption.font = .systemFont(ofSize: 11, weight: .semibold)
        caption.textColor = .white
        addSubview(caption)
        layer.borderWidth = 1
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 2)
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        let large = action == .build
        let small = bounds.height < 50
        glyph.frame = CGRect(x: 10, y: large ? 9 : (small ? 4 : 7), width: bounds.width - 20,
            height: large ? (bounds.height >= 68 ? 27 : 23) : (small ? 17 : 21))
        caption.frame = CGRect(x: 2, y: bounds.height - 22, width: bounds.width - 4, height: 16)
    }

    override func accessibilityActivate() -> Bool {
        if let onAccessibilityActivate { onAccessibilityActivate(); return true }
        sendActions(for: .touchUpInside)
        return true
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        lastPoint = touch.location(in: superview)
        return super.beginTracking(touch, with: event)
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let point = touch.location(in: superview)
        if let lastPoint, onDrag != nil { onDrag?(CGPoint(x: point.x - lastPoint.x, y: point.y - lastPoint.y)) }
        lastPoint = point
        // A held building gesture must keep tracking after it leaves the button.
        if onDrag != nil { return true }
        return super.continueTracking(touch, with: event)
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        lastPoint = nil
        super.endTracking(touch, with: event)
    }

    override func cancelTracking(with event: UIEvent?) {
        lastPoint = nil
        super.cancelTracking(with: event)
    }

    private func updateAppearance() {
        let pressed = active || isHighlighted
        let primary = action == .build
        backgroundColor = pressed ? touchAmber.withAlphaComponent(0.95) : touchSurface
        glyph.tintColor = pressed ? .black : (primary ? touchAmber : .white)
        caption.textColor = pressed ? .black : .white
        layer.borderColor = (pressed || primary ? touchAmber : UIColor.white.withAlphaComponent(0.22)).cgColor
        layer.borderWidth = primary ? 2 : 1
        accessibilityTraits = active ? [.button, .selected] : [.button]
    }
}

private final class FactorioTouchStickView: UIView {
    var onMovement: ((Set<Int32>) -> Void)?
    private let base = UIView()
    private let knob = UIView()
    private let caption = UILabel()
    private var activeTouch: UITouch?
    private var origin = CGPoint.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        base.isUserInteractionEnabled = false
        base.backgroundColor = UIColor.black.withAlphaComponent(0.20)
        base.layer.borderWidth = 1.5
        base.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        addSubview(base)
        knob.isUserInteractionEnabled = false
        knob.backgroundColor = UIColor.white.withAlphaComponent(0.28)
        knob.layer.borderWidth = 1
        knob.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        base.addSubview(knob)
        caption.text = "MOVE"
        caption.font = .systemFont(ofSize: 11, weight: .semibold)
        caption.textColor = UIColor.white.withAlphaComponent(0.75)
        caption.textAlignment = .center
        knob.addSubview(caption)
        isAccessibilityElement = true
        accessibilityLabel = "Movement pad"
        accessibilityHint = "Drag from anywhere on the pad. Release to stop."
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
        base.bounds.size = CGSize(width: bounds.width - 20, height: bounds.height - 20)
        base.layer.cornerRadius = base.bounds.width / 2
        knob.bounds.size = CGSize(width: 44, height: 44)
        knob.layer.cornerRadius = 22
        caption.frame = knob.bounds
        if activeTouch == nil { reset() }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        origin = touch.location(in: self)
        let radius = base.bounds.width / 2
        base.center = CGPoint(x: min(max(origin.x, radius), bounds.maxX - radius),
            y: min(max(origin.y, radius), bounds.maxY - radius))
        base.layer.borderColor = touchAmber.cgColor
        knob.backgroundColor = touchAmber.withAlphaComponent(0.8)
        caption.isHidden = true
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
        base.center = CGPoint(x: bounds.midX, y: bounds.midY)
        base.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        knob.backgroundColor = UIColor.white.withAlphaComponent(0.28)
        knob.center = CGPoint(x: base.bounds.midX, y: base.bounds.midY)
        caption.isHidden = false
        onMovement?([])
    }

    private func update(_ touch: UITouch) {
        let point = touch.location(in: self)
        let delta = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        let radius = base.bounds.width / 2
        let distance = max(1, hypot(delta.x, delta.y))
        let scale = min(1, (radius - knob.bounds.width / 2) / distance)
        knob.center = CGPoint(x: base.bounds.midX + delta.x * scale, y: base.bounds.midY + delta.y * scale)
        onMovement?(FactorioTouchLayout.movement(at: delta, radius: radius))
    }
}
#endif
