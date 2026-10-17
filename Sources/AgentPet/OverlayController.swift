import AppKit
import SwiftUI

/// Owns the panel: shows it while pets exist, sizes it to the row and remembers where the user put it.
@MainActor
final class OverlayController {
    private enum DefaultsKey {
        static let anchorX = "overlay.anchor.x"
        static let anchorY = "overlay.anchor.y"
    }

    private static let screenMargin: CGFloat = 24
    private static let exitAnimation: Duration = .milliseconds(300)

    private let store: PetStore
    private let quiet: QuietMode
    private let panel: OverlayPanel
    private let defaults = UserDefaults.standard
    private var moveObserver: NSObjectProtocol?
    private var pendingShrink: Task<Void, Never>?
    private var passThrough: PanelPassThrough?

    init(store: PetStore, quiet: QuietMode, actions: any PetActionHandling) {
        self.store = store
        self.quiet = quiet
        panel = OverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.applyOverlayStyle()
        let hosting = OverlayHostingView(rootView: PetRowView(store: store, actions: actions))
        hosting.sizingOptions = []
        panel.contentView = hosting
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveAnchor() }
        }
        quiet.panelFrame = { [panel] in panel.isVisible ? panel.frame : nil }
        installPassThrough()
        observe()
    }

    private func installPassThrough() {
        let monitor = PanelPassThrough(
            panel: panel,
            forceIgnore: { [quiet] in quiet.clickThrough },
            interactiveRects: { [store, panel] in
                PetRowLayout.interactiveRects(columns: store.columns(), windowFrame: panel.frame)
            }
        )
        passThrough = monitor
    }

    func stop() {
        pendingShrink?.cancel()
        pendingShrink = nil
        passThrough?.stop()
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
        moveObserver = nil
    }

    /// Re-arms itself after each change, so the window follows the store and the quiet modes.
    private func observe() {
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() } // lint-allow: sw-unowned-task single hop that re-arms observation
        }
    }

    private func update() {
        let target = targetSize()
        pendingShrink?.cancel()
        pendingShrink = nil
        guard !quiet.isSuppressed, panel.isVisible, shrinks(to: target) else {
            apply(size: target)
            return
        }
        // Lets pets that just left finish fading before the window gives up their room.
        pendingShrink = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.exitAnimation)
            } catch {
                return
            }
            guard let self else { return }
            apply(size: targetSize())
        }
    }

    private func targetSize() -> CGSize? {
        let columns = store.columns()
        guard !columns.isEmpty, !quiet.isSuppressed else { return nil }
        return PetRowLayout.windowSize(columns: columns)
    }

    private func shrinks(to size: CGSize?) -> Bool {
        guard let size else { return true }
        return size.width < panel.frame.width || size.height < panel.frame.height
    }

    private func apply(size: CGSize?) {
        guard let size else {
            panel.orderOut(nil)
            passThrough?.stop()
            return
        }
        let anchor = currentAnchor()
        let frame = NSRect(x: anchor.x - size.width, y: anchor.y, width: size.width, height: size.height)
        panel.setFrame(clamped(frame), display: true)
        panel.orderFrontRegardless()
        passThrough?.start()
    }

    /// Bottom-right corner of the window; the row grows leftwards and upwards from it.
    private func currentAnchor() -> CGPoint {
        if panel.isVisible {
            return CGPoint(x: panel.frame.maxX, y: panel.frame.minY)
        }
        if defaults.object(forKey: DefaultsKey.anchorX) != nil {
            let saved = CGPoint(x: defaults.double(forKey: DefaultsKey.anchorX), y: defaults.double(forKey: DefaultsKey.anchorY))
            guard let visible = visibleFrame(containing: saved) else { return saved }
            return CGPoint(x: saved.x, y: max(saved.y, visible.minY + Self.screenMargin))
        }
        let visible = NSScreen.main?.visibleFrame ?? .zero
        return CGPoint(x: visible.maxX - Self.screenMargin, y: visible.minY + Self.screenMargin)
    }

    private func visibleFrame(containing point: CGPoint) -> NSRect? {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        return screen?.visibleFrame
    }

    /// Keeps the whole panel inside the visible area of the screen holding its bottom-right corner.
    private func clamped(_ frame: NSRect) -> NSRect {
        let corner = CGPoint(x: frame.maxX - 1, y: frame.minY + 1)
        guard let visible = visibleFrame(containing: corner) else { return frame }
        var result = frame
        result.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
        result.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
        return result
    }

    private func saveAnchor() {
        guard panel.isVisible else { return }
        defaults.set(panel.frame.maxX, forKey: DefaultsKey.anchorX)
        defaults.set(panel.frame.minY, forKey: DefaultsKey.anchorY)
    }
}
