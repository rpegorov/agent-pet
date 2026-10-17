import AppKit
import CoreGraphics

/// Detects a frontmost application window that covers an entire screen.
enum FullScreenDetector {
    struct Snapshot: Sendable {
        let ownPID: Int32
        let screens: [Screen]
    }

    struct Screen: Sendable {
        let id: UInt32
        let frame: CGRect
    }

    private static let tolerance: CGFloat = 1.5
    private static let regularWindowLayer = 0

    /// Captures what must be read on the main thread, in Quartz coordinates. Nil without a screen.
    @MainActor static func snapshot() -> Snapshot? {
        guard let primary = NSScreen.screens.first else { return nil }
        let screens = NSScreen.screens.compactMap { screen in
            screen.displayID.map { Screen(id: $0, frame: cgFrame(of: screen.frame, primaryHeight: primary.frame.height)) }
        }
        return Snapshot(ownPID: ProcessInfo.processInfo.processIdentifier, screens: screens)
    }

    /// Safe to call off the main thread.
    static func coveredDisplays(_ snapshot: Snapshot) -> Set<UInt32> {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let bounds: [CGRect] = windows.compactMap { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != snapshot.ownPID,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == regularWindowLayer,
                  let dictionary = window[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: dictionary)
        }
        return covered(screens: snapshot.screens, windows: bounds)
    }

    /// Displays that have a window filling them; windows on other displays do not count.
    static func covered(screens: [Screen], windows: [CGRect]) -> Set<UInt32> {
        Set(screens.filter { screen in windows.contains { matches($0, screen.frame) } }.map(\.id))
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
