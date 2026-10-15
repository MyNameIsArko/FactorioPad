import Foundation
import CoreGraphics

enum FactorioTouchAction: String, CaseIterable {
    case build, mine, rotate, pick, inventory, more
    case transferStack, transferAll, shoot, pickup, map, research, alt, vehicle
    case copy, paste, undo, blueprints, deconstruct, upgrade, zoomIn, zoomOut, back, keyboard
    case guide, hideControls

    static let primary: [Self] = [.build, .mine, .rotate, .pick, .inventory, .shoot, .more]
    static let groups: [[Self]] = [
        [.copy, .paste, .undo, .blueprints, .deconstruct, .upgrade],
        [.transferStack, .transferAll, .pickup, .inventory, .back],
        [.map, .research, .alt, .vehicle, .zoomIn, .zoomOut],
        [.keyboard, .guide, .hideControls]
    ]

    var title: String {
        switch self {
        case .build: return "Build / open"
        case .mine: return "Mine"
        case .rotate: return "Rotate"
        case .pick: return "Pick / clear"
        case .inventory: return "Inventory"
        case .more: return "More"
        case .transferStack: return "Move stack"
        case .transferAll: return "Move all"
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
        case .guide: return "Control guide"
        case .hideControls: return "Hide touch controls"
        }
    }

    var held: Bool { [.build, .mine, .shoot, .pickup].contains(self) }

    var targetModifiers: UInt16? {
        switch self {
        case .transferStack: return 0x0001
        case .transferAll: return 0x0040
        default: return nil
        }
    }

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
    let modeSwitch: CGRect
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
        modeSwitch = CGRect(x: stick.midX - 44, y: stick.minY - 52, width: 88, height: 44)
        panel = CGRect(x: safeBounds.maxX - edgeInset - 272,
            y: safeBounds.maxY - bottom - 184, width: 272, height: 184)
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
        case .transferStack: return "arrow.right.square"
        case .transferAll: return "arrow.right.square.fill"
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
        case .guide: return "questionmark.circle"
        case .hideControls: return "hand.tap"
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
        case .guide: return "Guide"
        case .hideControls: return "Hide"
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
    private(set) var targetAction: FactorioTouchAction?
    private let stick = FactorioTouchStickView()
    private let modeButton = FactorioTouchOnlyButton(type: .system)
    private let palette = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    private let groups = FactorioTouchSegments(items: ["Build", "Items", "World", "App"])
    private let closeButton = FactorioTouchOnlyButton(type: .custom)
    private let backdrop = UIControl()
    private var buttons: [FactorioTouchAction: FactorioTouchActionButton] = [:]
    private var paletteButtons: [FactorioTouchAction: FactorioTouchActionButton] = [:]
    private var menuButtons: [FactorioTouchActionButton] = []
    private var heldActions = Set<FactorioTouchAction>()
    private let feedback = UISelectionFeedbackGenerator()

    override init(frame: CGRect) {
        super.init(frame: frame)
        overrideUserInterfaceStyle = .dark
        isMultipleTouchEnabled = true
        backdrop.isHidden = true
        backdrop.addAction(UIAction { [weak self] _ in self?.showPalette(false) }, for: .touchUpInside)
        addSubview(backdrop)
        stick.onMovement = { [weak self] in self?.onMovement?($0) }
        addSubview(stick)
        styleSurface(modeButton, radius: 22)
        modeButton.backgroundColor = touchSurface
        addSubview(modeButton)
        modeButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        modeButton.tintColor = .white
        modeButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if self.targetAction != nil { self.onModeChange?(); self.clearTargetAction() }
            else { self.setPrecision(!self.precision) }
        }, for: .touchUpInside)
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
        styleSurface(palette, radius: 18)
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
            button.compact = true
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
        modeButton.frame = layout.modeSwitch
        for (action, frame) in zip(FactorioTouchAction.primary, layout.actions) { buttons[action]?.frame = frame }
        for (button, frame) in zip(menuButtons, layout.menuActions) { button.frame = frame }
        palette.frame = layout.panel
        if FactorioTouchAction.groups[groups.selectedSegmentIndex].count <= 3 {
            palette.frame = CGRect(x: layout.panel.minX, y: layout.panel.maxY - 128,
                width: layout.panel.width, height: 128)
        }
        groups.frame = CGRect(x: 8, y: 8, width: palette.bounds.width - 60, height: 44)
        closeButton.frame = CGRect(x: palette.bounds.width - 48, y: 8, width: 44, height: 44)
        let column = (palette.bounds.width - 16) / 3
        for (index, action) in FactorioTouchAction.groups[groups.selectedSegmentIndex].enumerated() {
            paletteButtons[action]?.frame = CGRect(x: 8 + CGFloat(index % 3) * column,
                y: 64 + CGFloat(index / 3) * 56, width: column - 4, height: 52)
        }
        updateMode()
    }

    func setSelected(_ action: FactorioTouchAction, _ selected: Bool) {
        buttons[action]?.active = selected
        paletteButtons[action]?.active = selected
        for button in menuButtons where button.action == action { button.active = selected }
    }

    func clearTargetAction() {
        if let targetAction { setSelected(targetAction, false) }
        targetAction = nil
        updateMode()
    }

    func releaseHeldActions() {
        for action in Array(heldActions) { release(action) }
        stick.reset()
    }

    func reset() {
        releaseHeldActions()
        showPalette(false)
        clearTargetAction()
        setSelected(.more, false)
    }

    private func setPrecision(_ enabled: Bool) {
        releaseHeldActions()
        clearTargetAction()
        precision = enabled
        showPalette(false)
        updateMode()
        onModeChange?()
        feedback.selectionChanged()
    }

    private func updateMode() {
        let toolsOpen = !palette.isHidden
        stick.isHidden = !precision || (toolsOpen && stick.frame.intersects(palette.frame))
        buttons.values.forEach { $0.isHidden = !precision || toolsOpen }
        menuButtons.forEach { $0.isHidden = precision || toolsOpen }
        modeButton.isHidden = toolsOpen
        modeButton.titleLabel?.numberOfLines = targetAction == nil ? 1 : 2
        modeButton.titleLabel?.textAlignment = .center
        modeButton.setTitle(targetAction.map { "\($0.title)\nTap item" } ?? (precision ? "Play" : "Menus"), for: .normal)
        modeButton.accessibilityLabel = targetAction.map { "Cancel \($0.title)" } ?? "Touch mode: \(precision ? "Play" : "Menus")"
        modeButton.accessibilityHint = targetAction != nil ? "Tap an item to transfer it once, or tap here to cancel." : "Tap to switch between Menus and Play."
        modeButton.tintColor = targetAction != nil ? touchAmber : .white
    }

    private func showPalette(_ visible: Bool) {
        if visible { releaseHeldActions(); clearTargetAction(); onAction?(.more, true) }
        else {
            for action in Array(heldActions) where FactorioTouchAction.groups.flatMap({ $0 }).contains(action) { release(action) }
        }
        palette.isHidden = !visible
        backdrop.isHidden = !visible
        setSelected(.more, visible)
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
        if action == .keyboard { button.accessibilityHint = "Open the on-screen keyboard." }
        if action == .guide { button.accessibilityHint = "Show the touch and controller guide." }
        if action == .hideControls { button.accessibilityHint = "Show them again using the hand button near your left thumb." }
        if action.targetModifiers != nil {
            button.accessibilityHint = action == .transferStack ? "Then tap a stack to move it to the other inventory." : "Then tap an item to move all items of its type. An empty slot moves all items."
        }
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
                    if action.targetModifiers != nil {
                        self.setPrecision(false)
                        self.targetAction = action
                        self.setSelected(action, true)
                        self.updateMode()
                        UIAccessibility.post(notification: .announcement, argument: "\(action.title). Tap an item. Tap the mode button to cancel.")
                    } else if [.map, .research, .blueprints, .back].contains(action) { self.setPrecision(false) }
                    else if ![.zoomIn, .zoomOut].contains(action) { self.showPalette(false) }
                    if action == .guide { self.onHelp?() }
                    if action == .hideControls { self.onHide?() }
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
    var compact = false
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
        layer.cornerRadius = compact ? 12 : bounds.width / 2
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
