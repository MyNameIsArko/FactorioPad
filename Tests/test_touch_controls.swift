import Foundation
import CoreGraphics

@main struct TouchControlTests {
    static func main() {
        let sizes = [
            CGRect(x: 0, y: 0, width: 568, height: 320),
            CGRect(x: 47, y: 0, width: 750, height: 369),
            CGRect(x: 59, y: 0, width: 814, height: 381),
            CGRect(x: 0, y: 24, width: 1194, height: 790),
            CGRect(x: 0, y: 24, width: 1366, height: 980),
            CGRect(x: 0, y: 0, width: 375, height: 281)
        ]
        for safe in sizes {
            let layout = FactorioTouchLayout(safeBounds: safe)
            let frames = [layout.stick, layout.mode, layout.shoot] + layout.actions
            assert(frames.allSatisfy { safe.contains($0) }, "Controls must stay inside the safe area: \(safe)")
            assert(layout.actions.allSatisfy { $0.width >= 44 && $0.height >= 44 })
            assert(layout.panel.width >= 112 && safe.contains(layout.panel))
            for (index, frame) in frames.enumerated() {
                assert(frames.dropFirst(index + 1).allSatisfy { !frame.intersects($0) }, "Controls must not overlap")
            }
            assert(layout.actions.allSatisfy { !layout.panel.intersects($0) }, "More must leave the action buttons reachable")
        }
        let movement = FactorioTouchLayout.movement
        assert(movement(.zero, 56).isEmpty)
        assert(movement(CGPoint(x: 8, y: 0), 56).isEmpty)
        assert(movement(CGPoint(x: 56, y: 0), 56) == [7])
        assert(movement(CGPoint(x: -56, y: 0), 56) == [4])
        assert(movement(CGPoint(x: 0, y: -56), 56) == [26])
        assert(movement(CGPoint(x: 0, y: 56), 56) == [22])
        assert(movement(CGPoint(x: 56, y: -56), 56) == [7, 26])
        assert(movement(CGPoint(x: 56, y: 0), 0).isEmpty)
        assert(Set(FactorioTouchAction.primary + FactorioTouchAction.secondary + [.shoot]) == Set(FactorioTouchAction.allCases))
        assert(FactorioTouchAction.copy.key?.modifiers == 0x0040)
        assert(FactorioTouchAction.deconstruct.key?.modifiers == 0x0100)
        print("Factorio touch layout, movement, and shortcut tests passed.")
    }
}
