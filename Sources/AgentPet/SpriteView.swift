import AppKit
import PetCore
import SwiftUI

/// Plays one mood row on a Core Animation layer. The frame cuts and the whole-figure motion are
/// animations owned by the render server, so SwiftUI and the main thread do nothing per frame.
struct SpriteView: NSViewRepresentable {
    let agent: String
    let mood: Mood

    func makeNSView(context: Context) -> SpriteNSView {
        SpriteNSView()
    }

    func updateNSView(_ view: SpriteNSView, context: Context) {
        view.show(agent: agent, mood: mood)
    }

    @MainActor
    final class SpriteNSView: NSView {
        private let spriteLayer = CALayer()
        private var desired: (agent: String, mood: Mood)?
        private var playing = false

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            spriteLayer.anchorPoint = CGPoint(x: 0.5, y: 0)
            spriteLayer.contentsGravity = .resize
            layer?.addSublayer(spriteLayer)
        }

        required init?(coder: NSCoder) {
            return nil
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            spriteLayer.bounds = CGRect(origin: .zero, size: bounds.size)
            spriteLayer.position = CGPoint(x: bounds.midX, y: bounds.minY)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            spriteLayer.contentsScale = window?.backingScaleFactor ?? 1
            if window == nil {
                spriteLayer.removeAllAnimations()
                playing = false
            } else if let desired {
                play(agent: desired.agent, mood: desired.mood)
            }
        }

        func show(agent: String, mood: Mood) {
            let changed = desired?.agent != agent || desired?.mood != mood
            desired = (agent, mood)
            guard window != nil, changed || !playing else { return }
            play(agent: agent, mood: mood)
        }

        private func play(agent: String, mood: Mood) {
            playing = true
            spriteLayer.removeAllAnimations()
            let frames = SpriteLibrary.shared.frames(agent: agent, mood: mood)
            guard !frames.isEmpty else {
                spriteLayer.contents = nil
                return
            }
            spriteLayer.contents = frames[0]
            spriteLayer.add(frameAnimation(frames: frames, mood: mood), forKey: "frames")
            if let motion = motionAnimation(for: mood) {
                spriteLayer.add(motion, forKey: "motion")
            }
        }

        private func frameAnimation(frames: [CGImage], mood: Mood) -> CAKeyframeAnimation {
            let order = SpriteTiming.sequence(for: mood, frameCount: frames.count)
            let animation = CAKeyframeAnimation(keyPath: "contents")
            animation.values = order.map { frames[$0] }
            animation.keyTimes = order.indices.map { NSNumber(value: Double($0) / Double(order.count)) }
            animation.calculationMode = .discrete
            animation.duration = SpriteTiming.cycleDuration(for: mood, frameCount: frames.count)
            animation.repeatCount = .infinity
            return animation
        }

        private func motionAnimation(for mood: Mood) -> CABasicAnimation? {
            let animation: CABasicAnimation
            switch SpriteTiming.motion(for: mood) {
            case .still:
                return nil
            case let .breathing(scale, period):
                animation = CABasicAnimation(keyPath: "transform.scale")
                animation.fromValue = 1
                animation.toValue = 1 + scale
                animation.duration = period / 2
            case let .bob(amplitude, period):
                animation = CABasicAnimation(keyPath: "transform.translation.y")
                animation.fromValue = -amplitude
                animation.toValue = amplitude
                animation.duration = period / 2
            }
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            return animation
        }
    }
}
