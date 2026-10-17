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
        private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            spriteLayer.anchorPoint = CGPoint(x: 0.5, y: 0)
            spriteLayer.contentsGravity = .resize
            layer?.addSublayer(spriteLayer)
            SpriteRegistry.shared.add(self)
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
            removeObservers()
            if window == nil {
                spriteLayer.removeAllAnimations()
            } else {
                observeEnvironment()
            }
            refresh()
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            refresh()
        }

        func show(agent: String, mood: Mood) {
            desired = (agent, mood)
            refresh()
        }

        /// Idempotent: follows the current screen's scale and reinstalls animations that are missing.
        func refresh() {
            guard let window else { return }
            spriteLayer.contentsScale = window.screen?.backingScaleFactor ?? window.backingScaleFactor
            guard let desired else { return }
            if spriteLayer.animation(forKey: Self.framesKey) == nil || playing != desired.agent + desired.mood.rawValue {
                play(agent: desired.agent, mood: desired.mood)
            }
        }

        private static let framesKey = "frames"
        private var playing = ""

        private func observeEnvironment() {
            guard let window else { return }
            let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            let names: [(NotificationCenter, NSNotification.Name, AnyObject?)] = [
                (.default, NSWindow.didChangeScreenNotification, window),
                (.default, NSWindow.didChangeBackingPropertiesNotification, window),
                (.default, NSWindow.didChangeOcclusionStateNotification, window),
                (.default, NSApplication.didChangeScreenParametersNotification, nil),
                (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification, nil),
                (NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification, nil),
            ]
            for (center, name, object) in names {
                observers.append((center, center.addObserver(forName: name, object: object, queue: .main, using: refresh)))
            }
        }

        private func removeObservers() {
            for observer in observers { observer.center.removeObserver(observer.token) }
            observers.removeAll()
        }

        private func play(agent: String, mood: Mood) {
            spriteLayer.removeAllAnimations()
            playing = agent + mood.rawValue
            let frames = SpriteLibrary.shared.frames(agent: agent, mood: mood)
            guard !frames.isEmpty else {
                spriteLayer.contents = nil
                return
            }
            spriteLayer.contents = frames[0]
            spriteLayer.add(frameAnimation(frames: frames, mood: mood), forKey: Self.framesKey)
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

/// Weak list of live sprite views, so a periodic check can reinstall animations the system dropped.
@MainActor
final class SpriteRegistry {
    static let shared = SpriteRegistry()

    private let views = NSHashTable<SpriteView.SpriteNSView>.weakObjects()

    func add(_ view: SpriteView.SpriteNSView) {
        views.add(view)
    }

    func refreshAll() {
        for view in views.allObjects { view.refresh() }
    }
}
