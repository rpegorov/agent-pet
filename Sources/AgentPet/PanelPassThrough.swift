import AppKit

/// Lets clicks fall through the transparent parts of the panel by toggling `ignoresMouseEvents`
/// according to whether the cursor is over something interactive.
@MainActor
final class PanelPassThrough {
    private static let pollInterval: TimeInterval = 0.08

    private let panel: NSPanel
    private let forceIgnore: () -> Bool
    private let interactiveRects: () -> [NSRect]
    private var timer: Timer?

    init(panel: NSPanel, forceIgnore: @escaping () -> Bool, interactiveRects: @escaping () -> [NSRect]) {
        self.panel = panel
        self.forceIgnore = forceIgnore
        self.interactiveRects = interactiveRects
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let ignore: Bool
        if forceIgnore() {
            ignore = true
        } else if NSEvent.pressedMouseButtons != 0 {
            return
        } else {
            let location = NSEvent.mouseLocation
            ignore = !interactiveRects().contains { $0.contains(location) }
        }
        if panel.ignoresMouseEvents != ignore {
            panel.ignoresMouseEvents = ignore
        }
    }
}
