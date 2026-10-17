import AppKit
import CoreGraphics

/// Detects a frontmost application window that covers an entire screen.
enum FullScreenDetector {
    struct Snapshot: Sendable {
        let ownPID: Int32
        let panelFrame: CGRect
        let screenFrames: [CGRect]
    }

    private static let tolerance: CGFloat = 1.5
    private static let regularWindowLayer = 0

    /// Captures what must be read on the main thread, in Quartz coordinates. Nil without a screen.
    @MainActor static func snapshot(panelFrame: NSRect?) -> Snapshot? {
        guard let primary = NSScreen.screens.first else { return nil }
        let frames = NSScreen.screens.map { cgFrame(of: $0.frame, primaryHeight: primary.frame.height) }
        let panel = (panelFrame ?? NSScreen.main?.frame ?? primary.frame)
        return Snapshot(
            ownPID: ProcessInfo.processInfo.processIdentifier,
            panelFrame: cgFrame(of: panel, primaryHeight: primary.frame.height),
            screenFrames: frames)
    }

    /// Safe to call off the main thread.
    static func isCovering(_ snapshot: Snapshot) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let bounds: [CGRect] = windows.compactMap { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != snapshot.ownPID,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == regularWindowLayer,
                  let dictionary = window[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: dictionary)
        }
        return covers(panelFrame: snapshot.panelFrame, screens: snapshot.screenFrames, windows: bounds)
    }

    /// True when a window fills the display that holds the panel; windows on other displays do not count.
    static func covers(panelFrame: CGRect, screens: [CGRect], windows: [CGRect]) -> Bool {
        let overlaps = screens.map { (screen: $0, area: area($0.intersection(panelFrame))) }
        guard let home = overlaps.max(by: { $0.area < $1.area }), home.area > 0 else { return false }
        return windows.contains { matches($0, home.screen) }
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    // Quartz window bounds use a top-left origin anchored at the primary screen.
    static func cgFrame(of frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    static func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }
}
