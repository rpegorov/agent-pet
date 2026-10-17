import CoreGraphics

/// Where the panel may sit: always fully inside the visible area of one display, falling back to the main one.
enum PanelPlacement {
    static func defaultAnchor(in visible: CGRect, margin: CGFloat) -> CGPoint {
        CGPoint(x: visible.maxX - margin, y: visible.minY + margin)
    }

    /// A saved anchor whose display is gone moves onto the fallback display, keeping a margin above its bottom edge.
    static func restoredAnchor(_ saved: CGPoint, visibleFrames: [CGRect], fallback: CGRect, margin: CGFloat) -> CGPoint {
        guard let visible = visibleFrames.first(where: { $0.insetBy(dx: -1, dy: -1).contains(saved) }) else {
            return CGPoint(
                x: min(max(saved.x, fallback.minX), fallback.maxX),
                y: fallback.minY + margin)
        }
        return CGPoint(x: saved.x, y: max(saved.y, visible.minY + margin))
    }

    /// Keeps the whole frame inside the visible area of the display holding its bottom-right corner.
    static func clamped(_ frame: CGRect, visibleFrames: [CGRect], fallback: CGRect) -> CGRect {
        let corner = CGPoint(x: frame.maxX - 1, y: frame.minY + 1)
        let visible = visibleFrames.first { $0.contains(corner) } ?? fallback
        var result = frame
        result.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
        result.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
        return result
    }
}
