import AppKit
import SwiftUI

/// Catches clicks, drags and right clicks on a pet; a drag moves the whole window.
struct PetHitArea: NSViewRepresentable {
    let onClick: () -> Void
    let onRightClick: (NSEvent, NSView) -> Void

    func makeNSView(context: Context) -> HitView {
        let view = HitView()
        view.onClick = onClick
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ view: HitView, context: Context) {
        view.onClick = onClick
        view.onRightClick = onRightClick
    }

    final class HitView: NSView {
        private static let dragThreshold: CGFloat = 4

        var onClick: () -> Void = {}
        var onRightClick: (NSEvent, NSView) -> Void = { _, _ in }
        private var downPoint: NSPoint = .zero
        private var dragging = false

        override var mouseDownCanMoveWindow: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            Log.interaction.info("mouse down on a pet")
            downPoint = event.locationInWindow
            dragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard !dragging else { return }
            let dx = event.locationInWindow.x - downPoint.x
            let dy = event.locationInWindow.y - downPoint.y
            guard hypot(dx, dy) >= Self.dragThreshold else { return }
            dragging = true
            window?.performDrag(with: event)
        }

        override func mouseUp(with event: NSEvent) {
            if !dragging {
                Log.interaction.info("click on a pet")
                onClick()
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            onRightClick(event, self)
        }
    }
}
