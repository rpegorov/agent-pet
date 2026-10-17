import AppKit
import SwiftUI

/// One overlay panel on one display: sizing, position persistence per display and click pass-through.
@MainActor
final class PanelHost {
    let display: UInt32
    let context = PanelContext()
    private(set) var columns: [PetColumn] = []

    private let panel: OverlayPanel
    private let defaults = UserDefaults.standard
    private let margin: CGFloat
    private var moveObserver: NSObjectProtocol?
    private var passThrough: PanelPassThrough?
    private var pendingShrink: Task<Void, Never>?

    var isVisible: Bool { panel.isVisible }

    init(display: UInt32, margin: CGFloat, store: PetStore, quiet: QuietMode, actions: any PetActionHandling) {
        self.display = display
        self.margin = margin
        panel = OverlayPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.applyOverlayStyle()
        let hosting = OverlayHostingView(rootView: PetRowView(store: store, context: context, actions: actions))
        hosting.sizingOptions = []
        panel.contentView = hosting
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveAnchor() }
        }
        passThrough = PanelPassThrough(
            panel: panel,
            forceIgnore: { [quiet] in quiet.clickThrough },
            interactiveRects: { [weak self] in
                guard let self else { return [] }
                return PetRowLayout.interactiveRects(columns: columns, windowFrame: panel.frame)
            })
    }

    func stop() {
        pendingShrink?.cancel()
        pendingShrink = nil
        passThrough?.stop()
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
        panel.orderOut(nil)
    }

    /// Size the panel for `columns`, or hide it when there is nothing to show. Shrinking waits for exit animations.
    func update(columns newColumns: [PetColumn], hidden: Bool, exitDelay: Duration) {
        columns = newColumns
        pendingShrink?.cancel()
        pendingShrink = nil
        let target = hidden || newColumns.isEmpty ? nil : PetRowLayout.windowSize(columns: newColumns)
        guard !hidden, panel.isVisible, shrinks(to: target) else {
            apply(size: target)
            return
        }
        pendingShrink = Task { [weak self] in
            do {
                try await Task.sleep(for: exitDelay)
            } catch {
                return
            }
            guard let self else { return }
            apply(size: columns.isEmpty ? nil : PetRowLayout.windowSize(columns: columns))
        }
    }

    private func shrinks(to size: CGSize?) -> Bool {
        guard let size else { return true }
        return size.width < panel.frame.width || size.height < panel.frame.height
    }

    private func apply(size: CGSize?) {
        guard let size, let screen = screen else {
            panel.orderOut(nil)
            passThrough?.stop()
            return
        }
        let anchor = currentAnchor(on: screen)
        let frame = NSRect(x: anchor.x - size.width, y: anchor.y, width: size.width, height: size.height)
        panel.setFrame(
            PanelPlacement.clamped(frame, visibleFrames: [screen.visibleFrame], fallback: screen.visibleFrame),
            display: true)
        panel.orderFrontRegardless()
        passThrough?.start()
    }

    private var screen: NSScreen? {
        NSScreen.screens.first { $0.displayID == display }
    }

    private var anchorKeys: (x: String, y: String) {
        ("overlay.anchor.\(display).x", "overlay.anchor.\(display).y")
    }

    /// Bottom-right corner of the panel; the row grows leftwards and upwards from it.
    private func currentAnchor(on screen: NSScreen) -> CGPoint {
        if panel.isVisible, screen.frame.contains(CGPoint(x: panel.frame.maxX - 1, y: panel.frame.minY + 1)) {
            return CGPoint(x: panel.frame.maxX, y: panel.frame.minY)
        }
        let keys = anchorKeys
        guard defaults.object(forKey: keys.x) != nil else {
            return legacyAnchor(on: screen) ?? PanelPlacement.defaultAnchor(in: screen.visibleFrame, margin: margin)
        }
        let saved = CGPoint(x: defaults.double(forKey: keys.x), y: defaults.double(forKey: keys.y))
        return PanelPlacement.restoredAnchor(
            saved, visibleFrames: [screen.visibleFrame], fallback: screen.visibleFrame, margin: margin)
    }

    // The single-panel layout stored one global anchor; it seeds the display it lies on.
    private func legacyAnchor(on screen: NSScreen) -> CGPoint? {
        guard defaults.object(forKey: "overlay.anchor.x") != nil else { return nil }
        let point = CGPoint(x: defaults.double(forKey: "overlay.anchor.x"), y: defaults.double(forKey: "overlay.anchor.y"))
        return screen.frame.insetBy(dx: -1, dy: -1).contains(point)
            ? PanelPlacement.restoredAnchor(point, visibleFrames: [screen.visibleFrame], fallback: screen.visibleFrame, margin: margin)
            : nil
    }

    private func saveAnchor() {
        guard panel.isVisible, let screen, screen.frame.contains(CGPoint(x: panel.frame.maxX - 1, y: panel.frame.minY + 1)) else { return }
        let keys = anchorKeys
        defaults.set(panel.frame.maxX, forKey: keys.x)
        defaults.set(panel.frame.minY, forKey: keys.y)
    }
}
