import SwiftUI

/// A short double bounce each time `trigger` changes.
struct HopEffect: ViewModifier {
    private static let riseDuration = 0.14
    private static let fallDuration = 0.14
    private static let reboundRatio: CGFloat = 0.4
    private static let reboundDuration = 0.1

    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { view, lift in
            view.offset(y: -lift)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(PopoverMetrics.hopHeight, duration: Self.riseDuration)
                CubicKeyframe(0, duration: Self.fallDuration)
                CubicKeyframe(PopoverMetrics.hopHeight * Self.reboundRatio, duration: Self.reboundDuration)
                CubicKeyframe(0, duration: Self.reboundDuration)
            }
        }
    }
}
