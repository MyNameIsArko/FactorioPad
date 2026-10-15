import UIKit

// The keyboard bridge is outside this native interface test.
func FactorioKeyboardInsertText(_ text: String) {}
func FactorioKeyboardBackspace() {}
func FactorioKeyboardReturn() {}
func FactorioKeyboardTab() {}

private final class TestTouch: UITouch {
    var point = CGPoint.zero
    override func location(in view: UIView?) -> CGPoint { point }
}

private func descendants(_ view: UIView) -> [UIView] {
    view.subviews.flatMap { [$0] + descendants($0) }
}

private func visible(_ view: UIView) -> Bool {
    !view.isHidden && (view.superview.map(visible) ?? true)
}

private func testControls(_ controls: FactorioTouchControlsView) {
    let all = descendants(controls)
    for button in all where button.accessibilityIdentifier?.hasPrefix("touch-") == true {
        assert(button.subviews.compactMap { $0 as? UIImageView }.contains { $0.image != nil },
            "Missing action symbol: \(button.accessibilityIdentifier!)")
    }
    let mode = all.compactMap { $0 as? UISegmentedControl }.first { $0.accessibilityLabel == "Touch mode" }!
    let groups = all.compactMap { $0 as? UISegmentedControl }.first { $0.accessibilityLabel == "Tool group" }!
    let compactMode = all.compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == "Touch mode: Menus" }!
    let barToggle = all.compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == "Expand control bar" }!
    func button(_ action: FactorioTouchAction) -> UIButton {
        all.compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "touch-" + action.rawValue && visible($0) }!
    }
    var actions: [(FactorioTouchAction, Bool)] = []
    var aim: [CGPoint] = []
    var movement: [Set<Int32>] = []
    controls.onAction = { action, pressed in
        actions.append((action, pressed))
    }
    controls.onAim = { aim.append($0) }
    controls.onMovement = { movement.append($0) }
    assert(!controls.precision && !visible(all.first { $0.accessibilityIdentifier == "touch-build" }!))
    assert(!visible(mode), "The top bar must start collapsed")
    compactMode.sendActions(for: .touchUpInside)
    assert(controls.precision, "The compact mode button must switch modes in one tap")
    barToggle.sendActions(for: .touchUpInside)
    assert(visible(mode) && barToggle.accessibilityLabel == "Collapse control bar")
    barToggle.sendActions(for: .touchUpInside)
    assert(!visible(mode) && controls.precision, "Collapsing the bar must keep gameplay controls active")
    controls.layoutIfNeeded()
    let pad = all.first { $0.accessibilityLabel == "Movement pad" }!
    let padTouch = TestTouch()
    pad.touchesBegan([padTouch], with: nil)
    assert(pad.subviews.allSatisfy { pad.bounds.contains($0.frame) }, "The floating pad must stay away from the screen edge")
    padTouch.point = CGPoint(x: 60, y: 0)
    pad.touchesMoved([padTouch], with: nil)
    assert(movement.last == [7])
    pad.touchesCancelled([padTouch], with: nil)
    assert(movement.last!.isEmpty)
    let build = button(.build)
    let touch = TestTouch()
    _ = build.beginTracking(touch, with: nil)
    build.sendActions(for: .touchDown)
    touch.point = CGPoint(x: 300, y: 25)
    assert(build.continueTracking(touch, with: nil), "Building must keep tracking outside its button")
    assert(aim == [touch.point] && actions.last!.0 == .build && actions.last!.1)
    build.sendActions(for: .touchCancel)
    let count = aim.count
    touch.point.x += 20
    _ = build.continueTracking(touch, with: nil)
    assert(aim.count == count && !actions.last!.1, "Cancellation must stop both aiming and the held action")
    let releasedCount = actions.count
    build.sendActions(for: .touchUpInside)
    assert(actions.count == releasedCount, "A stale release must not start a new action")
    assert(build.accessibilityActivate())
    assert(actions.suffix(2).map(\.1) == [true, false])
    build.sendActions(for: .touchDown)
    button(.more).sendActions(for: .touchUpInside)
    let openingTools = actions.suffix(2)
    assert(openingTools.first!.0 == .build && !openingTools.first!.1 && openingTools.last!.0 == .more && !visible(build))
    assert(visible(groups) && all.filter { $0.accessibilityIdentifier?.hasPrefix("touch-") == true && visible($0) }.count == 6)
    if !pad.frame.intersects(groups.superview!.superview!.frame) { assert(visible(pad)) }
    groups.selectedSegmentIndex = 1
    groups.sendActions(for: .valueChanged)
    controls.layoutIfNeeded()
    button(.transferStack).sendActions(for: .touchUpInside)
    assert(!controls.precision && !visible(groups) && controls.targetAction == .transferStack)
    assert(compactMode.currentTitle == "Move stack\nTap item" && compactMode.accessibilityLabel == "Cancel Move stack")
    controls.clearTargetAction()
    assert(controls.targetAction == nil && compactMode.currentTitle == "Menus")
    button(.more).sendActions(for: .touchUpInside)
    button(.transferAll).sendActions(for: .touchUpInside)
    assert(controls.targetAction == .transferAll)
    compactMode.sendActions(for: .touchUpInside)
    assert(controls.targetAction == nil && !controls.precision, "Cancel must clear the target without switching modes")
    button(.inventory).sendActions(for: .touchUpInside)
    assert(!controls.precision && !visible(build), "Items must preserve Menus mode")
    mode.selectedSegmentIndex = 1
    mode.sendActions(for: .valueChanged)
    for _ in 0..<2 {
        button(.inventory).sendActions(for: .touchUpInside)
        assert(controls.precision && visible(build) && !visible(mode), "Opening or closing Items must preserve Play mode and the collapsed bar")
        assert(actions.last!.0 == .inventory && actions.last!.1)
    }
    build.sendActions(for: .touchDown)
    controls.reset()
    assert(actions.last!.0 == .build && !actions.last!.1)
    button(.more).sendActions(for: .touchUpInside)
    button(.transferAll).sendActions(for: .touchUpInside)
    controls.reset()
    assert(controls.targetAction == nil && !visible(mode), "Suspension must clear pending actions and keep the bar collapsed")
    controls.onAction = nil
    controls.onAim = nil
    controls.onMovement = nil
}

private final class PreviewController: UIViewController {
    let controls = FactorioTouchControlsView()
    let canvas = UIView()
    private var tested = false
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        canvas.backgroundColor = UIColor(red: 0.16, green: 0.20, blue: 0.18, alpha: 1)
        view.addSubview(canvas)
        canvas.addSubview(controls)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let height = min(view.bounds.height, view.bounds.width * 0.75)
        canvas.frame = CGRect(x: 0, y: (view.bounds.height - height) / 2, width: view.bounds.width, height: height)
        controls.frame = canvas.bounds
        controls.layoutIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !tested else { return }
        tested = true
        UIView.setAnimationsEnabled(false)
        testControls(controls)
        let all = descendants(controls)
        let mode = all.compactMap { $0 as? UISegmentedControl }.first { $0.accessibilityLabel == "Touch mode" }!
        mode.selectedSegmentIndex = CommandLine.arguments.contains("--menus") ? 0 : 1
        mode.sendActions(for: .valueChanged)
        let groups = all.compactMap { $0 as? UISegmentedControl }.first { $0.accessibilityLabel == "Tool group" }!
        groups.selectedSegmentIndex = CommandLine.arguments.contains("--items") ? 1 : 0
        groups.sendActions(for: .valueChanged)
        if CommandLine.arguments.contains("--tools") {
            all.compactMap { $0 as? UIButton }.first {
                $0.accessibilityIdentifier == "touch-more" && visible($0)
            }!.sendActions(for: .touchUpInside)
        }
        controls.layoutIfNeeded()
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let image = UIGraphicsImageRenderer(bounds: canvas.bounds).image { _ in
            canvas.drawHierarchy(in: canvas.bounds, afterScreenUpdates: true)
        }
        try! image.pngData()!.write(to: folder.appendingPathComponent("touch-ui-preview.png"))
        let result = folder.appendingPathComponent("touch-ui-passed.txt")
        try! "Native touch interface tests passed.\n".write(to: result, atomically: true, encoding: .utf8)
    }
}

private final class TestSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = PreviewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}

@main private final class TestAppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ app: UIApplication, configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = TestSceneDelegate.self
        return configuration
    }
}
