struct FactorioKeyboardLayout {
    enum Page { case letters, numbers, symbols }
    enum Shift { case off, once, locked }
    static let letterRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    static let numberRows = ["1234567890", "-/:;()$&@\"", ".,?!'"]
    static let symbolRows = ["[]{}#%^*+=", "_\\|~<>€£¥`", ".,?!'"]
    private(set) var page = Page.letters
    private(set) var shift = Shift.off
    private var lastShiftTap: Double?

    var rows: [String] {
        switch page {
        case .letters: return Self.letterRows.map { shift == .off ? $0 : $0.uppercased() }
        case .numbers: return Self.numberRows
        case .symbols: return Self.symbolRows
        }
    }

    mutating func tapShift(at time: Double) {
        if let lastShiftTap, time >= lastShiftTap, time - lastShiftTap < 0.35 {
            shift = .locked
            self.lastShiftTap = nil
        } else {
            shift = shift == .off ? .once : .off
            lastShiftTap = time
        }
    }

    mutating func toggleCapsLock() {
        shift = shift == .locked ? .off : .locked
        lastShiftTap = nil
    }

    mutating func show(_ page: Page) {
        self.page = page
        if shift == .once { shift = .off }
        lastShiftTap = nil
    }

    mutating func insert(_ text: String) -> String {
        let result = page == .letters ? (shift == .off ? text.lowercased() : text.uppercased()) : text
        if shift == .once { shift = .off }
        if text == " " { page = .letters }
        lastShiftTap = nil
        return result
    }

    mutating func reset() { self = Self() }
}

#if canImport(UIKit)
import UIKit

final class FactorioTouchOnlyButton: UIButton {
    override var canBecomeFocused: Bool { false }
    var onAccessibilityActivate: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        guard let onAccessibilityActivate else { return super.accessibilityActivate() }
        onAccessibilityActivate()
        return true
    }
}

final class FactorioOnScreenKeyboardView: UIView {
    var onClose: (() -> Void)?
    private var layout = FactorioKeyboardLayout()
    private let rows = UIStackView()
    private var repeatTimer: Timer?

    override var isHidden: Bool {
        didSet { if isHidden { reset() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        overrideUserInterfaceStyle = .dark
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 10
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        clipsToBounds = true
        rows.axis = .vertical
        rows.spacing = 8
        rows.distribution = .fillEqually
        addSubview(rows)
        rebuildKeys()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { repeatTimer?.invalidate() }

    override func layoutSubviews() {
        super.layoutSubviews()
        rows.frame = bounds.inset(by: UIEdgeInsets(top: 12, left: max(8, safeAreaInsets.left),
            bottom: max(8, safeAreaInsets.bottom), right: max(8, safeAreaInsets.right)))
    }

    func reset() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        layout.reset()
        rebuildKeys()
    }

    private func rebuildKeys() {
        for row in rows.arrangedSubviews {
            rows.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        for (index, text) in layout.rows.enumerated() {
            var keys: [UIView] = text.map { character in
                let text = String(character)
                return button(text) { [weak self] in
                    self?.insertText(text)
                }
            }
            var weights = Array(repeating: CGFloat(1), count: keys.count)
            if index == 1 && layout.page == .letters {
                keys.insert(UIView(), at: 0)
                keys.append(UIView())
                weights = [0.5] + weights + [0.5]
            }
            if index == 2 {
                let pageKey: UIButton
                if layout.page == .letters {
                    pageKey = button("", label: layout.shift == .locked ? "Caps Lock" : "Shift", special: true) { [weak self] in
                        self?.layout.tapShift(at: CACurrentMediaTime())
                        self?.rebuildKeys()
                    }
                    let icon = layout.shift == .locked ? "capslock.fill" : (layout.shift == .once ? "shift.fill" : "shift")
                    pageKey.setImage(UIImage(systemName: icon), for: .normal)
                    pageKey.accessibilityTraits = layout.shift == .off ? [.button] : [.button, .selected]
                    pageKey.accessibilityCustomActions = [UIAccessibilityCustomAction(
                        name: "Toggle Caps Lock", target: self, selector: #selector(toggleCapsLock))]
                } else {
                    pageKey = button(layout.page == .numbers ? "#+=" : "123", special: true) { [weak self] in
                        guard let self else { return }
                        self.layout.show(self.layout.page == .numbers ? .symbols : .numbers)
                        self.rebuildKeys()
                    }
                    weights = Array(repeating: CGFloat(1.4), count: keys.count)
                }
                let backspace = button("", label: "Backspace", special: true) { FactorioKeyboardBackspace() }
                backspace.setImage(UIImage(systemName: "delete.left"), for: .normal)
                backspace.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(repeatBackspace)))
                keys.insert(pageKey, at: 0)
                keys.append(backspace)
                weights = [1.5] + weights + [1.5]
            }
            rows.addArrangedSubview(makeRow(keys, weights: weights))
        }
        let hide = button("", label: "Hide keyboard", special: true) { [weak self] in self?.onClose?() }
        hide.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        rows.addArrangedSubview(makeRow([
            button(layout.page == .letters ? "123" : "ABC", special: true) { [weak self] in
                guard let self else { return }
                self.layout.show(self.layout.page == .letters ? .numbers : .letters)
                self.rebuildKeys()
            },
            button("space") { [weak self] in
                self?.insertText(" ")
            },
            button("return", special: true) { [weak self] in
                FactorioKeyboardReturn()
                self?.onClose?()
            },
            hide
        ], weights: [1.2, 5.6, 2.2, 1]))
    }

    private func insertText(_ text: String) {
        let previousRows = layout.rows
        FactorioKeyboardTypeKey(layout.insert(text))
        if layout.rows != previousRows { rebuildKeys() }
    }

    private func button(_ title: String, label: String? = nil, special: Bool = false, action: @escaping () -> Void) -> UIButton {
        let key = FactorioTouchOnlyButton(type: .system)
        key.setTitle(title, for: .normal)
        key.accessibilityLabel = label ?? title
        key.setTitleColor(.white, for: .normal)
        key.tintColor = .white
        key.titleLabel?.font = .systemFont(ofSize: special || title.count > 1 ? 17 : 24)
        key.titleLabel?.adjustsFontSizeToFitWidth = true
        key.backgroundColor = special ? .systemGray5 : .systemGray3
        key.layer.cornerRadius = 5
        key.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return key
    }

    private func makeRow(_ keys: [UIView], weights: [CGFloat]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: keys)
        row.spacing = 6
        for index in keys.indices.dropFirst() {
            keys[index].widthAnchor.constraint(equalTo: keys[0].widthAnchor,
                multiplier: weights[index] / weights[0]).isActive = true
        }
        return row
    }

    @objc private func toggleCapsLock() -> Bool {
        layout.toggleCapsLock()
        rebuildKeys()
        return true
    }

    @objc private func repeatBackspace(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state != .changed else { return }
        repeatTimer?.invalidate()
        repeatTimer = nil
        guard gesture.state == .began else { return }
        FactorioKeyboardBackspace()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] timer in
            guard let self, !self.isHidden, self.window != nil else { timer.invalidate(); return }
            FactorioKeyboardBackspace()
        }
    }
}
#endif
